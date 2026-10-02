# medical-rag-v2

医学文献 RAG，基于 Azure ADLS Gen2 和 Snowflake。本阶段先跑通上传、解析、切分、检索和带引用的回答。

## 当前进度

Azure 事件链路和旧版入库 SQL 已部署。10 份 PDF 已处理 9 份；1 份因块超过 512 token 失败。单次切分基线、递归补切改进版和 Cortex Search 定义已在本地准备，待部署验收。Task 已创建且暂停。实际状态见 `.harness/context/current-state.md`。

## 入口

- `docs/architecture.md`：整体流程和核心约定。
- `.harness/context/current-state.md`：当前状态和下一步。
- `docs/hands-on.md`：用户动手的位置和验收方式。
- `AGENTS.md`：协作规则。
- `docs/pitfalls.md`：实际遇到的坑；`docs/decisions.md`：设计取舍。
- `tests/chunk_one_file.sql`：单文件切分验收，运行后查看每块完整文本。
- `tests/backfill_baseline.sql`：部署后手工把已完成文件补成基线块。
- `tests/cortex_search_one_query.sql`：服务建好后的检索预览。

## 部署

`infra/azure/` 管理 Azure 资源；`setup/` 是一次性引导。日常只部署根目录 `deploy.sql`，按顺序执行 `ingest/`、`ingest/chunk/` 和 `search/` 的文件，记录提交 sha。实验 SQL 不随部署执行；Task 当前暂停，新版切分须先验收并重切基线语料，服务才会有正式检索内容。

用户提交并推送后，在 Snowflake 执行：

```sql
USE ROLE MEDRAG_ADMIN;
ALTER GIT REPOSITORY MEDRAG.OPS.REPO FETCH;
EXECUTE IMMEDIATE FROM @MEDRAG.OPS.REPO/branches/main/deploy.sql
  USING (stage_base_url => '<stage_base_url>');
```

`stage_base_url` 来自 `terraform -chdir=infra/azure output -raw stage_base_url`，只在执行时填入。

提交前检查见 `.harness/checklists/verification.md`。后续目标见 `docs/roadmap.md`。
