# 部署与运行

入库 SQL 与应用独立部署。Azure 资源由 `infra/azure/` 管理，Snowflake 首次初始化脚本位于 `infra/snowflake/setup/`。账号、连接名和凭据通过本机配置或执行参数提供，不进入仓库。

## Snowflake SQL

推送代码后，从 Snowflake Git 仓库对象执行根目录部署入口：

```sql
USE ROLE MEDRAG_ADMIN;
ALTER GIT REPOSITORY MEDRAG.OPS.REPO FETCH;
EXECUTE IMMEDIATE FROM @MEDRAG.OPS.REPO/branches/main/deploy.sql
  USING (stage_base_url => '<stage_base_url>');
```

`stage_base_url` 取自 `terraform -chdir=infra/azure output -raw stage_base_url`。入口按顺序执行 `src/ingestion/sql/`、`src/serving/sql/` 和 `eval/dataset/`、`eval/retrieval/` 下的模块，并在 `OPS.DEPLOY_LOG` 记录提交与状态；初始化脚本和手工验收 SQL 不包含在其中。任务的启动状态需单独核对。

当前环境中部分 EVAL 对象仍由 ACCOUNTADMIN 持有，snapshot 模块还有混合所有者。本轮本机 CLI 部署按原所有者分别执行，没有变更权限；根 Git 入口统一使用 MEDRAG_ADMIN，尚未验收这批评测模块。通过该入口完整部署前需要先解决评测对象的所有权与访问权限，不能把逐模块部署成功当成 Git 入口已通过。

## 本机 Docker

首次运行复制配置示例，填写 `.env` 中的 Snowflake 账号、用户和 PAT，角色为 MEDRAG_ADMIN：

```sh
cp config/env.example .env
docker compose up --build -d
```

前端为 `http://localhost:8501`，API 文档为 `http://localhost:8000/docs`，探针为 `/healthz`。凭据仅传入后端；前端通过容器网络访问后端。

`PYTHON_IMAGE` 可覆盖基础镜像。例如本机已有缓存时：

```sh
PYTHON_IMAGE=public.ecr.aws/docker/library/python:3.12.11-slim-bookworm docker compose up --build -d
```

当前未实现的 `/search`、`/ask` 返回 501，探针和页面可独立启动。启动检查不代表真实检索与模型调用已验收。

## 本机 Python

```sh
python3.12 -m venv .venv
.venv/bin/python -m pip install -e '.[api,ui,dev]'
```

已有虚拟环境在目录迁移后也需重新执行安装命令，使包路径指向 `src/serving/`；Docker 使用新目录时重新构建镜像。

在两个终端分别运行：

```sh
SNOWFLAKE_CONNECTION_NAME='<本机连接名>' .venv/bin/uvicorn medical_rag.backend.api:app --reload
.venv/bin/streamlit run src/serving/medical_rag/frontend/app.py
```

不指定连接名时，后端读取 Snowflake 环境变量；Python 直接启动不会自动加载 `.env`，需先在终端设置。单元测试使用 `.venv/bin/python -m pytest`，只验证本地参数和引用处理。

## Snowpark Container Services

`deploy/spcs/setup.sql` 准备计算池、镜像仓库、stage 和权限；`service.yaml` 定义两个容器，前端公开，后端仅内部访问。SPCS 后端使用挂载的 OAuth token，无需本机 PAT。首次初始化涉及权限变更，需确认后执行。

应用实现完成且初始化后，从 `SHOW IMAGE REPOSITORIES` 获取 `repository_url`：

```sh
snow spcs image-registry login -c '<本机连接名>'
rag_repository_url='<repository_url>'
docker build --platform linux/amd64 -f deploy/docker/backend.Dockerfile -t "$rag_repository_url/backend:v1" .
docker build --platform linux/amd64 -f deploy/docker/frontend.Dockerfile -t "$rag_repository_url/frontend:v1" .
docker push "$rag_repository_url/backend:v1"
docker push "$rag_repository_url/frontend:v1"
snow sql -c '<本机连接名>' -f deploy/spcs/deploy.sql
```

升级使用新镜像标签，并同步 `service.yaml`，通过 PUT 和 ALTER SERVICE 更新服务。部署后核对容器状态、公开端点及一次完整检索；当前尚未做 SPCS 运行验收。

## 本机辅助工具

当前 .gitignore 忽略整个 scripts/；以下语料工具和 SQL 模板仅保留在已有本机工作区，新 clone 不会包含它们。scripts/check_forbidden.sh 已被 Git 跟踪，忽略规则不影响它继续供 CI 使用。

| 本机文件 | 用途 |
|---|---|
| scripts/fetch_sample_pdfs.py | 初始样本下载，以及其他语料工具复用的来源检查与请求函数 |
| scripts/fetch_corpus.py | 正式语料按批次下载，依赖样本工具 |
| scripts/check_corpus.py | 文件、来源与分布检查，依赖上述两个工具 |
| scripts/sql/backfill_snapshot.sql | 固定快照按配置回填，执行前调整 SET 参数 |
| scripts/sql/run_experiment.sql | 运行检索实验，指定题集、服务和新的实验 ID |

数据与人工审核历史在忽略的 data/；上述工具不是部署入口。正式验收 SQL 在 tests/sql/checks/，单元测试在 tests/unit/，两者纳入版本管理。

## 官方参考

- [Cortex Search Python API](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/query-cortex-search-service)
- [AI_COMPLETE](https://docs.snowflake.com/en/sql-reference/functions/ai_complete-single-string)
- [SPCS 连接 Snowflake](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/spcs-execute-sql)
- [服务定义](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/specification-reference)
