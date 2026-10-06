-- 标题前缀对照：复用章节表格块，源查询构造“最近一级标题 + 正文”的 search_text。
-- 关键词、embedding 和原生重排使用这个 ON 字段；返回原始 chunk_text，避免把注入标题算作证据。
-- 查询默认权重。取舍是标题占用 512-token 窗口，少量搜索文本会截断；CHUNKS 本身不改。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_INDEX_WH;

CREATE CORTEX SEARCH SERVICE IF NOT EXISTS CORE.MEDICAL_CHUNKS_MARKDOWN_HEADING_PREFIX_1200_200
  ON search_text
  PRIMARY KEY (chunk_id)
  ATTRIBUTES doc_id, relative_path, config_name
  WAREHOUSE = MEDICAL_RAG_INDEX_WH
  TARGET_LAG = '1 hour'
  EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
AS
  SELECT chunk_id, chunk_text, doc_id, relative_path, etag, config_name,
         chunk_index, section_path, page_start, page_end, token_count,
         -- 路径由现有定位过程用 " > " 连接；只取最后一个标题。
         CONCAT_WS('\n',
           COALESCE(NULLIF(TRIM(SPLIT_PART(section_path, ' > ', -1)), ''), ''),
           chunk_text) AS search_text
    FROM CORE.CHUNKS
   WHERE config_name = 'markdown_header_table_1200_200';
