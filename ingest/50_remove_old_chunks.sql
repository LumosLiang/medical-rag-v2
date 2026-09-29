-- 删旧块:把判断为 TO_REMOVE 的文件版本在 CORE.CHUNKS 里的块删掉。入库流程的第 3 步。
-- 由 deploy.sql 调用,可以重复执行(过程用 CREATE OR REPLACE 更新;改签名要先 DROP,见 docs/pitfalls.md)。
--
-- 在流程里的位置:RUN_INGEST(80_run_ingest.sql)在判断变更(40_classify_file_changes.sql)之后、解析新版本之前调它。先删旧块,
-- 块表里就只留当前版本;代价是新版本解析失败时,这篇暂时搜不到(FILE_CHANGES 里是 FAILED)。
-- 状态约定见 30_capture_file_changes.sql 的文件头。
-- 用法:CALL MEDRAG.INGEST.REMOVE_OLD_CHUNKS();返回删掉的块数。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE OR REPLACE PROCEDURE INGEST.REMOVE_OLD_CHUNKS()
RETURNS NUMBER
LANGUAGE SQL
COMMENT = 'medrag v2: step 3, delete the chunks of every file version marked TO_REMOVE, then mark those rows DONE'
EXECUTE AS OWNER
AS
$$
DECLARE
  v_removed       INTEGER DEFAULT 0;
  v_left          INTEGER;
  remove_left     EXCEPTION (-20151, 'REMOVE_OLD_CHUNKS: some rows are still TO_REMOVE; every TO_REMOVE row must end as DONE');
BEGIN
  -- 按 (relative_path, etag) 删块:块表只做增量 DML,不重建、不整表删(.harness/rules/pipeline-rules.md)。

  -- 对应删chuck里面的，按照relative_path和etag去删除，删除的数量返回
  DELETE FROM CORE.CHUNKS c
   USING (SELECT DISTINCT relative_path, etag
            FROM INGEST.FILE_CHANGES
           WHERE status = 'TO_REMOVE') r
   WHERE c.relative_path = r.relative_path
     AND c.etag = r.etag;
  v_removed := SQLROWCOUNT;

  -- 删完以后设置Done。但这里有个问题，如果上面失败了怎么办？
  UPDATE INGEST.FILE_CHANGES
     SET status = 'DONE', updated_at = CURRENT_TIMESTAMP()
   WHERE status = 'TO_REMOVE';


  -- 算一把剩下的TO_REMOVE的行数，不知道这个是不是留着做重试。
  SELECT COUNT(*) INTO :v_left
    FROM INGEST.FILE_CHANGES
   WHERE status = 'TO_REMOVE';
  IF (v_left > 0) THEN
    RAISE remove_left;
  END IF;

  RETURN v_removed;
END;
$$;
