-- 模型对照：原 512 窗口切分结果不变，只换 Arctic 8K embedding 模型。
-- 关键词索引为正文和完整章节路径，向量输入为正文；请求权重由调用方提供。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_INDEX_WH;

CREATE CORTEX SEARCH SERVICE IF NOT EXISTS CORE.MEDICAL_CHUNKS_MARKDOWN_8K_CONTROL
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
   WHERE config_name = 'markdown_header_table_1200_200';
