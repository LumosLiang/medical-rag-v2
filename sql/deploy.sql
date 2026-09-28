--!jinja
-- 部署入口:按编号顺序执行 sql/ 里的文件,并把这次部署的提交 sha 记进 OPS.DEPLOY_LOG。
-- 引导文件 00–03 不在这里:它们要 ACCOUNTADMIN 或用户介入,只在新环境里执行一次(见 README 的部署顺序)。
--
-- 只从 main 部署。用 MEDRAG_ADMIN 执行,先推送,再拉取、执行:
--   USE ROLE MEDRAG_ADMIN;
--   ALTER GIT REPOSITORY MEDRAG.OPS.REPO FETCH;
--   EXECUTE IMMEDIATE FROM @MEDRAG.OPS.REPO/branches/main/sql/deploy.sql;
-- 加进 04_stage 之后,最后一行要带上 USING (stage_base_url => '<terraform output 的 stage_base_url>')。
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

SET deploy_id = UUID_STRING();

-- 执行的文件来自 FETCH 之后 main 指向的提交。
SHOW GIT BRANCHES LIKE 'main' IN GIT REPOSITORY OPS.REPO;

INSERT INTO OPS.DEPLOY_LOG (deploy_id, branch, commit_sha, status, started_at, deployed_by, role_name)
  SELECT $deploy_id, "name", "commit_hash", 'STARTED', CURRENT_TIMESTAMP(), CURRENT_USER(), CURRENT_ROLE()
  FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- 按编号执行,写法:EXECUTE IMMEDIATE FROM './<文件>';
-- 04_stage.sql 要和 31_task.sql 一起加进来:stream 建好后,没人消费、也没人调用 SYSTEM$STREAM_HAS_DATA,
-- 14 天后就可能过期(见 docs/pitfalls.md)。它要的 USING 参数见 04_stage.sql 的文件头。

UPDATE OPS.DEPLOY_LOG
  SET status = 'SUCCEEDED', finished_at = CURRENT_TIMESTAMP()
  WHERE deploy_id = $deploy_id;

SELECT deploy_id, branch, commit_sha, status, started_at, finished_at
  FROM OPS.DEPLOY_LOG
  WHERE deploy_id = $deploy_id;
