-- 8K 长窗口配置：完整章节关键词索引 + 正文向量索引；请求权重与原服务一致。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_INDEX_WH;

CREATE CORTEX SEARCH SERVICE IF NOT EXISTS CORE.MEDICAL_CHUNKS_STRUCTURED_MARKDOWN_8K_BODY_1024
  TEXT INDEXES chunk_text, section_path
  VECTOR INDEXES chunk_text (model = 'snowflake-arctic-embed-l-v2.0-8k')
  PRIMARY KEY (chunk_id)
  ATTRIBUTES doc_id, relative_path, config_name
  WAREHOUSE = MEDICAL_RAG_INDEX_WH
  TARGET_LAG = '1 hour'
AS
  SELECT chunk_id, chunk_text, doc_id, relative_path, etag, config_name,
         chunk_index, section_path, page_start, page_end, token_count
    FROM CORE.CHUNKS
   WHERE config_name = 'structured_markdown_8k_body_1024';
