# medical-rag-v2

医学文献 RAG，基于 Azure ADLS Gen2 和 Snowflake。本阶段先跑通上传、解析、切分、检索和带引用的回答。

## 当前进度

Azure 事件链路和 Snowflake 基础对象已建好；10 个 PDF 已捕获，1 份已成功解析出 12 页；真实 etag 的解析和重复跳过验收通过，结果见 `.harness/context/current-state.md`。切分和 task 尚未填写，Cortex Search 和回答生成尚未实现。

## 入口

- `docs/architecture.md`：整体流程和核心约定。
- `.harness/context/current-state.md`：当前状态和下一步。
- `docs/hands-on.md`：用户动手的位置和验收方式。
- `AGENTS.md`：协作规则。
- `docs/pitfalls.md`：实际遇到的坑；`docs/decisions.md`：设计取舍。

## 部署

`infra/azure/` 管理 Azure 资源；`setup/` 是一次性引导。日常只部署根目录 `deploy.sql`，按顺序执行 `ingest/10`–`80`，记录提交 sha。实验 SQL 保留为注释，不随部署执行；task 写完再加入部署。

用户提交并推送后，在 Snowflake 执行：

```sql
USE ROLE MEDRAG_ADMIN;
ALTER GIT REPOSITORY MEDRAG.OPS.REPO FETCH;
EXECUTE IMMEDIATE FROM @MEDRAG.OPS.REPO/branches/main/deploy.sql
  USING (stage_base_url => '<stage_base_url>');
```

`stage_base_url` 来自 `terraform -chdir=infra/azure output -raw stage_base_url`，只在执行时填入。

提交前检查见 `.harness/checklists/verification.md`。后续目标见 `docs/roadmap.md`。
