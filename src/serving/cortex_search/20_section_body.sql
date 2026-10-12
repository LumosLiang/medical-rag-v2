-- 章节表格对照：只索引 markdown_header_table_1200_200，关键词与向量都使用 chunk_text。
-- section_path 只是返回的元数据，不因出现在 SELECT 中就参与搜索；这组用于隔离切分本身的效果。
-- 模型与基线相同，查询默认权重及原生重排；TITLE 信号的两种改进见 30 / 40。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_INDEX_WH;

CREATE CORTEX SEARCH SERVICE IF NOT EXISTS CORE.MEDICAL_CHUNKS_MARKDOWN_HEADER_TABLE_1200_200
  ON chunk_text
  PRIMARY KEY (chunk_id)
  ATTRIBUTES doc_id, relative_path, config_name
  WAREHOUSE = MEDICAL_RAG_INDEX_WH
  TARGET_LAG = '1 hour'
  EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
AS
  SELECT chunk_id, chunk_text, doc_id, relative_path, etag, config_name,
         chunk_index, section_path, page_start, page_end, token_count
    FROM CORE.CHUNKS
   WHERE config_name = 'markdown_header_table_1200_200';
