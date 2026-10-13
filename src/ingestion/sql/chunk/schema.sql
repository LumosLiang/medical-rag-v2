-- CHUNKS 保存不同配置的切分结果，也是 Cortex Search 的增量源表。
USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

-- 检索服务的源表。只做增量 DML(INSERT、DELETE、MERGE),不重建、不整表删了重插。
CREATE TABLE IF NOT EXISTS CORE.CHUNKS (
  chunk_id       VARCHAR       NOT NULL COMMENT 'Unique, built from deterministic inputs, stable across reruns; search service primary key',
  doc_id         VARCHAR       NOT NULL,
  relative_path  VARCHAR       NOT NULL,
  etag           VARCHAR       NOT NULL COMMENT 'File version the chunk came from; must be the current version',
  config_name    VARCHAR       NOT NULL COMMENT 'PIPELINE_CONFIG used to chunk it',
  chunk_index    NUMBER        NOT NULL COMMENT 'Order within the document, starting at 0',
  section_path   VARCHAR       COMMENT 'Header path, e.g. Results > Survival',
  chunk_text     VARCHAR       NOT NULL COMMENT 'Stored retrieval text; search-service heading prefixes are computed separately',
  chunk_text_raw VARCHAR       NOT NULL COMMENT 'Legacy duplicate of chunk_text; retained for existing table compatibility',
  token_count    NUMBER        NOT NULL COMMENT 'Tokens in chunk_text, measured with COUNT_TOKENS',
  page_start     NUMBER        COMMENT 'Starting at 0; NULL when pages cannot be matched',
  page_end       NUMBER,
  created_at     TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_chunks PRIMARY KEY (chunk_id)
)
CHANGE_TRACKING = TRUE
COMMENT = 'medrag v2: indexed chunks; incremental DML only';

-- Cortex Search 通过 change tracking 读取源表的增量变化。
ALTER TABLE CORE.CHUNKS SET CHANGE_TRACKING = TRUE;

