-- 一个切分配置对应一个搜索服务；服务名后缀与 config_name 相同。
-- 当前只部署默认配置的服务，其他配置需要时另建服务。
-- 首次建服务用 IF NOT EXISTS；修改模型或源查询时需单独评估重建。
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
