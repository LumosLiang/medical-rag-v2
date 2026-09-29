-- 解析和切分用的配置。由 deploy.sql 调用,可以重复执行。
--
-- 规则(用户定,2026-09-28):
--   - 配置名一旦部署,参数就固定。要换参数,新建一个名字。文件里改了已部署配置的参数,部署报 -20101。
--   - 只有 is_active 和 note 能改,随部署生效。入库用 is_active 的那个,必须正好一个。
--   - 表里的配置不删:块表和评测结果按配置名引用它们。从文件里删掉的配置,部署时 is_active 置为 FALSE。
--   - 切换 is_active 不会自动重切已经入库的文档;重切怎么做,到时候再定。
--
-- 部署报 -20101 时,在同一个会话里查是哪个配置被改了(CONFIG_FROM_REPO 是这次部署建的会话临时表):
--   SELECT r.config_name
--     FROM (SELECT config_name, HASH(* EXCLUDE (is_active, note, created_at)) AS h FROM MEDRAG.CORE.CONFIG_FROM_REPO) r
--     JOIN (SELECT config_name, HASH(* EXCLUDE (is_active, note, created_at)) AS h FROM MEDRAG.CORE.PIPELINE_CONFIG) t
--       USING (config_name)
--    WHERE r.h <> t.h;

USE ROLE MEDRAG_ADMIN;
USE SCHEMA MEDRAG.CORE;

CREATE TABLE IF NOT EXISTS PIPELINE_CONFIG (
  config_name              VARCHAR       NOT NULL COMMENT 'Config name; parameters never change once deployed',
  parse_mode               VARCHAR       NOT NULL COMMENT 'AI_PARSE_DOCUMENT mode: LAYOUT or OCR',
  page_split               BOOLEAN       NOT NULL COMMENT 'AI_PARSE_DOCUMENT page_split',
  split_headers            OBJECT        NOT NULL COMMENT 'SPLIT_TEXT_MARKDOWN_HEADER headers_to_split_on, e.g. #: header_1, ##: header_2',
  chunk_size_chars         NUMBER        NOT NULL COMMENT 'Maximum chunk size, in characters',
  chunk_overlap_chars      NUMBER        NOT NULL COMMENT 'Overlap between chunks, in characters',
  max_tokens               NUMBER        NOT NULL COMMENT 'Hard cap on tokens per indexed chunk; longer chunks are split again',
  token_model              VARCHAR       NOT NULL COMMENT 'Model for SNOWFLAKE.CORTEX.COUNT_TOKENS; must match the search service embedding model',
  resplit_chunk_size_chars NUMBER        NOT NULL COMMENT 'SPLIT_TEXT_RECURSIVE_CHARACTER chunk_size for chunks over max_tokens, in characters',
  drop_reference_sections  BOOLEAN       NOT NULL COMMENT 'Drop reference-list sections',
  add_prefix               BOOLEAN       NOT NULL COMMENT 'Prefix indexed text with title > section',
  is_active                BOOLEAN       NOT NULL COMMENT 'Ingest uses this config; exactly one is TRUE',
  note                     VARCHAR       COMMENT 'Why this config exists',
  created_at               TIMESTAMP_LTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
  CONSTRAINT pk_pipeline_config PRIMARY KEY (config_name)
)
COMMENT = 'medrag v2: parse and chunk parameters; a config never changes once deployed';

-- 已有表增量加列。旧配置保持原方法，新配置显式选择 recursive。
ALTER TABLE PIPELINE_CONFIG ADD COLUMN IF NOT EXISTS chunk_method VARCHAR;
ALTER TABLE PIPELINE_CONFIG ADD COLUMN IF NOT EXISTS split_format VARCHAR;
UPDATE PIPELINE_CONFIG
   SET chunk_method = COALESCE(chunk_method, 'markdown_header'),
       split_format = COALESCE(split_format, 'none')
 WHERE chunk_method IS NULL OR split_format IS NULL;
ALTER TABLE PIPELINE_CONFIG ALTER COLUMN chunk_method SET NOT NULL;
ALTER TABLE PIPELINE_CONFIG ALTER COLUMN split_format SET NOT NULL;

-- 仓库里定义的配置先放进会话临时表,和已部署的比对过再写入。
CREATE OR REPLACE TEMPORARY TABLE CONFIG_FROM_REPO LIKE PIPELINE_CONFIG;

INSERT INTO CONFIG_FROM_REPO (
  config_name, parse_mode, page_split, split_headers, chunk_size_chars, chunk_overlap_chars,
  max_tokens, token_model, resplit_chunk_size_chars, drop_reference_sections, add_prefix,
  is_active, note, chunk_method, split_format)
