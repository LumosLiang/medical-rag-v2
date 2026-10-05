-- 入库流程的入口:task(90_ingest_task.sql)在 stream 有数据时调用它,它按顺序调用下面四步。本文件没有留空。
-- 由 deploy.sql 调用,可以重复执行(过程用 CREATE OR REPLACE 更新;改签名要先 DROP,见 docs/pitfalls.md)。
--
--   1. 捕获变更   CAPTURE_CHANGES(30_capture_file_changes.sql)    stream 里这一批 → FILE_CHANGES,PENDING
--   2. 判断变更   CLASSIFY_CHANGES(40_classify_file_changes.sql)  PENDING → TO_PARSE、TO_REMOVE 或其它
--   3. 删旧块     REMOVE_OLD_CHUNKS(50_remove_old_chunks.sql)   TO_REMOVE 的版本从 CHUNKS 删掉 → DONE
--   4. 解析、切分 PARSE_FILE(60_parse_documents.sql)、CHUNK_DOC(chunk/chunk_doc.sql),逐条处理 TO_PARSE → DONE 或 FAILED
--
-- 各步各自提交,不包成一个事务(docs/decisions.md)。每一步处理所有处在它输入状态的行,不只这一批:
-- 某一步失败,留下的行等下一次运行接着处理(stream 再有数据时,或者手动 CALL RUN_INGEST())。
-- 状态约定见 30_capture_file_changes.sql 的文件头。
-- 用法:CALL MEDRAG.INGEST.RUN_INGEST();返回这一次的摘要。

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
  v_captured    INTEGER DEFAULT 0;
  v_removed     INTEGER DEFAULT 0;
  v_done        INTEGER DEFAULT 0;
  v_failed      INTEGER DEFAULT 0;
  v_row_batch   VARCHAR;
  v_path        VARCHAR;
  v_etag        VARCHAR;
  v_error       VARCHAR;
  no_active_config EXCEPTION (-20121, 'RUN_INGEST: no config with is_active = TRUE in CORE.PIPELINE_CONFIG');
  -- 游标在 FOR 开始时才执行,所以能看到第 2 步刚设的 TO_PARSE。
  c_to_parse CURSOR FOR
    SELECT batch_id, relative_path, etag
      FROM INGEST.FILE_CHANGES
     WHERE status = 'TO_PARSE'
     ORDER BY captured_at, relative_path;
BEGIN
  SELECT MAX(config_name) INTO :v_config_name
    FROM CORE.PIPELINE_CONFIG
   WHERE is_active;
  IF (v_config_name IS NULL) THEN
    RAISE no_active_config;
  END IF;

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

  -- 环节 8 之后在这里调用数据检查。

  RETURN 'batch ' || v_batch_id || ': captured ' || v_captured::VARCHAR
      || ', chunks removed ' || v_removed::VARCHAR
      || ', done ' || v_done::VARCHAR || ', failed ' || v_failed::VARCHAR;
END;
$$;
