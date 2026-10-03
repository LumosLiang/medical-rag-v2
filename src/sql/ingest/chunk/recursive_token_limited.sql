-- 超限补切策略。只由 CHUNK_DOC 调用；事务和验收由 CHUNK_DOC 负责。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE PROCEDURE CORE.CHUNK_RECURSIVE(
  p_relative_path VARCHAR,
  p_etag VARCHAR,
  p_config_name VARCHAR,
  p_target_table VARCHAR,
  p_format VARCHAR,
  p_chunk_size INTEGER,
  p_overlap INTEGER,
  p_token_model VARCHAR,
  p_resplit_size INTEGER,
  p_max_tokens INTEGER
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'medrag v2: insert recursively resplit chunks inside CHUNK_DOC transaction'
EXECUTE AS OWNER
AS
$$
DECLARE
  v_over_limit INTEGER;
  over_limit EXCEPTION (-20115, 'CHUNK_RECURSIVE: a chunk still exceeds max_tokens');
BEGIN
  INSERT INTO IDENTIFIER(:p_target_table) (
    chunk_id, doc_id, relative_path, etag, config_name, chunk_index,
    section_path, chunk_text, chunk_text_raw, token_count, page_start, page_end
  )
  WITH RECURSIVE first_pass AS (
    SELECT p.doc_id,
           page.value:index::NUMBER AS page_index,
           piece.index AS piece_index,
           piece.value::VARCHAR AS chunk_text,
           SNOWFLAKE.CORTEX.COUNT_TOKENS(:p_token_model, piece.value::VARCHAR) AS token_count
      FROM INGEST.PARSED_DOCS p,
           LATERAL FLATTEN(input => p.parse_result:value:pages) page,
           LATERAL FLATTEN(input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
             page.value:content::VARCHAR, :p_format, :p_chunk_size, :p_overlap
           )) piece
     WHERE p.relative_path = :p_relative_path
       AND p.etag = :p_etag
       AND p.error_message IS NULL
  ),
  split_tree (doc_id, page_index, sort_path, chunk_text, token_count, split_size) AS (
    SELECT doc_id, page_index, LPAD(piece_index::VARCHAR, 6, '0')::VARCHAR(4096),
           chunk_text, token_count, :p_resplit_size
      FROM first_pass
    UNION ALL
    SELECT t.doc_id, t.page_index,
           t.sort_path || '.' || LPAD(child.index::VARCHAR, 6, '0'),
           child.value::VARCHAR,
           SNOWFLAKE.CORTEX.COUNT_TOKENS(:p_token_model, child.value::VARCHAR),
           GREATEST(1, FLOOR(t.split_size / 2))
      FROM split_tree t,
           LATERAL FLATTEN(input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
             t.chunk_text, :p_format, t.split_size,
             LEAST(:p_overlap, FLOOR(t.split_size / 5))
           )) child
     WHERE (t.token_count IS NULL OR t.token_count > :p_max_tokens)
       AND t.split_size > 1
  ),
  numbered AS (
    SELECT doc_id, page_index, chunk_text, token_count,
           ROW_NUMBER() OVER (ORDER BY page_index, sort_path) - 1 AS chunk_index
      FROM split_tree
     WHERE NULLIF(TRIM(chunk_text), '') IS NOT NULL
       AND (token_count <= :p_max_tokens OR split_size <= 1)
  )
  SELECT SHA2(:p_relative_path || '|' || :p_etag || '|' || :p_config_name || '|' || chunk_index::VARCHAR, 256),
         doc_id, :p_relative_path, :p_etag, :p_config_name, chunk_index,
         NULL, chunk_text, chunk_text, token_count,
         page_index, page_index
    FROM numbered;

  SELECT COUNT_IF(token_count > :p_max_tokens)
    INTO :v_over_limit
    FROM IDENTIFIER(:p_target_table)
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND config_name = :p_config_name;
  IF (v_over_limit > 0) THEN
    RAISE over_limit;
  END IF;

  RETURN 'OK';
END;
$$;
