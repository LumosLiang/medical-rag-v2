-- CLASSIFY_CHANGES 只负责把 PENDING 分配给下游：DELETE → TO_REMOVE，其余 → TO_PARSE。
-- 覆盖对应旧版本删除和新版本新增，因此后续先删旧块，再解析新版本。

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
  -- 只处理 PENDING，FAILED 不由分类步骤自动重试。
  -- IFF(condition, true_value, false_value) 在两种动作之间选择目标状态。

  UPDATE INGEST.FILE_CHANGES
     SET status = IFF(change_action = 'DELETE', 'TO_REMOVE', 'TO_PARSE'),
         updated_at = CURRENT_TIMESTAMP()
   WHERE status = 'PENDING';

  -- 检查本步的后置条件：处理结束不能仍有 PENDING。
  SELECT COUNT(*) INTO :v_pending_left
    FROM INGEST.FILE_CHANGES
   WHERE status = 'PENDING';
  IF (v_pending_left > 0) THEN
    RAISE pending_left;
  END IF;

  RETURN 'classified';
END;
$$;
