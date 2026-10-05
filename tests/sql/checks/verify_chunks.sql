-- 回填后的块验收,只读。任一配置都适用,改 config_name 即可。
-- 硬上限:基线 recursive_once_1200_200 允许超 512 token(只观察);其余配置 invalid_tokens 必须为 0。
-- 空块、重复 ID、错误页码、错误版本、缺文档都必须为 0。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_PARSE_WH;

SET snapshot_name = 'corpus_2026_10_03';
SET config_name   = 'markdown_header_table_1200_200';

-- 1. 总量、token、空块、页码范围、跨页块、重复 ID。
SELECT COUNT(DISTINCT relative_path) AS files,
       COUNT(*) AS chunks,
       MAX(token_count) AS max_tokens,
       COUNT_IF(token_count IS NULL OR token_count > 512) AS invalid_tokens,
       COUNT_IF(NULLIF(TRIM(chunk_text_raw), '') IS NULL) AS empty_chunks,
       COUNT_IF(page_start IS NULL OR page_end IS NULL OR page_start > page_end) AS invalid_pages,
       COUNT_IF(page_start < page_end) AS across_pages,
       COUNT(*) - COUNT(DISTINCT chunk_id) AS duplicate_ids
  FROM CORE.CHUNKS
 WHERE config_name = $config_name;

-- 2. 块必须来自快照里的那个文件版本,页码落在该版本解析结果的页数之内。
SELECT COUNT(*) AS wrong_version_or_page
  FROM CORE.CHUNKS c
  LEFT JOIN EVAL.CORPUS_FILES f
    ON f.snapshot_name = $snapshot_name
   AND f.relative_path = c.relative_path
   AND f.etag = c.etag
  LEFT JOIN INGEST.PARSED_DOCS d
    ON d.relative_path = c.relative_path
   AND d.etag = c.etag
   AND d.error_message IS NULL
 WHERE c.config_name = $config_name
   AND (f.doc_id IS NULL
        OR d.doc_id IS NULL
        OR c.page_start < 0
        OR c.page_end >= ARRAY_SIZE(d.parse_result:value:pages));

-- 3. 快照里一块都没有的文档。
SELECT f.doc_id AS missing_doc
  FROM EVAL.CORPUS_FILES f
  LEFT JOIN CORE.CHUNKS c
    ON c.relative_path = f.relative_path
   AND c.etag = f.etag
   AND c.config_name = $config_name
 WHERE f.snapshot_name = $snapshot_name
 GROUP BY f.doc_id
HAVING COUNT(c.chunk_id) = 0;

-- 4. 回填不应改变日常入库用的 active 配置。
SELECT config_name, is_active
  FROM CORE.PIPELINE_CONFIG
 WHERE is_active
    OR config_name = $config_name;
