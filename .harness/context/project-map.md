# 项目地图

| 位置 | 职责 |
|---|---|
| infra/azure/ | ADLS、Queue、Event Grid 与 Azure 权限 |
| infra/snowflake/setup/ | 角色、数据库、集成、schema、Git repository 与 SPCS 资源初始化 |
| deploy.sql | 21 个入库与检索模块的 Git 发布入口 |
| deploy/docker/ | 镜像构建与可选本机 Compose |
| deploy/spcs/ | 容器 spec、服务创建与升级 |
| src/ingestion/sql/ | 捕获、分类、删除旧版本、解析、调度 |
| src/ingestion/sql/chunk/ | CHUNKS、统一事务入口、recursive 与结构化 Markdown 策略 |
| src/serving/cortex_search/ | 四套检索服务定义 |
| src/serving/medical_rag/ | FastAPI、检索和生成服务、Streamlit 与会话管理 |
| eval/schema.sql、eval/deploy.sql | 评测表结构与独立发布入口 |
| eval/dataset/、eval/retrieval/ | 题集构建与检索实验 |
| tests/ingestion/、tests/serving/、eval/tests/ | 本地回归 |
| tests/snowflake/ | 临时表单篇切分与只读运行检查 |
| docs/ | 架构、工程难点、部署与实验结果 |
| .github/scripts/ | CI 敏感信息检查 |
| data/、.harness/local/ | 忽略的本机语料、历史工具与运行证据 |

数据库 MEDRAG；业务角色 MEDRAG_ADMIN；schema 为 INGEST、CORE、EVAL、OPS。OPS 保留 Git repository、镜像仓库、spec stage 与应用服务。DEPLOY_LOG 历史表不再由入口写入。

仓库中的路径与配置是正式源；运行状态以 current-state.md 为准，数字以 docs/experiments/ 为准。本机忽略文件不是新 clone 的必要依赖。
