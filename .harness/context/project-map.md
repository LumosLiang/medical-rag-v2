# 项目地图

| 位置 | 用途 |
|---|---|
| `infra/azure/` | 存储、队列、Event Grid、角色分配；真实参数和状态不进仓库 |
| `infra/snowflake/setup/00`–`03` | 一次性建立角色、库、集成、schema、Git 仓库对象 |
| `deploy.sql` | 从 Git 仓库部署入库、搜索和评测模块，写 OPS.DEPLOY_LOG |
| `src/sql/ingest/10` | CORE.PIPELINE_CONFIG |
| `src/sql/ingest/20` | INGEST.CORPUS_STAGE、CORPUS_STREAM |
| `src/sql/ingest/30`–`50` | 捕获、判断变更、删旧块；INGEST.FILE_CHANGES |
| `src/sql/ingest/60` | INGEST.PARSE_FILE、PARSED_DOCS |
| `src/sql/ingest/80` | INGEST.RUN_INGEST |
| `src/sql/ingest/90` | INGEST.INGEST_TASK，新增、覆盖和删除自动触发已验收（2026-10-03） |
| `src/sql/ingest/chunk/` | CORE.CHUNK_DOC 分派与事务、CHUNKS、各切分算法 |
| `src/sql/ingest/chunk/markdown_header_table/` | 章节+表格策略，按规范化、结构、分组、定位、算法入口拆分 |
| `src/sql/search/` | 基础搜索服务与同一批块的标题前缀、multi-index 实验服务；只改检索输入，不改切分配置 |
| `src/sql/eval/10`–`40` | PDF 快照、草稿题、审核修订与导入 |
| `src/sql/eval/50` | 固定题集、检索实验（六参数入口和可传 scoring_config 的七参数入口）、证据覆盖判定和指标视图 |
| `tests/sql/checks/` | 手工验收，只读或只写单篇：单篇切分、块验收、markdown 定位率、搜索服务；不进部署入口 |
| `scripts/sql/` | 手工操作模板：固定快照回填、跑一次检索实验；改开头的 SET 即可复用 |
| `tests/unit/` | 本地 pytest：应用骨架、markdown_header_table 的 Python handler |
| `src/medical_rag/backend/`、`src/medical_rag/frontend/` | FastAPI、Streamlit 骨架；核心链路由用户填写 |
| `compose.yaml`、`deploy/spcs/` | 本机 Docker、SPCS 部署文件；独立于入库部署 |
| `docs/experiments/` | 每次实验的设置、结果和结论；实验数字只写在这里 |
| `scripts/` | 纳入版本管理的语料下载、检查与 CI 工具；用法见 scripts/README.md |
| `data/` | 本地 PDF 与来源清单；历史人工审核记录在 data/eval/archive/，全部忽略 |
| `.harness/local/` | 本地连接与检查结果、archive/spike/ 早期实验、learning/ 学习示例，全部忽略 |

库 MEDRAG，角色 MEDRAG_ADMIN，schema 为 INGEST、CORE、EVAL、OPS。Git 仓库对象为 MEDRAG.OPS.REPO。账户级集成为 MEDRAG_AZURE_STORAGE_INT、MEDRAG_AZURE_QUEUE_INT、MEDRAG_GIT_API_INT。

warehouse 沿用 MEDICAL_RAG_PARSE_WH（解析）、MEDICAL_RAG_INDEX_WH（部署与服务刷新）。基线 Cortex Search 已部署并验收；应用骨架已准备，核心链路尚未实现；评测题库和检索评测(src/sql/eval/)已建，生成质量评测未实现。
