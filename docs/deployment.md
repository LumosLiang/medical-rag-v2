# 初始化与部署

资源初始化、SQL 对象发布和应用容器发布分别执行。代码经 GitHub 同步到 Snowflake Git repository，SQL 从指定版本执行；容器镜像单独构建、推送并更新 SPCS 服务。

## 初始化

Azure 资源由 `infra/azure/` 管理。Snowflake 的角色、数据库、集成、schema、Git repository 和 SPCS 资源统一位于 [infra/snowflake/setup/](../infra/snowflake/setup/)。初始化涉及账户权限；日常对象发布不重复初始化。

| 文件 | 初始化对象 | 执行角色 |
|---|---|---|
| `00_role_and_database.sql` | 项目角色、数据库、warehouse 使用权限与 Cortex 权限 | ACCOUNTADMIN |
| `01_azure_integrations.sql` | Azure storage / notification integrations | ACCOUNTADMIN |
| `02_schemas.sql` | INGEST、CORE、EVAL、OPS | MEDRAG_ADMIN |
| `03_git_repository.sql` | Git API integration 与 repository | 按文件切换角色 |
| `04_spcs.sql` | 计算池、镜像仓库、spec stage 与端点权限 | 按文件切换角色 |

Azure 集成的 tenant、stage 和 queue 地址来自 Terraform 输出；Git repository 地址执行时传入。私有仓库 secret 由用户在 Snowflake 中创建，内容不经过仓库。完成 Azure consent 后，再授予两个 service principal 对应的文件及队列权限。

角色与库先于集成和 schema，schema 与 Git secret 先于 repository；SPCS 资源在首次容器发布前准备。当前账户已完成初始化，不因目录整理重新执行授权或转移所有权。

## 入库与检索 SQL

代码提交、推送后刷新 Snowflake 的 Git 副本，再执行根入口：

```sql
USE ROLE MEDRAG_ADMIN;
ALTER GIT REPOSITORY MEDRAG.OPS.REPO FETCH;
EXECUTE IMMEDIATE FROM @MEDRAG.OPS.REPO/branches/main/deploy.sql
  USING (stage_base_url => '<stage_base_url>');
```

`stage_base_url` 由 `terraform -chdir=infra/azure output -raw stage_base_url` 获取。入口按依赖部署入库及搜索模块，不执行回填、评测、任务恢复或容器发布。需要固定发布版本时，将路径中的 `branches/main` 换为 `commits/<commit_sha>`。

