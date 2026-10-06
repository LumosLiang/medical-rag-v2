-- PARSE_FILE 对一个文件版本调用一次 AI_PARSE_DOCUMENT，并保存原始输出、选项及错误。
-- LAYOUT 返回含标题、表格结构的 Markdown，供章节/表格切分；OCR 只提取文本。
-- page_split=TRUE 保留物理页号，后续可拼接跨页正文并换算引用页码。
-- 解析结果按文件版本复用，改变切分不重复解析；更换解析模式需要独立的解析版本设计。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

-- AI_PARSE_DOCUMENT 的原样输出。每次解析尝试一行,成功的版本最多一行。
-- 切分只读解析表；失败结果也保留，便于判断是解析还是切分失败。
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

CREATE OR REPLACE PROCEDURE INGEST.PARSE_FILE(
  p_relative_path VARCHAR,
  p_etag          VARCHAR,
  p_config_name   VARCHAR
)
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
  -- 同一文件版本已有成功结果时复用，避免改变切分策略时重复解析。
  SELECT COUNT(*) INTO :v_ok_count
    FROM INGEST.PARSED_DOCS
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND error_message IS NULL;
  IF (v_ok_count > 0) THEN
    RETURN 'SKIPPED: already parsed';
  END IF;

  -- 按配置构造解析选项；函数结果先保存到变量，再写表，成功和失败都留记录。
  -- return_error_details=TRUE 返回 value、error、metadata，页数来自 metadata.pageCount。
  -- doc_id 由文件名去掉 .pdf 得到；解析调用只在下面的 SELECT 中执行一次。
  SELECT OBJECT_CONSTRUCT('mode', parse_mode, 'page_split', page_split)
    INTO :v_options
    FROM CORE.PIPELINE_CONFIG
   WHERE config_name = :p_config_name;

  SELECT AI_PARSE_DOCUMENT(
    TO_FILE('@MEDRAG.INGEST.CORPUS_STAGE', :p_relative_path),
    :v_options,
    TRUE
  ) INTO :v_parse_result;

  INSERT INTO INGEST.PARSED_DOCS (
    relative_path, etag, doc_id, parse_options, parse_result, page_count, error_message
  )
  SELECT :p_relative_path, :p_etag, REPLACE(:p_relative_path, '.pdf', ''),
         :v_options, :v_parse_result,
         :v_parse_result:metadata:pageCount::NUMBER,
         :v_parse_result:error::STRING;

  SELECT COUNT(*) INTO :v_ok_count
    FROM INGEST.PARSED_DOCS
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND error_message IS NULL;
  IF (v_ok_count = 0) THEN
    RAISE parse_failed;
  END IF;

  RETURN 'PARSED';
END;
$$;
