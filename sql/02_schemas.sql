-- 库里的 schema。用 MEDRAG_ADMIN 执行,可以重复执行。
--   snow sql -f sql/02_schemas.sql
-- 前提:00_role.sql 已执行(MEDRAG_ADMIN 存在、拥有 MEDRAG 库、已授给当前用户)。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;

CREATE SCHEMA IF NOT EXISTS INGEST
  COMMENT = 'External stage, stream, task, FILE_STATE, PARSED_DOCS';
CREATE SCHEMA IF NOT EXISTS CORE
  COMMENT = 'PIPELINE_CONFIG, CHUNKS, DOC_METADATA, Cortex Search service';
CREATE SCHEMA IF NOT EXISTS EVAL
  COMMENT = 'Labels, eval runs, results, metrics, baselines';
CREATE SCHEMA IF NOT EXISTS OPS
  COMMENT = 'Git repository object, data check results, deploy log';
