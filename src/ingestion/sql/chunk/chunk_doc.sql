-- CHUNK_DOC 是所有切分算法的统一入口：读配置、验证输入、分派算法、替换结果与验收。
-- chunk_method 对应 CORE.CHUNK_<METHOD> 的统一十参数接口，新增算法无需给入口添加分支。
-- 同文件版本、同配置先删后写在一个事务内；失败回滚，其他版本和配置的块保持不变。

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
  chunk_text     VARCHAR       NOT NULL COMMENT 'Stored retrieval text; search-service heading prefixes are computed separately',
  chunk_text_raw VARCHAR       NOT NULL COMMENT 'Legacy duplicate of chunk_text; retained for existing table compatibility',
  token_count    NUMBER        NOT NULL COMMENT 'Tokens in chunk_text, measured with COUNT_TOKENS',
  page_start     NUMBER        COMMENT 'Starting at 0; NULL when pages cannot be matched',
  page_end       NUMBER,
  created_at     TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_chunks PRIMARY KEY (chunk_id)
)
CHANGE_TRACKING = TRUE
COMMENT = 'medrag v2: indexed chunks; incremental DML only';

-- Cortex Search 通过 change tracking 读取源表的增量变化。
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
  v_bad_count    INTEGER;
  v_format       VARCHAR;
  v_chunk_size   INTEGER;
  v_overlap      INTEGER;
  v_resplit_size INTEGER;
  v_max_tokens   INTEGER;
  v_token_model  VARCHAR;
  v_method       VARCHAR;
  v_call_sql     VARCHAR;
  missing_config EXCEPTION (-20111, 'CHUNK_DOC: config not found in CORE.PIPELINE_CONFIG');
  missing_parse  EXCEPTION (-20112, 'CHUNK_DOC: this file version has no successful row in INGEST.PARSED_DOCS');
  wrong_method   EXCEPTION (-20113, 'CHUNK_DOC: invalid chunk_method identifier');
  invalid_chunks EXCEPTION (-20114, 'CHUNK_DOC: no chunks or token_count is NULL');
BEGIN
  -- 先取这次切分的配置；后面的 SQL 都用同一组参数。
  SELECT COUNT(*) INTO :v_config_count
    FROM CORE.PIPELINE_CONFIG
   WHERE config_name = :p_config_name;
  IF (v_config_count = 0) THEN
    RAISE missing_config;
  END IF;

  -- 读配置参数:split_format、chunk_size_chars、chunk_overlap_chars、resplit_chunk_size_chars、max_tokens、token_model、chunk_method。
  SELECT split_format, chunk_size_chars, chunk_overlap_chars,
         resplit_chunk_size_chars, max_tokens, token_model, chunk_method
    INTO :v_format, :v_chunk_size, :v_overlap,
         :v_resplit_size, :v_max_tokens, :v_token_model, :v_method
    FROM CORE.PIPELINE_CONFIG
   WHERE config_name = :p_config_name;

  IF (v_method IS NULL OR NOT REGEXP_LIKE(v_method, '^[a-z][a-z0-9_]*$')) THEN
    RAISE wrong_method;
  END IF;
  v_call_sql := 'CALL CORE.CHUNK_' || UPPER(v_method) || '(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

  -- 只处理已经解析成功的这个文件版本，不重新调用 AI_PARSE_DOCUMENT。
  SELECT COUNT(*) INTO :v_parsed_count
    FROM INGEST.PARSED_DOCS
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND error_message IS NULL;
  IF (v_parsed_count = 0) THEN
    RAISE missing_parse;
  END IF;

  -- 同版本、同配置重跑时先删后写；失败则一起回滚。
  BEGIN TRANSACTION;
  DELETE FROM IDENTIFIER(:p_target_table)
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND config_name = :p_config_name;

  EXECUTE IMMEDIATE :v_call_sql USING (
    p_relative_path, p_etag, p_config_name, p_target_table,
    v_format, v_chunk_size, v_overlap, v_token_model,
    v_resplit_size, v_max_tokens
  );

  SELECT COUNT(*), COUNT_IF(token_count IS NULL)
    INTO :v_chunk_count, :v_bad_count
    FROM IDENTIFIER(:p_target_table)
   WHERE relative_path = :p_relative_path
     AND etag = :p_etag
     AND config_name = :p_config_name;
  IF (v_chunk_count = 0 OR v_bad_count > 0) THEN
    RAISE invalid_chunks;
  END IF;

  COMMIT;
  RETURN v_chunk_count;
EXCEPTION
  WHEN OTHER THEN
    ROLLBACK;
    RAISE;
END;
$$;
