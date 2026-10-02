-- 解析:用 AI_PARSE_DOCUMENT 解析一个文件版本,结果存进 INGEST.PARSED_DOCS。
-- 由 deploy.sql 调用,可以重复执行:表已经存在就不动;过程用 CREATE OR REPLACE 更新(改签名要先 DROP,见 docs/pitfalls.md)。
--
-- 在流程里的位置:RUN_INGEST(80_run_ingest.sql)对每条 TO_PARSE 的变更,先调 PARSE_FILE,再调 CHUNK_DOC(chunk/chunk_doc.sql)。
-- 用法:CALL MEDRAG.INGEST.PARSE_FILE('<relative_path>', '<etag>', '<config_name>');
--
-- 以后加列:在 CREATE TABLE 后面写 ALTER TABLE ... ADD COLUMN IF NOT EXISTS;只改 CREATE TABLE 本身不会影响已经部署的表。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

-- AI_PARSE_DOCUMENT 的原样输出。每次解析尝试一行,成功的版本最多一行。
-- 改切分只读这张表,不重新解析:解析按页计费,是整条流程里最贵的一步。
CREATE TABLE IF NOT EXISTS INGEST.PARSED_DOCS (
  relative_path VARCHAR       NOT NULL,
  etag          VARCHAR       NOT NULL,
  doc_id        VARCHAR       NOT NULL COMMENT 'File name without .pdf, i.e. the PMCID; labels refer to it',
  parse_options OBJECT        COMMENT 'Options passed to AI_PARSE_DOCUMENT',
  parse_result  VARIANT       COMMENT 'AI_PARSE_DOCUMENT output as returned',
  page_count    NUMBER,
  error_message VARCHAR       COMMENT 'NULL means the parse succeeded',
  parsed_at     TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'medrag v2: raw AI_PARSE_DOCUMENT output per parse attempt; the only input when re-chunking';

CREATE OR REPLACE PROCEDURE INGEST.PARSE_FILE(p_relative_path VARCHAR, p_etag VARCHAR, p_config_name VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'medrag v2: parse one file version with AI_PARSE_DOCUMENT into PARSED_DOCS; skips versions already parsed'
EXECUTE AS OWNER
AS
$$
DECLARE
  v_ok_count      INTEGER;
  v_parse_result  VARIANT;
  v_options       OBJECT;
  parse_failed    EXCEPTION (-20141, 'PARSE_FILE: no successful parse for this file version; see INGEST.PARSED_DOCS.error_message');
BEGIN
  -- 同一版本之前已经解析成功,就不再解析:解析按页计费(docs/pitfalls.md)。
  SELECT COUNT(*) INTO :v_ok_count
    FROM INGEST.PARSED_DOCS
   WHERE relative_path = :p_relative_path AND etag = :p_etag AND error_message IS NULL;
  IF (v_ok_count > 0) THEN
    RETURN 'SKIPPED: already parsed';
  END IF;

  -- ===== 你来写:环节 3A 解析 =====
  -- 用 AI_PARSE_DOCUMENT 解析 @MEDRAG.INGEST.CORPUS_STAGE 上的 :p_relative_path,写进 INGEST.PARSED_DOCS 一行(成功失败都写)。
  -- 选项用 CORE.PIPELINE_CONFIG 里 :p_config_name 那一行的 parse_mode、page_split。第三个参数 return_error_details 传 TRUE:
  -- 返回的 OBJECT 里 value 是解析结果、error 是错误原文、metadata 里有 pageCount(官方 AI_PARSE_DOCUMENT 页)。
  -- doc_id 是文件名去掉 .pdf。不要放进 CTE,会重复调用、重复计费(docs/pitfalls.md)。
  SELECT OBJECT_CONSTRUCT('mode', parse_mode, 'page_split', page_split)
    INTO :v_options
    FROM CORE.PIPELINE_CONFIG
   WHERE config_name = :p_config_name;

  SELECT AI_PARSE_DOCUMENT(
    TO_FILE('@MEDRAG.INGEST.CORPUS_STAGE', :p_relative_path),
    :v_options,
    TRUE
  ) INTO :v_parse_result;

  INSERT INTO INGEST.PARSED_DOCS(relative_path, etag, doc_id, parse_options, parse_result, page_count, error_message)
  SELECT :p_relative_path, :p_etag, REPLACE(:p_relative_path, '.pdf', ''),
         :v_options, :v_parse_result,
         :v_parse_result:metadata:pageCount::NUMBER,
         :v_parse_result:error::STRING;

  -- ===== 到这里 =====

  -- 你的代码跑完,还没有成功的行,就抛异常,让 RUN_INGEST 把这条变更标成 FAILED。
  SELECT COUNT(*) INTO :v_ok_count
    FROM INGEST.PARSED_DOCS
   WHERE relative_path = :p_relative_path AND etag = :p_etag AND error_message IS NULL;
  IF (v_ok_count = 0) THEN
    RAISE parse_failed;
  END IF;

  RETURN 'PARSED';
END;
$$;

-- select * from CORE.PIPELINE_CONFIG;

-- ETAG 必须保留 DIRECTORY 返回值里的双引号，手动去掉会被当成另一个版本。
-- call INGEST.PARSE_FILE('PMC10275696.pdf', '"0x8DF1DFD5260DBC0"', 'base_1200');
-- select * from INGEST.PARSED_DOCS where relative_path = 'PMC10275696.pdf' and etag = '"0x8DF1DFD5260DBC0"';
