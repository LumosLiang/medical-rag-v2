-- 捕获变更:把 CORPUS_STREAM 里这一批文件变更写进 INGEST.FILE_CHANGES。入库流程的第 1 步。
-- 由 deploy.sql 调用,可以重复执行:表已经存在就不动;过程用 CREATE OR REPLACE 更新(改签名要先 DROP,见 docs/pitfalls.md)。
--
-- 在流程里的位置:RUN_INGEST(80_run_ingest.sql)第一个调它;判断变更(40_classify_file_changes.sql)处理它写进来的 PENDING 行。
-- 用法:CALL MEDRAG.INGEST.CAPTURE_CHANGES('<batch_id>');返回这一批写进来的行数。
-- CORPUS_STREAM 随 20_corpus_stage_and_stream.sql 一起部署。
--
-- FILE_CHANGES.status 的约定,每个状态只由一步处理:
--   PENDING    本步写入;判断变更(40_classify_file_changes)处理。
--   TO_PARSE   判断变更设;RUN_INGEST 逐条解析(60_parse_documents)、切分(70_chunk_documents),完了设 DONE 或 FAILED。
--   TO_REMOVE  判断变更设;删旧块(50_remove_old_chunks)删掉这个版本的块,设 DONE。
--   DONE       处理完。
--   FAILED     出错,error_message 是错误原文,retry_count 加一。要不要重试,由判断变更决定。
--   其它取值(比如 SKIPPED)由判断变更自己定,别的步骤不碰。
-- 各步各自提交,不包成一个事务(docs/decisions.md)。每一步处理所有处在它输入状态的行,不只这一批,
-- 所以某一步失败时留下的行,下一次运行接着处理。
--
-- 以后加列:在 CREATE TABLE 后面写 ALTER TABLE ... ADD COLUMN IF NOT EXISTS;只改 CREATE TABLE 本身不会影响已经部署的表。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

-- 每条文件变更一行。覆盖一个已经捕获过的文件,stream 里是一删一增,这里就是两行;
-- 两次捕获之间新增后又覆盖,stream 里只剩一行新增(docs/decisions.md 先验证第 2 项)。
CREATE TABLE IF NOT EXISTS INGEST.FILE_CHANGES (
  batch_id      VARCHAR       NOT NULL COMMENT 'One per RUN_INGEST run; for tracing which run captured the row',
  relative_path VARCHAR       NOT NULL COMMENT 'Path inside CORPUS_STAGE, e.g. PMC123.pdf',
  etag          VARCHAR       NOT NULL COMMENT 'File version; for DELETE rows, the version that was removed',
  size          NUMBER,
  last_modified TIMESTAMP_LTZ,
  change_action VARCHAR       NOT NULL COMMENT 'METADATA$ACTION from the stream: INSERT or DELETE',
  is_update     BOOLEAN       COMMENT 'METADATA$ISUPDATE from the stream',
  status        VARCHAR       NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING, TO_PARSE, TO_REMOVE, DONE, FAILED, or a value set by CLASSIFY_CHANGES; see ingest/30_capture_file_changes.sql',
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
  not_implemented EXCEPTION (-20129, 'NOT_IMPLEMENTED: 环节 2A 捕获变更(ingest/30_capture_file_changes.sql CAPTURE_CHANGES)');
BEGIN
  -- ===== 你来写:环节 2A 捕获变更 =====
  -- 一条 INSERT ... SELECT:把 INGEST.CORPUS_STREAM 的行写进 INGEST.FILE_CHANGES,batch_id 填 :p_batch_id。
  -- 用到 stream 的文件列和 METADATA$ACTION、METADATA$ISUPDATE;status 不用填,默认 PENDING。
  -- 这条 DML 一提交,stream 就前进(环节 1 在 SPIKE_STREAM 上练过同样的消费)。
  -- 写完删掉下面这一行。
  RAISE not_implemented;
  -- ===== 到这里 =====

  SELECT COUNT(*) INTO :v_captured
    FROM INGEST.FILE_CHANGES
   WHERE batch_id = :p_batch_id;
  RETURN v_captured;
END;
$$;
