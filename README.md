# Medical RAG v2

基于 Azure ADLS Gen2 与 Snowflake 的事件驱动医学文献 RAG。PDF 上传、覆盖和删除通过事件触发增量处理；Cortex Search 提供混合检索，应用返回带原文引用的回答。

## 架构

```text
ADLS Gen2 → Event Grid → Storage Queue → directory table
          → Stream → Task → 解析与切分 → Cortex Search
          → FastAPI → Streamlit
```

PDF 保留在 Azure，解析结果与不同策略的文本块存入 Snowflake。各切分配置对应独立搜索服务，便于后续比较检索效果。

## 项目结构

```text
src/medical_rag/   Python 应用：backend 与 frontend
src/sql/          入库过程、切分算法与搜索服务
infra/            Azure Terraform 与 Snowflake 初始化
deploy/          Docker 镜像与 SPCS 部署文件
config/           配置示例
tests/           Python 单元测试与手工 SQL 验收
scripts/         语料下载、检查与手工操作 SQL
docs/            架构、部署与设计记录
```

根目录 `deploy.sql` 是 Snowflake SQL 部署入口，`compose.yaml` 用于本机启动应用。Python 依赖统一定义在 `pyproject.toml`。

## 当前状态

Azure 事件链路、入库过程、三种切分策略及四个搜索服务已部署；日常入库和应用默认仍使用 recursive 基线。上传自动触发已验证，固定题集的检索评测已运行。前后端、模型调用及 Docker 基础代码已准备，应用检索接口和会话状态管理尚待实现；SPCS 尚未部署。

## 运行与文档

- [部署与本机运行](docs/deployment.md)
- [语料与操作工具](scripts/README.md)
- [架构与数据约定](docs/architecture.md)
- [设计决定](docs/decisions.md)、[排错记录](docs/pitfalls.md)、[后续计划](docs/roadmap.md)

详细验收记录和开发协作信息位于 `.harness/`，不作为应用运行依赖。第一版 MEDICAL_RAG 保留，两版语料和指标独立。
