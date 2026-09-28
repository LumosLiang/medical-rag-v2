# 项目地图

## 目录

已经存在:

- `AGENTS.md`:agent 入口。`README.md`:现状和入口命令。
- `.harness/`:现状、规则、检查清单。
- `docs/`:`architecture.md`(架构)、`decisions.md`(取舍、先验证结论)、`pitfalls.md`(坑)。
- `infra/azure/`:Azure 资源的 Terraform。
  - `versions.tf`:Terraform 和 provider 版本、provider 配置。
  - `variables.tf`:输入变量。两个 service principal 的对象 ID 为空时,不建第二阶段的资源。
  - `main.tf`:资源定义。
  - `outputs.tf`:给 Snowflake 用的值(租户 ID、stage 地址、队列地址)。
  - `terraform.tfvars.example`:变量示例。真实值写在 `terraform.tfvars`,不进仓库。
- `scripts/check_forbidden.sh`:提交前扫描不该进仓库的内容。
- `.github/workflows/checks.yml`:推送后在 GitHub Actions 上跑同样的检查。

计划(还没建):

- `sql/`:`00_database`、`01_integrations`、`02_stage`、`03_git_repo`、`10_config`、`11_tables`、`12_doc_metadata`、`20_chunk`、`30_ingest`、`31_task`、`40_search`、`50_checks`、`90_monitor`,以及部署入口脚本。
- `eval/`:`00_schema`、`10_match`、`20_run_eval`、`30_experiment`、`40_labels`。
- `app/`:`src/medrag_app/`(`retrieval`、`generation`、`api`、`ui`、`settings`)、`tests/`、`Dockerfile`、`spcs/service.yaml`。
- `scripts/stage_corpus.py`:一次性语料脚本,在外部机器上运行。

## Snowflake 对象(计划)

- 账户级:存储集成 `MEDRAG_AZURE_STORAGE_INT`、通知集成 `MEDRAG_AZURE_QUEUE_INT`、Git 用的 API 集成。
- 库 `MEDRAG`:
  - `INGEST`:外部 stage、stream、task、`FILE_STATE`、`PARSED_DOCS`
  - `CORE`:`PIPELINE_CONFIG`、`CHUNKS`、`DOC_METADATA`、Cortex Search 服务
  - `EVAL`:标注、运行、结果、指标、基线
  - `OPS`:Git 仓库对象、`CHECK_RESULTS`、`DEPLOY_LOG`
- warehouse 沿用 v1:`MEDICAL_RAG_PARSE_WH`(MEDIUM,解析)、`MEDICAL_RAG_INDEX_WH`(X-SMALL,索引和轻量任务)。

## Azure 资源(`infra/azure/`)

- 资源组:默认 `medrag-rg`,日本东部(和 Snowflake 账户同在东京)。
- 存储账户:StorageV2 + 分层命名空间(ADLS Gen2),名字写在 `terraform.tfvars`。
- 容器 `corpus`。路径约定:`pdf/<PMCID>.pdf` 放语料,`manifest/` 放语料清单,`spike/` 只在先验证时用,用完删掉。
- 队列 `medrag-events`。
- Event Grid system topic `medrag-corpus-events`;事件订阅 `medrag-to-snowflake`(第二阶段)。
- 两条角色分配(第二阶段):存储集成的 service principal 对存储账户有 Storage Blob Data Reader;通知集成的 service principal 对队列有 Storage Queue Data Message Processor。
