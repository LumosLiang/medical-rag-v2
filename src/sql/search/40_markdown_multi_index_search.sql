-- 实验 B：正文和章节路径分别参与关键词检索，正文单独做 embedding。
-- 本轮不加标题向量、不调权重；先测原生默认行为，避免同时改变多个因素。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_INDEX_WH;

CREATE CORTEX SEARCH SERVICE IF NOT EXISTS CORE.MEDICAL_CHUNKS_MARKDOWN_MULTI_INDEX_1200_200
  TEXT INDEXES chunk_text, section_path
  VECTOR INDEXES chunk_text (model = 'snowflake-arctic-embed-l-v2.0')
  PRIMARY KEY (chunk_id)
  ATTRIBUTES doc_id, relative_path, config_name
  WAREHOUSE = MEDICAL_RAG_INDEX_WH
  TARGET_LAG = '1 hour'
AS
  SELECT chunk_id, chunk_text, doc_id, relative_path, etag, config_name,
         chunk_index, section_path, page_start, page_end, token_count
    FROM CORE.CHUNKS
   WHERE config_name = 'markdown_header_table_1200_200';
