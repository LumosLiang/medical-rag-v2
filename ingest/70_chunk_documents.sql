-- 切分:把一个解析好的文件版本切成块,写进块表。块表 CORE.CHUNKS 是检索服务的源表。
-- 入库和评测实验共用这一份切分逻辑:入库时写 CORE.CHUNKS,评测实验传自己的表。
-- 由 deploy.sql 调用,可以重复执行:表已经存在就不动;过程用 CREATE OR REPLACE 更新(改签名要先 DROP,见 docs/pitfalls.md)。
--
-- 在流程里的位置:RUN_INGEST(80_run_ingest.sql)解析完一个版本(60_parse_documents.sql)就调 CHUNK_DOC。
-- 用法:CALL MEDRAG.CORE.CHUNK_DOC('<relative_path>', '<etag>', '<config_name>', 'MEDRAG.CORE.CHUNKS');
-- 返回写入的块数。任何一步出错都抛异常,这个版本的块回到调用前的样子。
--
-- 以后加列:在 CREATE TABLE 后面写 ALTER TABLE ... ADD COLUMN IF NOT EXISTS;只改 CREATE TABLE 本身不会影响已经部署的表。
-- CHUNKS 的列要在环节 7 建检索服务之前定下来:服务建好后再改 source query 的列,会触发全量重新 embedding(docs/pitfalls.md)。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

-- 检索服务的源表。只做增量 DML(INSERT、DELETE、MERGE),不重建、不整表删了重插。
CREATE TABLE IF NOT EXISTS CORE.CHUNKS (
  chunk_id       VARCHAR       NOT NULL COMMENT 'Unique, built from deterministic inputs, stable across reruns; search service primary key',
  doc_id         VARCHAR       NOT NULL,
  relative_path  VARCHAR       NOT NULL,
  etag           VARCHAR       NOT NULL COMMENT 'File version the chunk came from; must be the current version',
  config_name    VARCHAR       NOT NULL COMMENT 'PIPELINE_CONFIG used to chunk it',
  chunk_index    NUMBER        NOT NULL COMMENT 'Order within the document, starting at 0',
  section_path   VARCHAR       COMMENT 'Header path, e.g. Results > Survival',
  chunk_text     VARCHAR       NOT NULL COMMENT 'Indexed text, with prefix',
  chunk_text_raw VARCHAR       NOT NULL COMMENT 'Original text, for display and evidence matching',
  token_count    NUMBER        NOT NULL COMMENT 'Tokens in chunk_text, measured with COUNT_TOKENS',
  page_start     NUMBER        COMMENT 'Starting at 0; NULL when pages cannot be matched',
  page_end       NUMBER,
  created_at     TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_chunks PRIMARY KEY (chunk_id)
)
CHANGE_TRACKING = TRUE
COMMENT = 'medrag v2: indexed chunks; incremental DML only';

-- 表已存在时 CREATE 不会生效,这里再确认一次 change tracking 是开的(Cortex Search 需要)。
ALTER TABLE CORE.CHUNKS SET CHANGE_TRACKING = TRUE;

CREATE OR REPLACE PROCEDURE CORE.CHUNK_DOC(
  p_relative_path VARCHAR,
  p_etag          VARCHAR,
  p_config_name   VARCHAR,
  p_target_table  VARCHAR
)
RETURNS NUMBER
LANGUAGE SQL
COMMENT = 'medrag v2: chunk one parsed file version with one config into the target table'
EXECUTE AS OWNER
AS
$$
DECLARE
  v_config_count INTEGER;
  v_parsed_count INTEGER;
  v_chunk_count  INTEGER;
  missing_config  EXCEPTION (-20111, 'CHUNK_DOC: config not found in CORE.PIPELINE_CONFIG');
  missing_parse   EXCEPTION (-20112, 'CHUNK_DOC: this file version has no successful row in INGEST.PARSED_DOCS');
  not_implemented EXCEPTION (-20119, 'NOT_IMPLEMENTED: 环节 5A 切分(ingest/70_chunk_documents.sql CHUNK_DOC)');
BEGIN
  SELECT COUNT(*) INTO :v_config_count
    FROM CORE.PIPELINE_CONFIG
   WHERE config_name = :p_config_name;
  IF (v_config_count = 0) THEN
    RAISE missing_config;
  END IF;

  SELECT COUNT(*) INTO :v_parsed_count
    FROM INGEST.PARSED_DOCS
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND error_message IS NULL;
  IF (v_parsed_count = 0) THEN
    RAISE missing_parse;
  END IF;

  -- 删旧块和写新块在一个事务里:中途出错就回滚,检索服务不会看到这个版本只剩一半块。
  BEGIN TRANSACTION;

  -- 同一版本、同一配置重跑时,先删掉上次的块,保证可以重复执行。
  -- 这里只删同一版本的块;被删除、被覆盖的旧版本由 REMOVE_OLD_CHUNKS(50_remove_old_chunks.sql)删。
  DELETE FROM IDENTIFIER(:p_target_table)
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND config_name = :p_config_name;

  -- ===== 你来写:环节 5A 切分 =====
  -- 把这个版本的解析结果(INGEST.PARSED_DOCS 里成功的那一行)切成块,写进 IDENTIFIER(:p_target_table),列同上面的 CORE.CHUNKS。
  -- recursive 基线,参数都取 CORE.PIPELINE_CONFIG 里 :p_config_name 那一行:
  --   1. SPLIT_TEXT_RECURSIVE_CHARACTER 按 split_format、chunk_size_chars、chunk_overlap_chars 直接切;
  --      省略 separators 参数,使用 Snowflake 默认分隔符;不使用 split_headers。
  --   2. SNOWFLAKE.CORTEX.COUNT_TOKENS(token_model, 块) 数 token;
  --   3. 超过 max_tokens 的块继续 recursive 切,再数一次;resplit_chunk_size_chars 是起始再切大小。
  -- 这个配置里前缀和去参考文献都关着:chunk_text 和 chunk_text_raw 先填一样的;section_path、页码可以先留空。
  -- chunk_id 要唯一、重跑不变;每块不超过 max_tokens。要自己定的:各页先拼起来再切,还是按页切。
  -- 写完删掉下面这一行。
  RAISE not_implemented;
  -- ===== 到这里 =====

  COMMIT;

  SELECT COUNT(*) INTO :v_chunk_count
    FROM IDENTIFIER(:p_target_table)
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND config_name = :p_config_name;
  RETURN v_chunk_count;
EXCEPTION
  WHEN OTHER THEN
    ROLLBACK;
    RAISE;
END;
$$;
