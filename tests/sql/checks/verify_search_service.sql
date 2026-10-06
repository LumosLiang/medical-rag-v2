-- 搜索服务验收,只读:服务状态、索引行数与源表一致,再手工问一个问题看返回。
-- 改 service_name / config_name 即可检查任一服务。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_INDEX_WH;

SET config_name = 'markdown_header_table_1200_200';

-- 1. 源块:行数、文档数、没有章节的块、源数据指纹(对照实验之间应相同)。
SELECT COUNT(*) AS chunks,
       COUNT(DISTINCT doc_id) AS documents,
       COUNT_IF(NULLIF(TRIM(section_path), '') IS NULL) AS no_heading,
       HASH_AGG(chunk_id, chunk_text, section_path, etag, page_start, page_end) AS source_hash
  FROM CORE.CHUNKS
 WHERE config_name = $config_name;

-- 2. 服务状态:indexing_state / serving_state 为 ACTIVE,source_data_num_rows 等于上面的 chunks。
SHOW CORTEX SEARCH SERVICES IN SCHEMA CORE;

-- 3. 冒烟查询:服务名和问题按需改;SEARCH_PREVIEW 只接受常量。
SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
         'MEDRAG.CORE.MEDICAL_CHUNKS_MARKDOWN_MULTI_INDEX_1200_200',
         '{"query": "clinical outcomes",
           "columns": ["chunk_id", "relative_path", "page_start", "chunk_text"],
           "limit": 5}'
       )):results AS results;

-- 4. 仅对标题前缀服务(30_heading_prefix.sql):加前缀后超过 512 token 的块数。
--    embedding 会截断超窗部分,这个数应很小并记进实验 params。
SELECT COUNT_IF(SNOWFLAKE.CORTEX.COUNT_TOKENS(
         'snowflake-arctic-embed-l-v2.0',
         CONCAT_WS('\n',
           COALESCE(NULLIF(TRIM(SPLIT_PART(section_path, ' > ', -1)), ''), ''),
           chunk_text)
       ) > 512) AS prefix_over_limit
  FROM CORE.CHUNKS
 WHERE config_name = $config_name;
