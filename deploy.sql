--!jinja
-- 部署入口:按顺序执行入库文件,并把这次部署的提交 sha 记进 OPS.DEPLOY_LOG。
-- infra/snowflake/setup/ 里的引导文件不在这里:它们要 ACCOUNTADMIN 或用户介入,只在新环境里执行一次(见 README 的部署顺序)。
--
-- 只从 main 部署。用 MEDRAG_ADMIN 执行,先推送,再拉取、执行:
--   USE ROLE MEDRAG_ADMIN;
--   ALTER GIT REPOSITORY MEDRAG.OPS.REPO FETCH;
--   EXECUTE IMMEDIATE FROM @MEDRAG.OPS.REPO/branches/main/deploy.sql
--     USING (stage_base_url => '<terraform output 的 stage_base_url>');
-- 值只在执行时传入,不写进仓库。末尾加 DRY_RUN = TRUE 只看渲染结果,不执行。
--
-- 某个文件中途失败就停,前面执行过的不回滚(见 docs/pitfalls.md),所以每个文件都要能重复执行。
-- 失败的部署在 DEPLOY_LOG 里停在 STARTED,finished_at 为空。
-- 注释里不要写 Jinja 的花括号:注释也会被渲染,未传入的变量会让整个文件报错。

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

-- SET 不接受 UUID_STRING() 这类不固定的表达式,要包一层子查询(见 docs/pitfalls.md)。
SET deploy_id = (SELECT UUID_STRING());

-- 执行的文件来自 FETCH 之后 main 指向的提交。
SHOW GIT BRANCHES LIKE 'main' IN GIT REPOSITORY OPS.REPO;

INSERT INTO OPS.DEPLOY_LOG (deploy_id, branch, commit_sha, status, started_at, deployed_by, role_name)
  SELECT $deploy_id, "name", "commit_hash", 'STARTED', CURRENT_TIMESTAMP(), CURRENT_USER(), CURRENT_ROLE()
  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- 按数据流向执行,写法:EXECUTE IMMEDIATE FROM './<模块>/<文件>';(相对路径从本文件所在的目录算)
-- 过程里引用的表只在执行到那一句时才解析,所以前面的过程可以引用后面才建的表。
-- 20_corpus_stage_and_stream.sql 要 stage_base_url:部署时在最后一行传入,这里原样往下传。
-- 有空没写(.harness/context/implementation.md)也能部署:没写的地方只在被调用时抛 NOT_IMPLEMENTED。
EXECUTE IMMEDIATE FROM './src/sql/ingest/10_pipeline_config.sql';
EXECUTE IMMEDIATE FROM './src/sql/ingest/20_corpus_stage_and_stream.sql' USING (stage_base_url => '{{ stage_base_url }}');
EXECUTE IMMEDIATE FROM './src/sql/ingest/30_capture_file_changes.sql';
EXECUTE IMMEDIATE FROM './src/sql/ingest/40_classify_file_changes.sql';
EXECUTE IMMEDIATE FROM './src/sql/ingest/50_remove_old_chunks.sql';
EXECUTE IMMEDIATE FROM './src/sql/ingest/60_parse_documents.sql';
EXECUTE IMMEDIATE FROM './src/sql/ingest/chunk/chunk_doc.sql';
EXECUTE IMMEDIATE FROM './src/sql/ingest/chunk/recursive_baseline.sql';
EXECUTE IMMEDIATE FROM './src/sql/ingest/chunk/recursive_token_limited.sql';
EXECUTE IMMEDIATE FROM './src/sql/ingest/80_run_ingest.sql';
EXECUTE IMMEDIATE FROM './src/sql/ingest/90_ingest_task.sql';
EXECUTE IMMEDIATE FROM './src/sql/search/10_cortex_search.sql';

-- 上面的文件会切换 schema,这里切回来。
USE DATABASE MEDRAG;
USE WAREHOUSE MEDICAL_RAG_INDEX_WH;

UPDATE OPS.DEPLOY_LOG
  SET status = 'SUCCEEDED', finished_at = CURRENT_TIMESTAMP()
  WHERE deploy_id = $deploy_id;

SELECT deploy_id, branch, commit_sha, status, started_at, finished_at
  FROM OPS.DEPLOY_LOG
  WHERE deploy_id = $deploy_id;
