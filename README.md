# Medical RAG v2

基于 Azure ADLS Gen2 与 Snowflake 的事件驱动医学文献检索与问答应用。PDF 保存在对象存储，文件变化驱动增量解析和切分；Cortex Search 提供混合检索，FastAPI 组织带来源引用的回答，Streamlit 提供交互界面。应用部署在 Snowpark Container Services（SPCS）。

```text
ADLS Gen2 → Event Grid → Storage Queue → directory table → Stream → Task
          → AI_PARSE_DOCUMENT → CHUNKS → Cortex Search → FastAPI → Streamlit
```

## 实现与验证

文件新增、覆盖和删除的自动入库已验证；固定语料包含 209 篇医学论文，评测题集 `qset_v1` 包含 50 题。应用已部署至 SPCS，云端服务身份下的检索与带引用回答通过 HTTP 验收。

日常入库使用 recursive 基线，应用使用固定语料上的结构化 Markdown multi-index 服务。两者目前独立，新增文件不会自动进入应用所选索引。当前工作集中在固定语料的检索实验，暂不切换入库配置。

历史探索的最佳证据 Hit@5 为 0.82、MRR 为 0.593；重复运行存在排名波动。下一阶段目标是将两项指标提高到 0.90，并通过独立问题验证。结果与限制见 [实验记录](docs/experiments/README.md)。第一版 MEDICAL_RAG 保持只读，两版指标独立。

## 目录

| 位置 | 职责 |
|---|---|
| `src/ingestion/` | 文件变更、解析、切分与入库调度 |
| `src/serving/` | Cortex Search 定义、FastAPI 与 Streamlit |
| `eval/` | 独立的题集构建、检索实验与评分 |
| `infra/` | Azure Terraform 与 Snowflake 初始化 |
| `deploy/` | Docker 镜像与 SPCS 发布 |
| `tests/` | 本地回归与 Snowflake 验收 |
| `docs/` | 架构、工程难点、部署与实验报告 |

`deploy.sql` 是入库和检索对象的 Git 部署入口，评测工具使用独立的 `eval/deploy.sql`。本机数据、操作记录和凭据不纳入版本管理；`.harness/` 保存协作规则与当前进度。

## 文档

- [架构与设计取舍](docs/architecture.md)
- [工程难点与解决路径](docs/challenges.md)
- [结构化 Markdown 切分](src/ingestion/sql/chunk/structured_markdown/README.md)、[检索与回答](src/serving/README.md)
- [评测](eval/README.md)、[实验报告](docs/experiments/README.md)、[测试](tests/README.md)
- [初始化](infra/snowflake/setup/README.md)、[部署](docs/deployment.md)
