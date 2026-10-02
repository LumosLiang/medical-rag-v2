# 项目地图

| 位置 | 用途 |
|---|---|
| `infra/azure/` | 存储、队列、Event Grid、角色分配；真实参数和状态不进仓库 |
| `setup/00`–`03` | 一次性建立角色、库、集成、schema、Git 仓库对象 |
| `deploy.sql` | 从 Git 仓库部署 ingest 各模块，写 OPS.DEPLOY_LOG |
| `ingest/10` | CORE.PIPELINE_CONFIG |
| `ingest/20` | INGEST.CORPUS_STAGE、CORPUS_STREAM |
| `ingest/30`–`50` | 捕获、判断变更、删旧块；INGEST.FILE_CHANGES |
| `ingest/60` | INGEST.PARSE_FILE、PARSED_DOCS |
| `ingest/chunk/` | CORE.CHUNK_DOC 分派与事务、CHUNKS、各切分算法 |
| `search/` | Cortex Search 服务定义；每个服务只读取对应切分配置，当前只建基线服务 |
| `ingest/80` | INGEST.RUN_INGEST |
| `tests/chunk_one_file.sql`、`tests/backfill_baseline.sql`、`tests/cortex_search_one_query.sql` | 手工切分、补齐和检索验收，不进部署入口 |
| `ingest/90` | INGEST.INGEST_TASK，已部署并暂停，自动触发待验收 |
| `spike/`、`data/`、`.harness/local/` | 本地实验、样本、连接检查结果，全部忽略 |

库 MEDRAG，角色 MEDRAG_ADMIN，schema 为 INGEST、CORE、EVAL、OPS。Git 仓库对象为 MEDRAG.OPS.REPO。账户级集成为 MEDRAG_AZURE_STORAGE_INT、MEDRAG_AZURE_QUEUE_INT、MEDRAG_GIT_API_INT。

warehouse 沿用 MEDICAL_RAG_PARSE_WH（解析）、MEDICAL_RAG_INDEX_WH（部署与服务刷新）。基线 Cortex Search 已部署并验收；评测和应用尚未实现。
