--!jinja
-- 语料的外部 stage(容器里的 pdf/)、directory table 自动刷新,以及 stage 上的 stream。可以重复执行。
-- 由 deploy.sql 调用。stream 建好后 14 天没人消费会过期(docs/pitfalls.md),task(90_ingest_task.sql)要在那之前建好。
-- stage_base_url 取自 infra/azure 的 terraform output,以 / 结尾,执行时传入,不写进仓库:
--   EXECUTE IMMEDIATE FROM './ingest/20_corpus_stage_and_stream.sql' USING (stage_base_url => '<stage_base_url>');
--
-- 顺序不能乱(见 docs/pitfalls.md):
--   1. 建 stage 时不刷新:REFRESH_ON_CREATE 默认是 TRUE,会在 stream 建好之前就把已有文件登记进去。
--   2. 马上建 stream:它只记录建好之后的变化,之前登记的文件不会出现在 stream 里。
--   3. 手动 REFRESH:已有文件这时才登记,作为新增出现在 stream 里(环节 1 的实验见 docs/decisions.md 先验证第 2 项)。
-- 之后的变化靠 Azure 事件自动刷新。每次部署都会 REFRESH 一次,只补上自动刷新漏掉的变化
-- (比如重命名、删目录,见 docs/pitfalls.md)。

USE ROLE MEDRAG_ADMIN;
USE SCHEMA MEDRAG.INGEST;

CREATE STAGE IF NOT EXISTS CORPUS_STAGE
  URL = '{{ stage_base_url }}pdf/'
  STORAGE_INTEGRATION = MEDRAG_AZURE_STORAGE_INT
  DIRECTORY = (
    ENABLE = TRUE
    REFRESH_ON_CREATE = FALSE
    AUTO_REFRESH = TRUE
    NOTIFICATION_INTEGRATION = 'MEDRAG_AZURE_QUEUE_INT'
  )
  COMMENT = 'medrag v2: corpus PDFs (pdf/ in the corpus container); directory table auto-refreshed by Event Grid';

CREATE STREAM IF NOT EXISTS CORPUS_STREAM
  ON STAGE CORPUS_STAGE
  COMMENT = 'medrag v2: added, overwritten and deleted corpus PDFs; consumed only by the ingest task';

ALTER STAGE CORPUS_STAGE REFRESH;
