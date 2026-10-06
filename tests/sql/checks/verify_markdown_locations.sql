-- markdown_header_table 专用,只读:重算正文初次切分的定位率。
-- 表格位置直接由 EXTRACT_MARKDOWN_ELEMENTS 给出,不在这里统计;补切后代保留母块范围,也不计为新的精确定位。
-- 验收线:fallback_percent < 0.5,missing_pages = 0。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_PARSE_WH;
ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 180;

SET snapshot_name = 'corpus_2026_10_03';
SET config_name   = 'markdown_header_table_1200_200';

WITH documents AS (
  SELECT d.doc_id,
         CORE.PREPARE_MARKDOWN_DOCUMENT(d.parse_result:value:pages::ARRAY) AS document,
         c.split_headers, c.chunk_size_chars, c.chunk_overlap_chars
    FROM INGEST.PARSED_DOCS d
    JOIN EVAL.CORPUS_FILES f
      ON f.relative_path = d.relative_path
     AND f.etag = d.etag
    JOIN CORE.PIPELINE_CONFIG c
      ON c.config_name = $config_name
   WHERE f.snapshot_name = $snapshot_name
     AND d.error_message IS NULL
),
candidates AS (
  SELECT d.doc_id, d.document, s.span_index,
         c.index AS piece_index,
         OBJECT_CONSTRUCT(
           'kind', 'TEXT',
           'text', c.value:chunk::VARCHAR,
           'headers', c.value:headers,
           'span_index', s.span_index,
           'span_start', s.source_start,
           'span_end', s.source_end
         ) AS candidate
    FROM documents d,
         TABLE(CORE.EXTRACT_MARKDOWN_ELEMENTS(d.document:text::VARCHAR)) s,
         LATERAL FLATTEN(input => SNOWFLAKE.CORTEX.SPLIT_TEXT_MARKDOWN_HEADER(
           s.span_text, d.split_headers, d.chunk_size_chars, d.chunk_overlap_chars
         )) c
   WHERE s.span_type = 'TEXT'
     AND NULLIF(TRIM(c.value:chunk::VARCHAR), '') IS NOT NULL
),
grouped AS (
  SELECT doc_id, document,
         ARRAY_AGG(candidate) WITHIN GROUP (ORDER BY span_index, piece_index) AS pieces
    FROM candidates
   GROUP BY doc_id, document
),
located AS (
  SELECT g.doc_id, l.*
    FROM grouped g,
         TABLE(CORE.ANNOTATE_CHUNK_LOCATIONS(g.document, g.pieces)) l
)
SELECT COUNT(*) AS text_candidates,
       COUNT_IF(NOT location_exact) AS span_range_fallback,
       ROUND(100.0 * COUNT_IF(NOT location_exact) / COUNT(*), 3) AS fallback_percent,
       COUNT_IF(page_start IS NULL OR page_end IS NULL) AS missing_pages
  FROM located;
