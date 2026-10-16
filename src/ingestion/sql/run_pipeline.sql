-- RUN_INGEST 协调文件变化的处理：捕获 → 分类 → 删除旧块 → 逐文件解析与切分。
-- 日常策略必须且只能有一条 active 配置；实验策略不由此入口自动回填。
-- 单文件失败记为 FAILED 并继续处理其他文件；不同步骤分开提交，不形成整批事务。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE PROCEDURE INGEST.RUN_INGEST()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'medrag v2: ingest entry called by the task; capture, classify, remove old chunks, then parse and chunk TO_PARSE files'
EXECUTE AS OWNER
AS
$$
DECLARE
  v_batch_id    VARCHAR DEFAULT UUID_STRING();
  v_config_name VARCHAR;
  v_active_count INTEGER;
  v_captured    INTEGER DEFAULT 0;
  v_removed     INTEGER DEFAULT 0;
  v_done        INTEGER DEFAULT 0;
  v_failed      INTEGER DEFAULT 0;
  v_row_batch   VARCHAR;
  v_path        VARCHAR;
  v_etag        VARCHAR;
  v_error       VARCHAR;
  invalid_active_config EXCEPTION (-20121, 'RUN_INGEST: exactly one config must have is_active = TRUE');
  -- 游标在 FOR 开始时才执行,所以能看到第 2 步刚设的 TO_PARSE。
  c_to_parse CURSOR FOR
    SELECT batch_id, relative_path, etag
      FROM INGEST.FILE_CHANGES
     WHERE status = 'TO_PARSE'
     ORDER BY captured_at, relative_path;
BEGIN

  -- active 是明确的运行选择，不按名字或创建时间猜测。消费 stream 前先验证唯一性。
  SELECT COUNT(*) INTO :v_active_count
    FROM CORE.PIPELINE_CONFIG
    WHERE is_active;
  IF (v_active_count <> 1) THEN
    RAISE invalid_active_config;
  END IF;
  SELECT config_name INTO :v_config_name
    FROM CORE.PIPELINE_CONFIG
   WHERE is_active;

  -- 1. 捕获变更
  CALL INGEST.CAPTURE_CHANGES(:v_batch_id) INTO :v_captured;

  -- 2. 判断变更
  CALL INGEST.CLASSIFY_CHANGES();

  -- 3. 删旧块
  CALL INGEST.REMOVE_OLD_CHUNKS() INTO :v_removed;

  -- 4. 解析、切分。一个文件失败不影响其它文件:记下错误,接着处理下一个。
  FOR r IN c_to_parse DO
    v_row_batch := r.batch_id;
    v_path      := r.relative_path;
    v_etag      := r.etag;
    BEGIN
      CALL INGEST.PARSE_FILE(:v_path, :v_etag, :v_config_name);
      CALL CORE.CHUNK_DOC(:v_path, :v_etag, :v_config_name, 'MEDRAG.CORE.CHUNKS');
      UPDATE INGEST.FILE_CHANGES
         SET status = 'DONE', error_message = NULL, updated_at = CURRENT_TIMESTAMP()
       WHERE batch_id = :v_row_batch
         AND relative_path = :v_path
         AND etag = :v_etag
         AND status = 'TO_PARSE';
      v_done := v_done + 1;
    EXCEPTION
      WHEN OTHER THEN
        v_error := SQLERRM;
        UPDATE INGEST.FILE_CHANGES
           SET status = 'FAILED', error_message = :v_error, retry_count = retry_count + 1,
               updated_at = CURRENT_TIMESTAMP()
         WHERE batch_id = :v_row_batch
           AND relative_path = :v_path
           AND etag = :v_etag
           AND status = 'TO_PARSE';
        v_failed := v_failed + 1;
    END;
  END FOR;

  RETURN 'batch ' || v_batch_id || ': captured ' || v_captured::VARCHAR
      || ', chunks removed ' || v_removed::VARCHAR
      || ', done ' || v_done::VARCHAR || ', failed ' || v_failed::VARCHAR;
END;
$$;
