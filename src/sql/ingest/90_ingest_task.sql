-- 入库 task:stream 有数据时调用 INGEST.RUN_INGEST()(80_run_ingest.sql)。
-- 已在 deploy.sql 的 80_run_ingest.sql 后面调用。建好的 task 是暂停的,RESUME 之后才会跑。

USE ROLE MEDRAG_ADMIN;
USE SCHEMA MEDRAG.INGEST;

-- ===== 你来写:环节 6A task 定义 =====
-- 用 CREATE OR ALTER TASK 定义 INGEST.INGEST_TASK,调用 INGEST.RUN_INGEST()。
-- 要定的:不设 SCHEDULE,只靠 stream 有数据时触发,WHEN 写什么(WHEN 只能用 SYSTEM$STREAM_HAS_DATA 这类函数,不能查表);
-- 用哪个 warehouse(MEDICAL_RAG_INDEX_WH 是 X-SMALL,MEDICAL_RAG_PARSE_WH 是 MEDIUM)。
-- 看:官方 CREATE TASK、Triggered tasks 两页。
-- 已填好定义并加入部署入口。

CREATE OR ALTER TASK INGEST.INGEST_TASK
  WAREHOUSE = MEDICAL_RAG_PARSE_WH
  WHEN SYSTEM$STREAM_HAS_DATA('INGEST.CORPUS_STREAM')
AS
  CALL INGEST.RUN_INGEST();


-- 手工查看 task：选中下面的语句单独执行，不随部署运行。
-- show tasks like '%INGEST%';
-- desc task MEDRAG.INGEST.INGEST_TASK;