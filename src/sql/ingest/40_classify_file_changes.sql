-- 判断变更:给每条还没判断的变更定下一步怎么处理。入库流程的第 2 步。
-- 由 deploy.sql 调用,可以重复执行(过程用 CREATE OR REPLACE 更新;改签名要先 DROP,见 docs/pitfalls.md)。
--
-- 在流程里的位置:RUN_INGEST(80_run_ingest.sql)在捕获变更(30_capture_file_changes.sql)之后调它。它设的 TO_REMOVE 由删旧块(50_remove_old_chunks.sql)处理,
-- TO_PARSE 由 RUN_INGEST 交给解析(60_parse_documents.sql)和切分(chunk/chunk_doc.sql)。状态约定见 30_capture_file_changes.sql 的文件头。
-- 用法:CALL MEDRAG.INGEST.CLASSIFY_CHANGES();不连 stream,可以往 FILE_CHANGES 插假数据来测。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE PROCEDURE INGEST.CLASSIFY_CHANGES()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'medrag v2: step 2, decide for every PENDING file change whether to parse it, remove its chunks, or skip it'
EXECUTE AS OWNER
AS
$$
DECLARE
  v_pending_left  INTEGER;
  pending_left    EXCEPTION (-20131, 'CLASSIFY_CHANGES: some rows are still PENDING; every PENDING row must get a new status');
BEGIN
  -- 最简版:只按 stream 的动作分。新增(含覆盖后的新版本)去解析,删除(含被覆盖的旧版本)去删块。
  -- 不重试 FAILED,不处理特殊情况;跑通后可以重写这一步(docs/roadmap.md)。
  -- iff --> if/else
  -- status = "TO_REMOVE" if change_action = 'DELETE' else "TO_PARSE"

  UPDATE INGEST.FILE_CHANGES
     SET status = IFF(change_action = 'DELETE', 'TO_REMOVE', 'TO_PARSE'),
         updated_at = CURRENT_TIMESTAMP()
   WHERE status = 'PENDING';

  -- 算一把剩下的pending的行数
  SELECT COUNT(*) INTO :v_pending_left
    FROM INGEST.FILE_CHANGES
   WHERE status = 'PENDING';
  IF (v_pending_left > 0) THEN
    RAISE pending_left;
  END IF;

  RETURN 'classified';
END;
$$;
