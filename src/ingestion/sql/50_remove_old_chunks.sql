-- REMOVE_OLD_CHUNKS 删除 TO_REMOVE 文件版本的所有配置块，并把对应变更标为 DONE。
-- 按路径和 etag 精确匹配，不删除同一文件其他版本。新版本由解析与切分步骤另行写入。
-- 先删后写简化版本切换，但新版本解析失败时文档会暂时不可检索。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

-- 删除 CORE.CHUNKS 里所有 TO_REMOVE 的文件版本的块,然后把 INGEST.FILE_CHANGES 里对应行标记为 DONE。
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
  -- 只删除明确标为 TO_REMOVE 的版本。

  -- SQLROWCOUNT 是这条 DELETE 删除的块数，作为过程返回值。
  DELETE FROM CORE.CHUNKS c
   USING (SELECT DISTINCT relative_path, etag
            FROM INGEST.FILE_CHANGES
           WHERE status = 'TO_REMOVE') r
   WHERE c.relative_path = r.relative_path
     AND c.etag = r.etag;
  v_removed := SQLROWCOUNT;

  -- DELETE 报错会直接退出，不会执行这个 UPDATE；删除成功才确认变更已处理。
  UPDATE INGEST.FILE_CHANGES
     SET status = 'DONE', updated_at = CURRENT_TIMESTAMP()
   WHERE status = 'TO_REMOVE';

  -- 后置条件检查，不是重试：所有待删除变更都应已变为 DONE。
  SELECT COUNT(*) INTO :v_left
    FROM INGEST.FILE_CHANGES
   WHERE status = 'TO_REMOVE';
  IF (v_left > 0) THEN
    RAISE remove_left;
  END IF;

  RETURN v_removed;
END;
$$;
