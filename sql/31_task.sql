-- 入库 task:stream 有数据时调用 INGEST.RUN_INGEST()。
--
-- 这个文件还没加进 deploy.sql。等环节 2–5 的空都写完,再和 04_stage.sql 一起加:
-- 先加 04_stage 的话,stream 没人消费,14 天后可能过期(docs/pitfalls.md)。
-- 建好的 task 是暂停的。ALTER TASK ... RESUME 之后才会跑,跑就会解析、花钱,RESUME 之前先说一声。

USE ROLE MEDRAG_ADMIN;
USE SCHEMA MEDRAG.INGEST;

-- ===== 你来写:环节 6A task 定义 =====
-- 要做什么:用 CREATE OR ALTER TASK 定义 INGEST.INGEST_TASK,调用 INGEST.RUN_INGEST()。
-- 要定的:WHEN 条件;用哪个 warehouse(解析和切分在同一个 task 里;MEDICAL_RAG_PARSE_WH 是 MEDIUM,
--         MEDICAL_RAG_INDEX_WH 是 X-SMALL);要不要设 USER_TASK_TIMEOUT_MS、SUSPEND_TASK_AFTER_NUM_FAILURES。
-- 注意(docs/pitfalls.md):WHEN 只能用 SYSTEM$STREAM_HAS_DATA 这类函数,不能查表;
--       不设 SCHEDULE 能不能由 stage 上的 stream 触发,是先验证第 2 项。
-- 看:官方 CREATE TASK、Triggered tasks 两页。
-- 验收:docs/hands-on.md 环节 6。
-- 这个文件在你写之前不进部署入口,所以这里没有占位语句。
-- ===== 到这里 =====
