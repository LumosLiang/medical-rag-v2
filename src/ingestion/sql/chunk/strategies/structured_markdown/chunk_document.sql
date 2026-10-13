-- CHUNK_STRUCTURED_MARKDOWN 协调“章节正文 + 独立表格”的切分流程，而不是单独调用一个 splitter。
-- 准备全文 → 提取元素 → 原生标题切正文 / 保上下文组表格 → 标注章节页码 → 超限补切 → 写块。
-- Python helper 负责确定性结构处理；标题切分和精确 token 计数使用 Snowflake 原生函数。
-- CHUNK_DOC 提供同版本、同配置的替换事务；本过程只生成结果和执行策略的 token 验收。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE PROCEDURE CORE.CHUNK_STRUCTURED_MARKDOWN(
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
  v_options    OBJECT;
  v_body_target_tokens INTEGER;
  -- 450 是表格分组的软目标，留出余量；不是字符长度，也不是最终硬上限。
  v_table_target_tokens INTEGER DEFAULT 450;
  over_limit EXCEPTION (-20116, 'CHUNK_STRUCTURED_MARKDOWN: NULL token count or a chunk exceeds max_tokens');
BEGIN
  SELECT doc_id, CORE.PREPARE_MARKDOWN_DOCUMENT(parse_result:value:pages::ARRAY)
    INTO :v_doc_id, :v_document
    FROM INGEST.PARSED_DOCS
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND error_message IS NULL;

  SELECT split_headers, COALESCE(method_options, OBJECT_CONSTRUCT())
    INTO :v_headers, :v_options
    FROM CORE.PIPELINE_CONFIG
   WHERE config_name = :p_config_name;

  -- 老配置 options 为空，保持原流程；新配置只打开显式选择的处理。
  v_document := CORE.CLEAN_MARKDOWN_DOCUMENT(v_document, v_options);
  v_body_target_tokens := COALESCE(v_options:body_target_tokens::INTEGER, p_max_tokens);
  v_table_target_tokens := COALESCE(v_options:table_target_tokens::INTEGER, 450);

  -- 候选块按原文 span 顺序排列。表格文本含重复前缀，位置取其实际数据行范围。
  -- 1. 段结构：TEXT 交给标题切分；TABLE 交给行组器，两路最后按原文顺序合并。
  WITH raw_spans AS (
    SELECT * FROM TABLE(CORE.EXTRACT_MARKDOWN_ELEMENTS(:v_document:text::VARCHAR))
  ),
  spans AS (
    SELECT a.source_start AS span_index, a.span_type, a.source_start, a.source_end,
           a.piece_text AS span_text, NULL::OBJECT AS table_data
      FROM raw_spans s,
           TABLE(CORE.SPLIT_ABSTRACT_SPANS(s.span_text, s.source_start, :v_document:abstracts::ARRAY)) a
     WHERE s.span_type = 'TEXT'
    UNION ALL
    SELECT source_start, span_type, source_start, source_end, span_text,
           CORE.ATTACH_TABLE_NOTES(table_data, :v_document:text::VARCHAR, source_end,
             COALESCE(:v_options:attach_table_notes::BOOLEAN, FALSE))
      FROM raw_spans WHERE span_type = 'TABLE'
  ),
  -- 2. 每行只计数一次，避免尝试添加每一行都重新计数整个表格。
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
  -- 3. 原生 header splitter 自带尺寸/overlap 切分，正常正文不用再 recursive 一遍。
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
    -- 摘要不经过标题细切；超出模型硬上限时才进入末尾的递归兜底。
    SELECT s.span_index, 0,
           OBJECT_CONSTRUCT('kind', 'ABSTRACT', 'span_index', s.span_index,
             'span_start', s.source_start, 'span_end', s.source_end, 'text', TRIM(s.span_text))
      FROM spans s WHERE s.span_type = 'ABSTRACT'
    UNION ALL
    SELECT t.span_index,
           p.piece_index,
           OBJECT_CONSTRUCT(
             'kind', 'TABLE',
             'text', p.chunk_text,
             'start', IFF(COALESCE(:v_options:attach_table_notes::BOOLEAN, FALSE), LEAST(t.source_start, p.source_start), p.source_start),
             'end', GREATEST(p.source_end, COALESCE(t.table_data:notes_end::INTEGER, p.source_end))
           )
      FROM counted_tables t,
           TABLE(CORE.BUILD_TABLE_CHUNKS(
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

  -- 4. 先恢复候选块的章节和页码，再精确计数；仅超限的候选进入递归补切。
  INSERT INTO IDENTIFIER(:p_target_table) (
    chunk_id, doc_id, relative_path, etag, config_name, chunk_index,
    section_path, chunk_text, chunk_text_raw, token_count, page_start, page_end
  )
  WITH RECURSIVE located AS (
    SELECT *,
           SNOWFLAKE.CORTEX.COUNT_TOKENS(:p_token_model, chunk_text) AS token_count,
           IFF(GET(:v_candidates, piece_index):kind::VARCHAR = 'TEXT',
               :v_body_target_tokens, :p_max_tokens) AS token_limit
      FROM TABLE(CORE.ANNOTATE_CHUNK_LOCATIONS(:v_document, :v_candidates))
  ),
  split_tree (
    sort_path, chunk_text, token_count, section_path, page_start, page_end, split_size, token_limit
  ) AS (
    SELECT LPAD(piece_index::VARCHAR, 6, '0')::VARCHAR(4096), chunk_text, token_count,
           section_path, page_start, page_end, :p_resplit_size, token_limit
      FROM located
    UNION ALL
    -- 复用补切版的递归规则，尺寸逐次减半；正常正文与表格不经过这一步。
    -- 表格兜底不能保证每个后代重复完整表头。后代保留母块的页码范围和章节。
    SELECT t.sort_path || '.' || LPAD(child.index::VARCHAR, 6, '0'),
           child.value::VARCHAR,
           SNOWFLAKE.CORTEX.COUNT_TOKENS(:p_token_model, child.value::VARCHAR),
           t.section_path, t.page_start, t.page_end,
           GREATEST(1, FLOOR(t.split_size / 2)), t.token_limit
      FROM split_tree t,
           LATERAL FLATTEN(input => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(
             t.chunk_text, :p_format, t.split_size,
             LEAST(:p_overlap, FLOOR(t.split_size / 5))
           )) child
     WHERE (t.token_count IS NULL OR t.token_count > t.token_limit)
       AND t.split_size > 1
  ),
  numbered AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY sort_path) - 1 AS chunk_index
      FROM split_tree
     WHERE (token_count <= token_limit OR split_size <= 1)
       AND NULLIF(TRIM(chunk_text), '') IS NOT NULL
  )
  SELECT SHA2(:p_relative_path || '|' || :p_etag || '|' || :p_config_name || '|'
              || chunk_index::VARCHAR, 256),
         :v_doc_id, :p_relative_path, :p_etag, :p_config_name, chunk_index,
         section_path, chunk_text, chunk_text, token_count, page_start, page_end
    FROM numbered;

  -- 5. 算法自己执行硬上限验收，外层 CHUNK_DOC 的通用验收不检查这个上限。
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
