-- 单次 recursive 切分。只由 CHUNK_DOC 调用；事务和验收由 CHUNK_DOC 负责。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE PROCEDURE CORE.CHUNK_RECURSIVE_BASELINE(
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
COMMENT = 'medrag v2: insert one-pass recursive chunks inside CHUNK_DOC transaction'
EXECUTE AS OWNER
AS
$$
BEGIN
  INSERT INTO IDENTIFIER(:p_target_table) (
    chunk_id, doc_id, relative_path, etag, config_name, chunk_index,
    section_path, chunk_text, chunk_text_raw, token_count, page_start, page_end
  )
  WITH pieces AS (
    SELECT p.doc_id, page.value:index::NUMBER AS page_index,
           piece.index AS piece_index, piece.value::VARCHAR AS chunk_text
      FROM INGEST.PARSED_DOCS p,
           LATERAL FLATTEN(input => p.parse_result:value:pages) page,
           LATERAL FLATTEN(input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
             page.value:content::VARCHAR, :p_format, :p_chunk_size, :p_overlap
           )) piece
     WHERE p.relative_path = :p_relative_path
       AND p.etag = :p_etag
       AND p.error_message IS NULL
  ),

  numbered AS (
    SELECT doc_id, page_index, chunk_text,
           ROW_NUMBER() OVER (ORDER BY page_index, piece_index) - 1 AS chunk_index
      FROM pieces
     WHERE NULLIF(TRIM(chunk_text), '') IS NOT NULL
  )

  SELECT SHA2(:p_relative_path || '|' || :p_etag || '|' || :p_config_name || '|' || chunk_index::VARCHAR, 256),
         doc_id, :p_relative_path, :p_etag, :p_config_name, chunk_index,
         NULL, chunk_text, chunk_text,
         SNOWFLAKE.CORTEX.COUNT_TOKENS(:p_token_model, chunk_text),
         page_index, page_index
    FROM numbered;

  RETURN 'OK';
END;
$$;
