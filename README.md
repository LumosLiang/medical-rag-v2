# Medical RAG v2

基于 Azure ADLS Gen2 与 Snowflake 的事件驱动医学文献 RAG。文件新增、覆盖和删除触发增量处理；不同解析、切分与检索策略用固定 PDF 题集比较，应用目标是返回带原文引用的回答。

```text
PDF → Event Grid → Queue → directory table → Stream → Task
    → 解析与切分 → Cortex Search → FastAPI → Streamlit
```

## 项目结构

```text
src/ingestion/    文件变更、解析、切分与入库 task
src/serving/      搜索服务 SQL、FastAPI 与 Streamlit
eval/dataset/    PDF 快照、起草、审核与冻结题集
eval/retrieval/  检索实验、证据评分与指标
infra/           Azure Terraform 与 Snowflake 初始化
deploy/          Docker 与 SPCS 部署文件
scripts/         语料工具与手工操作 SQL
tests/           单元测试与手工验收
docs/            架构、部署、运行约束与实验结果
```

## 当前状态

事件入库、三种切分策略、四个搜索服务和固定题集检索实验已实现并有历史验收；日常入库与应用默认仍使用 recursive 基线。前后端有骨架，/search、/ask 与前端请求/会话管理尚未完成，SPCS 尚未部署。2026-10-06 的代码与文档重构包含 active 唯一性、表格章节归属和指标分母修复，云端尚未部署复验。

接下来先完成前端 → /search → Cortex Search，再接带引用的回答。实验参数需要独立新题验证，不能把当前 50 题上的调参结果当成泛化效果。第一版 MEDICAL_RAG 保留，两版语料和指标独立。

## 阅读入口

- [架构、职责与取舍](docs/architecture.md)
- [章节表格切分](src/ingestion/sql/chunk/structured_markdown/README.md)、[检索配置](src/serving/README.md)、[评测流程](eval/README.md)
- [部署与运行](docs/deployment.md)、[运行约束与排错](docs/pitfalls.md)
- [实验结果](docs/experiments/README.md)、[本机辅助工具](docs/deployment.md#本机辅助工具)

根目录 deploy.sql 部署 Snowflake 模块，compose.yaml 启动本机应用，依赖统一在 pyproject.toml。开发验收和协作规则在 `.harness/`，不作为应用运行依赖。
