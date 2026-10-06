-- CAPTURE_CHANGES 将 stream 中一次消费区间的文件净变化保存到 FILE_CHANGES，初始状态为 PENDING。
-- INSERT SELECT 提交后消费 stream；持久化记录让后续判断、解析和删块不依赖 stream 重读。
-- batch_id 标识捕获批次，(relative_path, etag) 标识文件版本；本步骤不判断如何处理文件。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

-- 每条文件变更一行。覆盖一个已经捕获过的文件,stream 里是一删一增,这里就是两行;
-- 两次捕获之间新增后又覆盖,stream 里只剩一行新增。
CREATE TABLE IF NOT EXISTS INGEST.FILE_CHANGES (
  batch_id      VARCHAR       NOT NULL COMMENT 'One per RUN_INGEST run; for tracing which run captured the row',
  relative_path VARCHAR       NOT NULL COMMENT 'Path inside CORPUS_STAGE, e.g. PMC123.pdf',
  etag          VARCHAR       NOT NULL COMMENT 'File version; for DELETE rows, the version that was removed',
  size          NUMBER,
  last_modified TIMESTAMP_LTZ,
  change_action VARCHAR       NOT NULL COMMENT 'METADATA$ACTION from the stream: INSERT or DELETE',
  is_update     BOOLEAN       COMMENT 'METADATA$ISUPDATE from the stream',
  status        VARCHAR       NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING, TO_PARSE, TO_REMOVE, DONE or FAILED',
  error_message VARCHAR       COMMENT 'Error text when FAILED',
  retry_count   NUMBER        NOT NULL DEFAULT 0,
  captured_at   TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP() COMMENT 'When the row was copied from the stream',
  updated_at    TIMESTAMP_LTZ COMMENT 'When status last changed'
)
COMMENT = 'medrag v2: one row per file change captured from CORPUS_STREAM';

CREATE OR REPLACE PROCEDURE INGEST.CAPTURE_CHANGES(p_batch_id VARCHAR)
RETURNS NUMBER
LANGUAGE SQL
COMMENT = 'medrag v2: step 1, copy this batch of file changes from CORPUS_STREAM into FILE_CHANGES as PENDING'
EXECUTE AS OWNER
AS
$$
DECLARE
  v_captured      INTEGER;
BEGIN
  -- 连同动作与版本保存，status 使用默认 PENDING；后续分类只读持久化表。

  INSERT INTO INGEST.FILE_CHANGES (
    batch_id, relative_path, etag, size, last_modified, change_action, is_update
  )
  SELECT :p_batch_id, relative_path, etag, size, last_modified::TIMESTAMP_LTZ,
         METADATA$ACTION, METADATA$ISUPDATE
    FROM INGEST.CORPUS_STREAM;

  SELECT COUNT(*) INTO :v_captured
    FROM INGEST.FILE_CHANGES
   WHERE batch_id = :p_batch_id;
  RETURN v_captured;
END;
$$;
