-- 入库链路的三张表。由 deploy.sql 调用,可以重复执行:表已经存在就不动。
--
-- 以后加列:在对应的 CREATE TABLE 后面写 ALTER TABLE ... ADD COLUMN IF NOT EXISTS。
-- 只改 CREATE TABLE 本身不会影响已经部署的表。
-- CHUNKS 的列要在环节 7 建检索服务之前定下来:服务建好后再改 source query 的列,会触发全量重新 embedding(docs/pitfalls.md)。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

-- 每个文件变更一行:入库过程第一步把 stream 这一批 INSERT ... SELECT 进来(环节 2A)。
-- 覆盖在 stream 里是一删一增,这里就是两行。status 的约定见 sql/30_ingest.sql 的 PLAN_BATCH。
CREATE TABLE IF NOT EXISTS INGEST.FILE_STATE (
  batch_id      VARCHAR       NOT NULL COMMENT 'One per RUN_INGEST run',
  relative_path VARCHAR       NOT NULL COMMENT 'Path inside CORPUS_STAGE, e.g. PMC123.pdf',
  etag          VARCHAR       NOT NULL COMMENT 'File version; for DELETE rows, the version that was removed',
  size          NUMBER,
  last_modified TIMESTAMP_LTZ,
  change_action VARCHAR       NOT NULL COMMENT 'METADATA$ACTION from the stream: INSERT or DELETE',
  is_update     BOOLEAN       COMMENT 'METADATA$ISUPDATE from the stream',
  status        VARCHAR       NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING, then READY (to parse and chunk), then DONE or FAILED; other values decided by PLAN_BATCH',
  error_message VARCHAR       COMMENT 'Error text when FAILED',
  retry_count   NUMBER        NOT NULL DEFAULT 0,
  captured_at   TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP() COMMENT 'When the row was copied from the stream',
  updated_at    TIMESTAMP_LTZ COMMENT 'When status last changed'
)
COMMENT = 'medrag v2: one row per file change captured from CORPUS_STREAM';

-- AI_PARSE_DOCUMENT 的原样输出。每次解析尝试一行,成功的版本最多一行。
-- 改切分只读这张表,不重新解析:解析按页计费,是整条流程里最贵的一步。
CREATE TABLE IF NOT EXISTS INGEST.PARSED_DOCS (
  relative_path VARCHAR       NOT NULL,
  etag          VARCHAR       NOT NULL,
  doc_id        VARCHAR       NOT NULL COMMENT 'File name without .pdf, i.e. the PMCID; labels refer to it',
  parse_options OBJECT        COMMENT 'Options passed to AI_PARSE_DOCUMENT',
  parse_result  VARIANT       COMMENT 'AI_PARSE_DOCUMENT output as returned',
  page_count    NUMBER,
  error_message VARCHAR       COMMENT 'NULL means the parse succeeded',
  parsed_at     TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'medrag v2: raw AI_PARSE_DOCUMENT output per parse attempt; the only input when re-chunking';

-- 检索服务的源表。只做增量 DML(INSERT、DELETE、MERGE),不重建、不整表删了重插。
CREATE TABLE IF NOT EXISTS CORE.CHUNKS (
  chunk_id       VARCHAR       NOT NULL COMMENT 'Unique, built from deterministic inputs, stable across reruns; search service primary key',
  doc_id         VARCHAR       NOT NULL,
  relative_path  VARCHAR       NOT NULL,
  etag           VARCHAR       NOT NULL COMMENT 'File version the chunk came from; must be the current version',
  config_name    VARCHAR       NOT NULL COMMENT 'PIPELINE_CONFIG used to chunk it',
  chunk_index    NUMBER        NOT NULL COMMENT 'Order within the document, starting at 0',
  section_path   VARCHAR       COMMENT 'Header path, e.g. Results > Survival',
  chunk_text     VARCHAR       NOT NULL COMMENT 'Indexed text, with prefix',
  chunk_text_raw VARCHAR       NOT NULL COMMENT 'Original text, for display and evidence matching',
  token_count    NUMBER        NOT NULL COMMENT 'Tokens in chunk_text, measured with COUNT_TOKENS',
  page_start     NUMBER        COMMENT 'Starting at 0; NULL when pages cannot be matched',
  page_end       NUMBER,
  created_at     TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_chunks PRIMARY KEY (chunk_id)
)
CHANGE_TRACKING = TRUE
COMMENT = 'medrag v2: indexed chunks; incremental DML only';

-- 表已存在时 CREATE 不会生效,这里再确认一次 change tracking 是开的(Cortex Search 需要)。
ALTER TABLE CORE.CHUNKS SET CHANGE_TRACKING = TRUE;
