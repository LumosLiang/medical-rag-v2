--!jinja
-- Git 仓库对象。建好之后,仓库里的 SQL 都从这里执行:
--   EXECUTE IMMEDIATE FROM @MEDRAG.OPS.REPO/branches/main/sql/<文件>
-- 私有仓库,用只读 token 认证(官方建议自动化场景用 token,不用 OAuth)。
--
-- 分三段,顺序不能乱:
--
-- 第 1 段:用户自己做,token 不经过别人。
--   1. GitHub 上建 fine-grained token:只选这一个仓库,Repository permissions 里 Contents 设为 Read-only。
--   2. 在 Snowsight 里执行(用户名和 token 换成真实值):
--        USE ROLE MEDRAG_ADMIN;
--        CREATE SECRET IF NOT EXISTS MEDRAG.OPS.GITHUB_READONLY
--          TYPE = PASSWORD
--          USERNAME = '<GitHub 用户名>'
--          PASSWORD = '<token>'
--          COMMENT = 'medrag v2: read-only GitHub token for the Git repository object';
--
-- 第 2、3 段:本文件。仓库地址执行时传入,不写进仓库:
--   snow sql -f sql/03_git_repo.sql --enable-templating JINJA -D repo_url="$(git remote get-url origin)"
--
-- token 到期后:在 GitHub 上重新生成,再 ALTER SECRET MEDRAG.OPS.GITHUB_READONLY SET PASSWORD = '<新 token>'。

-- 第 2 段:账户级的 API 集成,只放行这一个仓库、只认上面那个 secret。
USE ROLE ACCOUNTADMIN;

CREATE API INTEGRATION IF NOT EXISTS MEDRAG_GIT_API_INT
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('{{ repo_url }}')
  ALLOWED_AUTHENTICATION_SECRETS = (MEDRAG.OPS.GITHUB_READONLY)
  ENABLED = TRUE
  COMMENT = 'medrag v2: read-only access to the project repository';

GRANT USAGE ON INTEGRATION MEDRAG_GIT_API_INT TO ROLE MEDRAG_ADMIN;

-- 第 3 段:仓库对象归 MEDRAG_ADMIN。建好后先拉一次,再看 main 指向哪个提交。
USE ROLE MEDRAG_ADMIN;

CREATE GIT REPOSITORY IF NOT EXISTS MEDRAG.OPS.REPO
  API_INTEGRATION = MEDRAG_GIT_API_INT
  GIT_CREDENTIALS = MEDRAG.OPS.GITHUB_READONLY
  ORIGIN = '{{ repo_url }}'
  COMMENT = 'medrag v2: SQL in this repository is executed from this clone';

ALTER GIT REPOSITORY MEDRAG.OPS.REPO FETCH;

SHOW GIT BRANCHES IN GIT REPOSITORY MEDRAG.OPS.REPO;