-- 旧配置参数保留，停用；已部署配置不原地改参数。
SELECT 'base_1200', 'LAYOUT', TRUE, OBJECT_CONSTRUCT('#', 'header_1', '##', 'header_2', '###', 'header_3'),
       1200, 0, 512, 'snowflake-arctic-embed-l-v2.0', 1000, FALSE, FALSE,
       FALSE, 'original markdown-header baseline; inactive', 'markdown_header', 'none'
UNION ALL
-- recursive 基线：格式 none，省略 separators 参数，使用 Snowflake 默认分隔符。
-- chunk_size 没有默认值，overlap 默认 0；1200 / 200 是项目选择，不是 Snowflake 默认。
-- split_headers 在 recursive 配置中不使用，保留空 OBJECT 兼容已有表结构。
SELECT 'recursive_1200_200', 'LAYOUT', TRUE, OBJECT_CONSTRUCT(),
       1200, 200, 512, 'snowflake-arctic-embed-l-v2.0', 1000, FALSE, FALSE,
       TRUE, 'recursive baseline; project size 1200/overlap 200; Snowflake default separators', 'recursive', 'none'
;

-- 先把所有检查做完,都通过了才写表;写表的两步放在一个事务里。
EXECUTE IMMEDIATE $$
DECLARE
  v_changed    INTEGER;
  v_duplicates INTEGER;
  v_repo_total INTEGER;
  v_repo_active INTEGER;
  v_table_total INTEGER;
  config_changed EXCEPTION (-20101, '10_pipeline_config: a deployed config had its parameters changed; add a new config name instead (query in the header of ingest/10_pipeline_config.sql)');
  active_not_one EXCEPTION (-20102, '10_pipeline_config: exactly one config must have is_active = TRUE');
  duplicate_name EXCEPTION (-20103, '10_pipeline_config: the same config name appears more than once in the file');
BEGIN
  SELECT COUNT(*) - COUNT(DISTINCT config_name), COUNT(*), COUNT_IF(is_active)
    INTO :v_duplicates, :v_repo_total, :v_repo_active
    FROM CONFIG_FROM_REPO;
  IF (v_duplicates > 0) THEN
    RAISE duplicate_name;
  END IF;

  SELECT COUNT(*) INTO :v_changed
    FROM (SELECT config_name, HASH(* EXCLUDE (is_active, note, created_at)) AS h FROM CONFIG_FROM_REPO) r
    JOIN (SELECT config_name, HASH(* EXCLUDE (is_active, note, created_at)) AS h FROM PIPELINE_CONFIG) t
      USING (config_name)
   WHERE r.h <> t.h;
  IF (v_changed > 0) THEN
    RAISE config_changed;
  END IF;

  -- 写完之后,is_active 的配置就是文件里 is_active 的那些(不在文件里的会被置为 FALSE)。
  SELECT COUNT(*) INTO :v_table_total FROM PIPELINE_CONFIG;
  IF ((v_repo_total > 0 OR v_table_total > 0) AND v_repo_active <> 1) THEN
    RAISE active_not_one;
  END IF;

  BEGIN TRANSACTION;
  MERGE INTO PIPELINE_CONFIG t
  USING CONFIG_FROM_REPO r
     ON t.config_name = r.config_name
  WHEN MATCHED THEN UPDATE SET
    is_active = r.is_active,
    note      = r.note
  WHEN NOT MATCHED THEN INSERT (
    config_name, parse_mode, page_split, split_headers, chunk_size_chars, chunk_overlap_chars,
    max_tokens, token_model, resplit_chunk_size_chars, drop_reference_sections, add_prefix,
    is_active, note, chunk_method, split_format)
  VALUES (
    r.config_name, r.parse_mode, r.page_split, r.split_headers, r.chunk_size_chars, r.chunk_overlap_chars,
    r.max_tokens, r.token_model, r.resplit_chunk_size_chars, r.drop_reference_sections, r.add_prefix,
    r.is_active, r.note, r.chunk_method, r.split_format);

  UPDATE PIPELINE_CONFIG
     SET is_active = FALSE
   WHERE is_active
     AND config_name NOT IN (SELECT config_name FROM CONFIG_FROM_REPO);
  COMMIT;

  RETURN v_repo_total::VARCHAR || ' config(s) in file';
EXCEPTION
  WHEN OTHER THEN
    ROLLBACK;
    RAISE;
END;
$$;