这是 [Snowflake 官方支持的 Git 执行流程](https://docs.snowflake.com/en/developer-guide/git/git-examples)，而非 Git FETCH 自动应用代码。`deploy.sql` 是按依赖组织 SQL 的薄入口，不是迁移框架；发布记录使用 Git 版本与执行结果，不依赖自建部署日志表。已有 `OPS.DEPLOY_LOG` 仅保留历史数据，不再写入。OPS schema 仍承载 Git repository、镜像仓库、spec stage 和服务。

执行失败会停止后续模块，已经成功的语句不会整体回滚。[EXECUTE IMMEDIATE FROM 官方说明](https://docs.snowflake.com/en/sql-reference/sql/execute-immediate-from)。首次创建与更新已有对象也不同：表的 `IF NOT EXISTS` 不会自动迁移结构，搜索定义更新不等于重建索引。发布后核对实际对象、task 状态及源数据与索引行数；验收文件在 `tests/snowflake/`。

## 评测工具

评测工具仅在需要构建题集或运行实验时部署：

```sql
EXECUTE IMMEDIATE FROM @MEDRAG.OPS.REPO/branches/main/eval/deploy.sql;
```

当前部分 EVAL 对象由 ACCOUNTADMIN 持有，snapshot 模块存在混合所有者；不能直接认定 MEDRAG_ADMIN 可以更新全部对象。此前按原所有者逐对象部署，未转移权限。独立 Git 入口的整体运行仍待权限对齐后验证，整理目录不改变现有 owner 或题集。流程与调用示例见 [eval](../eval/README.md)。

## SPCS 应用

`deploy/spcs/service.yaml` 定义前后端容器，前端公开，后端仅内部访问。后端使用挂载的 OAuth token 连接 Snowflake；前端通过内部 HTTP 调用后端。服务角色 `ui_access` 授权前端入口，SQL 中使用未加引号的 `UI_ACCESS`。

从 `SHOW IMAGE REPOSITORIES IN SCHEMA MEDRAG.OPS` 获取 `repository_url`。设置本次镜像标签，并同步 service.yaml 的两个镜像引用：

```sh
snow spcs image-registry login -c '<connection_name>'
rag_repository_url='<repository_url>'
rag_image_tag='<release_tag>'
docker build --provenance=false --platform linux/amd64 -f deploy/docker/backend.Dockerfile -t "$rag_repository_url/backend:$rag_image_tag" .
docker build --provenance=false --platform linux/amd64 -f deploy/docker/frontend.Dockerfile -t "$rag_repository_url/frontend:$rag_image_tag" .
docker push "$rag_repository_url/backend:$rag_image_tag"
docker push "$rag_repository_url/frontend:$rag_image_tag"
snow sql -c '<connection_name>' -f deploy/spcs/deploy.sql
```

部署入口上传 spec，创建不存在的服务或更新同一服务，再返回容器状态及端点。公开地址以 `SHOW ENDPOINTS IN SERVICE MEDRAG.OPS.MEDICAL_RAG_APP` 的 ingress_url 为准，使用 Snowflake 身份登录。验收要求容器 READY，并完成真实 `/search`、`/ask` 调用。当前已部署镜像标签为 `20261013-citations`。2026-10-16 更新 service.yaml 的 RAG_CONFIG_NAME 与 RAG_SEARCH_SERVICE，将应用切换到 8K 配置，两容器 READY；本次只更新环境配置，没有重建镜像。此前同镜像的云端 OAuth 验证任务已通过检索、生成与逐条摘录校验，本次真实 Streamlit AppTest 经本机 FastAPI 调用云端 8K 检索与生成通过；没有将其记为本次公开端点或新云端 OAuth 探针验收。

账号、凭据及连接名由本机配置或运行参数提供，不写入仓库。受限 PAT 不能执行 `USE ROLE` 时，在本机执行副本中移除角色语句并由 CLI 指定原角色，不修改仓库的标准角色声明。

## 本地开发（可选）

SPCS 不依赖 Docker Compose。`deploy/docker/compose.yaml` 仅用于本机联调或镜像检查，路径不属于云端发布链路：

```sh
cp config/env.example .env
# 填写仅供后端使用的本机 Snowflake 连接参数。
docker compose -f deploy/docker/compose.yaml up --build -d
```

前端为 `http://localhost:8501`，API 文档为 `http://localhost:8000/docs`。若直接运行 Python：

```sh
python3.12 -m venv .venv
.venv/bin/python -m pip install -e '.[api,ui,dev]'
SNOWFLAKE_CONNECTION_NAME='<connection_name>' .venv/bin/uvicorn medical_rag.backend.api:app --reload
# 在另一终端运行前端。
.venv/bin/streamlit run src/serving/medical_rag/frontend/app.py
```

Python 直接启动不会自动加载 `.env`。`data/` 保留本机语料，操作与历史工具记录归档于 `.harness/local/`，不作为新 clone 的运行依赖。CI 敏感信息检查位于 `.github/scripts/check_forbidden.sh`。

## 测试与验收

本地测试验证代码行为，Snowflake SQL 验证实际数据与服务状态。检索质量对照位于独立的 [eval](../eval/README.md)，不混入单元测试。

| 位置 | 验证内容 |
|---|---|
| `tests/ingestion/` | 表格边界、重复上下文、章节继承及位置标注的回归 |
| `tests/serving/` | API 输入、检索映射、生成结果与引用错误处理 |
| `eval/tests/` | 完成状态与零返回题的指标分母 |
| `tests/snowflake/` | 单篇切分、全库块校验、定位统计与搜索服务检查 |

```sh
.venv/bin/python -m pytest
```

pytest 不连接 Azure 或 Snowflake。嵌入 Python handler 的检查不代替 Snowflake 原生函数运行验收；SQLite 指标测试只验证基础查询，不验证 Snowflake 的完整视图语法。

`chunk_one_file.sql` 将结果写入会话临时表，便于逐块查看，不替换生产 CHUNKS。其他 SQL 为只读检查，执行前选择配置与快照。基线允许超过 512 token；限窗策略要求没有超限块。单篇检查看页码、章节、完整原文及重复调用结果；全库检查看文件版本、缺文档、空块、重复 ID 和 token 分布。

## 官方参考

- [Azure directory table 自动刷新](https://docs.snowflake.com/en/user-guide/data-load-dirtables-auto-azure)
- [Cortex Search 查询](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/query-cortex-search-service)
- [SPCS 连接 Snowflake](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/spcs-execute-sql)
- [SPCS 服务定义](https://docs.snowflake.com/en/developer-guide/snowpark-container-services/specification-reference)
