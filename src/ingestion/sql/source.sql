--!jinja
-- Azure 文件事件链：PDF 上传/覆盖/删除 → Event Grid → Storage Queue。
-- Snowflake 的通知集成读取队列，刷新 CORPUS_STAGE 的 directory table（文件元数据）。
-- CORPUS_STREAM 记录元数据的净变化，INGEST_TASK 据此调用入库；SQL 不直接读取队列。
-- STORAGE_INTEGRATION 授权读取 PDF；NOTIFICATION_INTEGRATION 授权读取事件，两者职责不同。
-- 首次建立后 REFRESH 将已有 PDF 登记为 stream 的新增文件，后续由事件自动刷新。

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
