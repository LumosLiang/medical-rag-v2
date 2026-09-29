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
- `setup/`:一次性引导,已执行过,不进部署。
  - `00_role_and_database.sql`:专用角色 MEDRAG_ADMIN、MEDRAG 库、账户级权限(ACCOUNTADMIN 执行)。
  - `01_azure_integrations.sql`:Azure 存储集成和通知集成,以及授给 MEDRAG_ADMIN 的 USAGE(ACCOUNTADMIN 执行,值在执行时传入)。
  - `02_schemas.sql`:四个 schema(MEDRAG_ADMIN 执行)。
  - `03_git_repository.sql`:Git 用的 API 集成(ACCOUNTADMIN)和 Git 仓库对象 `MEDRAG.OPS.REPO`(MEDRAG_ADMIN);只读 token 的 secret `MEDRAG.OPS.GITHUB_READONLY` 由用户自己建。
- `deploy.sql`(根目录):部署入口。只从 main 部署;按数据流向嵌套执行 `ingest/` 里的文件,每次在 `OPS.DEPLOY_LOG` 记一行。
- `ingest/`:入库,一个文件一步,按数据流向编号;每个文件放这一步用到的表和做这一步的过程。
  - `10_pipeline_config.sql`:`CORE.PIPELINE_CONFIG`,以及"已部署的配置不可改"的检查。
  - `20_corpus_stage_and_stream.sql`:语料的外部 stage `INGEST.CORPUS_STAGE`(容器里的 `pdf/`,directory table 自动刷新)和 stream `INGEST.CORPUS_STREAM`。还没加进部署入口,要和 `90_ingest_task` 一起加。
  - `30_capture_file_changes.sql`:表 `INGEST.FILE_CHANGES`(状态约定在文件头)和捕获变更 `INGEST.CAPTURE_CHANGES`。
  - `40_classify_file_changes.sql`:判断变更 `INGEST.CLASSIFY_CHANGES`。
  - `50_remove_old_chunks.sql`:删旧块 `INGEST.REMOVE_OLD_CHUNKS`。
  - `60_parse_documents.sql`:表 `INGEST.PARSED_DOCS` 和解析 `INGEST.PARSE_FILE`。
  - `70_chunk_documents.sql`:块表 `CORE.CHUNKS` 和切分 `CORE.CHUNK_DOC`。
  - `80_run_ingest.sql`:入口 `INGEST.RUN_INGEST`,按顺序调用上面几步。
  - `90_ingest_task.sql`:入库 task(还没加进部署入口)。
- `spike/`:先验证和动手实验的脚本,不进部署入口。只在本机,不进仓库。
- `docs/hands-on.md`:每个环节留给用户的空、验收和状态。
- `scripts/fetch_sample_pdfs.py`(只在本机,不进仓库):从 PMC 的公开 S3 桶随机取 10 篇近 5 年的临床医学论文 PDF(一次性,只用标准库)。结果在 `data/sample/`:`pdf/<PMCID>.pdf` 不进仓库,`manifest.csv` 记每篇的来源和入选依据。

计划(还没建):

- `ingest/12_doc_metadata.sql`(文档元数据);按模块分的目录 `search/`(Cortex Search)、`checks/`(数据检查)、`monitor/`,都从根目录的 `deploy.sql` 部署。
- `eval/`:`00_schema`、`10_match`、`20_run_eval`、`30_experiment`、`40_labels`。
- `app/`:`src/medrag_app/`(`retrieval`、`generation`、`api`、`ui`、`settings`)、`tests/`、`Dockerfile`、`spcs/service.yaml`。
- `scripts/stage_corpus.py`:一次性语料脚本,在外部机器上运行。

## Snowflake 对象

- 角色 `MEDRAG_ADMIN`(已建成):拥有 MEDRAG 库和里面的所有对象,task 按它的权限运行;挂在 SYSADMIN 下面。
- 账户级,由 ACCOUNTADMIN 拥有、把 USAGE 授给 MEDRAG_ADMIN:存储集成 `MEDRAG_AZURE_STORAGE_INT`、通知集成 `MEDRAG_AZURE_QUEUE_INT`、Git 用的 API 集成 `MEDRAG_GIT_API_INT`(都已建成)。
- 库 `MEDRAG`(库和四个 schema 已建成;下面没标"已建成"的对象都还是计划):
  - `INGEST`:外部 stage `CORPUS_STAGE`、stream `CORPUS_STREAM`、task、`FILE_CHANGES`、`PARSED_DOCS`,以及入库的几个过程
  - `CORE`:`PIPELINE_CONFIG`、`CHUNKS`、`DOC_METADATA`、Cortex Search 服务
  - `EVAL`:标注、运行、结果、指标、基线
  - `OPS`:Git 仓库对象 `REPO` 和 secret `GITHUB_READONLY`(已建成)、`DEPLOY_LOG`、`CHECK_RESULTS`
- warehouse 沿用 v1:`MEDICAL_RAG_PARSE_WH`(MEDIUM,解析)、`MEDICAL_RAG_INDEX_WH`(X-SMALL,索引和轻量任务)。

## Azure 资源(`infra/azure/`)

- 资源组:默认 `medrag-rg`,日本东部(和 Snowflake 账户同在东京)。
- 存储账户:StorageV2 + 分层命名空间(ADLS Gen2),名字写在 `terraform.tfvars`。
- 容器 `corpus`。路径约定:`pdf/<PMCID>.pdf` 放语料,`manifest/` 放语料清单,`spike/` 只在先验证时用,用完删掉。
- 队列 `medrag-events`。
- Event Grid system topic `medrag-corpus-events`;事件订阅 `medrag-to-snowflake`(第二阶段)。
- 两条角色分配(第二阶段):存储集成的 service principal 对存储账户有 Storage Blob Data Reader;通知集成的 service principal 对队列有 Storage Queue Data Contributor。

两个阶段都已 apply(2026-09-28),队列角色后来从 Message Processor 改成了 Contributor(`docs/pitfalls.md`)。
