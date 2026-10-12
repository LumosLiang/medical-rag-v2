-- 基线：只索引 recursive_once_1200_200 的逐页 recursive 块。
-- ON chunk_text 使用同一正文做关键词检索、向量检索及原生重排，查询不指定权重时用默认值。
-- 模型 snowflake-arctic-embed-l-v2.0；源块允许超过 512 token，向量输入可能截断，关键词仍用全文。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_INDEX_WH;

CREATE CORTEX SEARCH SERVICE IF NOT EXISTS CORE.MEDICAL_CHUNKS_RECURSIVE_ONCE_1200_200
  ON chunk_text
  PRIMARY KEY (chunk_id)
  ATTRIBUTES doc_id, relative_path, config_name
  WAREHOUSE = MEDICAL_RAG_INDEX_WH
  TARGET_LAG = '1 hour'
  EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
AS
  SELECT chunk_id, chunk_text, doc_id, relative_path, etag,
         config_name, chunk_index, page_start, page_end, token_count
    FROM CORE.CHUNKS
   WHERE config_name = 'recursive_once_1200_200';
