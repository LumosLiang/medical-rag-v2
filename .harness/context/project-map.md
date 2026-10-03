# 项目地图

| 位置 | 用途 |
|---|---|
| `infra/azure/` | 存储、队列、Event Grid、角色分配；真实参数和状态不进仓库 |
| `infra/snowflake/setup/00`–`03` | 一次性建立角色、库、集成、schema、Git 仓库对象 |
| `deploy.sql` | 从 Git 仓库部署入库和搜索模块，写 OPS.DEPLOY_LOG |
| `src/sql/ingest/10` | CORE.PIPELINE_CONFIG |
| `src/sql/ingest/20` | INGEST.CORPUS_STAGE、CORPUS_STREAM |
| `src/sql/ingest/30`–`50` | 捕获、判断变更、删旧块；INGEST.FILE_CHANGES |
| `src/sql/ingest/60` | INGEST.PARSE_FILE、PARSED_DOCS |
| `src/sql/ingest/chunk/` | CORE.CHUNK_DOC 分派与事务、CHUNKS、各切分算法 |
| `src/sql/search/` | Cortex Search 服务定义；每个服务只读取对应切分配置，当前只建基线服务 |
| `src/medical_rag/backend/`、`src/medical_rag/frontend/` | FastAPI、Streamlit 骨架；核心链路由用户填写 |
| `compose.yaml`、`deploy/spcs/` | 本机 Docker、SPCS 部署文件；独立于入库部署 |
| `src/sql/ingest/80` | INGEST.RUN_INGEST |
| `tests/sql/chunk_one_file.sql`、`tests/sql/backfill_baseline.sql`、`tests/sql/cortex_search_one_query.sql` | 手工切分、补齐和检索验收，不进部署入口 |
| `src/sql/ingest/90` | INGEST.INGEST_TASK，上传自动触发已验收，覆盖和删除待验收 |
| `spike/`、`data/`、`.harness/local/` | 本地实验、样本、连接检查结果，全部忽略 |

库 MEDRAG，角色 MEDRAG_ADMIN，schema 为 INGEST、CORE、EVAL、OPS。Git 仓库对象为 MEDRAG.OPS.REPO。账户级集成为 MEDRAG_AZURE_STORAGE_INT、MEDRAG_AZURE_QUEUE_INT、MEDRAG_GIT_API_INT。

warehouse 沿用 MEDICAL_RAG_PARSE_WH（解析）、MEDICAL_RAG_INDEX_WH（部署与服务刷新）。基线 Cortex Search 已部署并验收；应用骨架已准备，核心链路和评测尚未实现。
