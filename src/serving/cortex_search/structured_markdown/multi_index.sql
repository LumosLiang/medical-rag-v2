-- Multi-index：正文与完整 section_path 各建关键词索引，仅正文建向量索引。
-- 不占用正文 embedding 窗口；章节是否有贡献取决于解析标题和查询中的字段权重。
-- 服务定义未写入调参权重：默认请求保持默认；实验请求用 texts:vectors:reranker=1:1:3，
-- 且 text_boosts 为正文 1、章节 3。该候选未成为应用默认，具体 JSON 见 ../README.md。

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
