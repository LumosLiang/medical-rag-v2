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

`stage_base_url` 取自 `terraform -chdir=infra/azure output -raw stage_base_url`。入口按顺序执行 `src/sql/` 下的模块，并在 `OPS.DEPLOY_LOG` 记录提交与状态；初始化脚本和手工验收 SQL 不包含在其中。任务的启动状态需单独核对。

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

在两个终端分别运行：

```sh
SNOWFLAKE_CONNECTION_NAME='<本机连接名>' .venv/bin/uvicorn medical_rag.backend.api:app --reload
.venv/bin/streamlit run src/medical_rag/frontend/app.py
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

## 官方参考

- [Cortex Search Python API](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/query-cortex-search-service)
- [AI_COMPLETE](https://docs.snowflake.com/en/sql-reference/functions/ai_complete-single-string)
- [SPCS 连接 Snowflake](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/spcs-execute-sql)
- [服务定义](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/specification-reference)
