--!jinja
-- 部署按依赖建立入库、搜索和评测对象，并记录所执行的 Git 提交及完成状态。
-- 初始化资源由 infra/ 单独建立；这里不运行回填、实验 CALL 或应用容器。
-- 模块中途失败时停止，前面已执行的 DDL 不回滚，日志保持 STARTED。

USE ROLE MEDRAG_ADMIN;
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_INDEX_WH;

CREATE TABLE IF NOT EXISTS OPS.DEPLOY_LOG (
  deploy_id   VARCHAR       NOT NULL COMMENT 'UUID, one per deploy',
  branch      VARCHAR       NOT NULL,
  commit_sha  VARCHAR       NOT NULL COMMENT 'Commit the branch pointed to after FETCH; the executed files come from it',
  status      VARCHAR       NOT NULL COMMENT 'STARTED or SUCCEEDED; STARTED with no finished_at means the deploy stopped midway',
  started_at  TIMESTAMP_LTZ NOT NULL,
  finished_at TIMESTAMP_LTZ,
  deployed_by VARCHAR       NOT NULL,
  role_name   VARCHAR       NOT NULL
)
COMMENT = 'medrag v2: one row per deploy from the Git repository object';

-- 为本次部署生成日志标识。
SET deploy_id = (SELECT UUID_STRING());

-- 执行的文件来自 FETCH 之后 main 指向的提交。
SHOW GIT BRANCHES LIKE 'main' IN GIT REPOSITORY OPS.REPO;

INSERT INTO OPS.DEPLOY_LOG (deploy_id, branch, commit_sha, status, started_at, deployed_by, role_name)
  SELECT $deploy_id, "name", "commit_hash", 'STARTED', CURRENT_TIMESTAMP(), CURRENT_USER(), CURRENT_ROLE()
  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- 先建立数据与算法依赖，再建立搜索索引及评测对象。
EXECUTE IMMEDIATE FROM './src/ingestion/sql/10_pipeline_config.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/20_corpus_stage_and_stream.sql' USING (stage_base_url => '{{ stage_base_url }}');
EXECUTE IMMEDIATE FROM './src/ingestion/sql/30_capture_file_changes.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/40_classify_file_changes.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/50_remove_old_chunks.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/60_parse_documents.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/chunk_doc.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/recursive_baseline.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/recursive_token_limited.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/structured_markdown/prepare_document.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/structured_markdown/extract_elements.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/structured_markdown/build_table_chunks.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/structured_markdown/annotate_chunks.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/structured_markdown/chunk_document.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/chunk/structured_markdown/compatibility.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/80_run_ingest.sql';
EXECUTE IMMEDIATE FROM './src/ingestion/sql/90_ingest_task.sql';
EXECUTE IMMEDIATE FROM './src/serving/sql/10_recursive_baseline.sql';
EXECUTE IMMEDIATE FROM './src/serving/sql/20_section_body.sql';
EXECUTE IMMEDIATE FROM './src/serving/sql/30_heading_prefix.sql';
EXECUTE IMMEDIATE FROM './src/serving/sql/40_section_multi_index.sql';
EXECUTE IMMEDIATE FROM './eval/dataset/tables.sql';
EXECUTE IMMEDIATE FROM './eval/dataset/snapshot.sql';
EXECUTE IMMEDIATE FROM './eval/dataset/draft_questions.sql';
EXECUTE IMMEDIATE FROM './eval/dataset/review_questions.sql';
EXECUTE IMMEDIATE FROM './eval/dataset/question_sets.sql';
EXECUTE IMMEDIATE FROM './eval/retrieval/tables.sql';
EXECUTE IMMEDIATE FROM './eval/retrieval/score_evidence.sql';
EXECUTE IMMEDIATE FROM './eval/retrieval/run_experiment.sql';
EXECUTE IMMEDIATE FROM './eval/retrieval/metrics.sql';

-- 上面的文件会切换 schema,这里切回来。
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_INDEX_WH;

UPDATE OPS.DEPLOY_LOG
  SET status = 'SUCCEEDED', finished_at = CURRENT_TIMESTAMP()
  WHERE deploy_id = $deploy_id;

SELECT deploy_id, branch, commit_sha, status, started_at, finished_at
  FROM OPS.DEPLOY_LOG
  WHERE deploy_id = $deploy_id;
