-- 策略入口：准备全文 → 分正文/表格 → 定位 → 仅超限块补切 → 写入并验硬上限。
-- 各个 Python helper 只做一件事；原生切分和 COUNT_TOKENS 留在 SQL。
-- 由 CHUNK_DOC 调用；此处不建临时表、不提交事务，失败由外层恢复旧块。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE PROCEDURE CORE.CHUNK_MARKDOWN_HEADER_TABLE(
  p_relative_path VARCHAR,
  p_etag          VARCHAR,
  p_config_name   VARCHAR,
  p_target_table  VARCHAR,
  p_format        VARCHAR,
  p_chunk_size    INTEGER,
  p_overlap       INTEGER,
  p_token_model   VARCHAR,
  p_resplit_size  INTEGER,
  p_max_tokens    INTEGER
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  v_document   OBJECT;
  v_doc_id     VARCHAR;
  v_headers    OBJECT;
  v_candidates ARRAY;
  v_over_limit INTEGER;
  -- 450 是表格分组的软目标，留出余量；不是字符长度，也不是最终硬上限。
  v_table_target_tokens INTEGER DEFAULT 450;
  over_limit EXCEPTION (-20116, 'CHUNK_MARKDOWN_HEADER_TABLE: NULL token count or a chunk exceeds max_tokens');
BEGIN
  SELECT doc_id, CORE.NORMALIZE_MARKDOWN_PAGES(parse_result:value:pages::ARRAY)
    INTO :v_doc_id, :v_document
    FROM INGEST.PARSED_DOCS
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND error_message IS NULL;

  SELECT split_headers
    INTO :v_headers
    FROM CORE.PIPELINE_CONFIG
   WHERE config_name = :p_config_name;

  -- 候选块按原文 span 顺序排列。表格文本含重复前缀，位置取其实际数据行范围。
  WITH spans AS (
    SELECT *
      FROM TABLE(CORE.SPLIT_TABLE_SPANS(:v_document:text::VARCHAR))
  ),
  counted_tables AS (
    SELECT s.span_index, s.source_start, s.source_end, s.table_data,
           ARRAY_AGG(
             IFF(r.index IS NOT NULL,
                 OBJECT_INSERT(r.value, 'tokens',
                   SNOWFLAKE.CORTEX.COUNT_TOKENS(:p_token_model, r.value:text::VARCHAR)),
                 NULL)
           ) WITHIN GROUP (ORDER BY r.index) AS counted_rows
      FROM spans s,
           LATERAL FLATTEN(input => s.table_data:rows, outer => TRUE) r
     WHERE s.span_type = 'TABLE'
     GROUP BY s.span_index, s.source_start, s.source_end, s.table_data
  ),
  candidates AS (
    SELECT s.span_index,
           c.index AS piece_index,
           OBJECT_CONSTRUCT(
             'kind', 'TEXT',
             'span_index', s.span_index,
             'span_start', s.source_start,
             'span_end', s.source_end,
             'text', c.value:chunk::VARCHAR,
             'headers', c.value:headers
           ) AS candidate
      FROM spans s,
           LATERAL FLATTEN(input => SNOWFLAKE.CORTEX.SPLIT_TEXT_MARKDOWN_HEADER(
             s.span_text, :v_headers, :p_chunk_size, :p_overlap
           )) c
     WHERE s.span_type = 'TEXT'
       AND NULLIF(TRIM(c.value:chunk::VARCHAR), '') IS NOT NULL
    UNION ALL
    SELECT t.span_index,
           p.piece_index,
           OBJECT_CONSTRUCT(
             'kind', 'TABLE',
             'text', p.chunk_text,
             'start', p.source_start,
             'end', p.source_end
           )
      FROM counted_tables t,
           TABLE(CORE.PACK_TABLE_ROWS(
             OBJECT_INSERT(
               OBJECT_INSERT(t.table_data, 'rows', t.counted_rows, TRUE),
               'prefix_tokens',
               SNOWFLAKE.CORTEX.COUNT_TOKENS(:p_token_model, t.table_data:prefix::VARCHAR)
             ),
             :v_table_target_tokens
           )) p
  )
  SELECT ARRAY_AGG(candidate) WITHIN GROUP (ORDER BY span_index, piece_index)
    INTO :v_candidates
    FROM candidates;

  INSERT INTO IDENTIFIER(:p_target_table) (
    chunk_id, doc_id, relative_path, etag, config_name, chunk_index,
    section_path, chunk_text, chunk_text_raw, token_count, page_start, page_end
  )
  WITH RECURSIVE located AS (
    SELECT *,
           SNOWFLAKE.CORTEX.COUNT_TOKENS(:p_token_model, chunk_text) AS token_count
      FROM TABLE(CORE.LOCATE_MARKDOWN_CHUNKS(:v_document, :v_candidates))
  ),
  split_tree (
    sort_path, chunk_text, token_count, section_path, page_start, page_end, split_size
  ) AS (
    SELECT LPAD(piece_index::VARCHAR, 6, '0')::VARCHAR(4096), chunk_text, token_count,
           section_path, page_start, page_end, :p_resplit_size
      FROM located
    UNION ALL
    -- 复用补切版的递归规则，尺寸逐次减半；正常正文与表格不经过这一步。
    -- 表格兜底不能保证每个后代重复完整表头。后代保留母块的页码范围和章节。
    SELECT t.sort_path || '.' || LPAD(child.index::VARCHAR, 6, '0'),
           child.value::VARCHAR,
           SNOWFLAKE.CORTEX.COUNT_TOKENS(:p_token_model, child.value::VARCHAR),
           t.section_path, t.page_start, t.page_end,
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
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY sort_path) - 1 AS chunk_index
      FROM split_tree
     WHERE (token_count <= :p_max_tokens OR split_size <= 1)
       AND NULLIF(TRIM(chunk_text), '') IS NOT NULL
  )
  SELECT SHA2(:p_relative_path || '|' || :p_etag || '|' || :p_config_name || '|'
              || chunk_index::VARCHAR, 256),
         :v_doc_id, :p_relative_path, :p_etag, :p_config_name, chunk_index,
         section_path, chunk_text, chunk_text, token_count, page_start, page_end
    FROM numbered;

  SELECT COUNT_IF(token_count IS NULL OR token_count > :p_max_tokens)
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
