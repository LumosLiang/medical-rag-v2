# 检索与回答服务

Cortex Search 从 CHUNKS 构建索引，FastAPI 负责接收问题、检索和回答，Streamlit 展示问题、答案与引用。应用包名为 medical_rag。后端 /search、/ask、检索和生成已实现并通过本地测试与真实 Snowflake 调用；云端容器 OAuth 身份下的检索与回答已验收。

服务定义位于 `cortex_search/`，Python 应用位于 `medical_rag/`。

## 四个搜索服务的区别

所有服务都用 snowflake-arctic-embed-l-v2.0、chunk_id 主键及 1 小时 TARGET_LAG；同批章节表格块上的三个服务只改变检索输入，不改变原始块。

| SQL | 切分配置 | 关键词输入 | 向量输入 |
|---|---|---|---|
| `10_recursive_baseline.sql` | recursive_once_1200_200 | chunk_text | chunk_text |
| `20_section_body.sql` | markdown_header_table_1200_200 | chunk_text | chunk_text |
| `30_heading_prefix.sql` | 同上 | 最近标题 + 正文 | 最近标题 + 正文 |
| `40_section_multi_index.sql` | 同上 | chunk_text、完整 section_path 两个索引 | 仅 chunk_text |

单 ON 字段的服务也是混合检索，包含关键词、向量及原生重排。ATTRIBUTES 是筛选字段，不会仅因列在 SELECT 中就参与关键词搜索。前缀服务在源查询构造 search_text，原始 chunk_text 保留用于展示和评分；代价是标题占用 embedding 窗口。Multi-index 让章节单独提供关键词信号，不为章节增加向量。

实际服务名保留现有标识，写在各 SQL 中。应用默认选择当前历史实验表现最好的 multi-index 服务，并发送下方最佳请求权重；日常入库使用 recursive 基线，因此新增文档不会自动进入应用当前选择的 Markdown 索引。两者暂不切换；应用配置改变也不触发历史文档重切。

## 服务定义与查询调参是两层配置

SQL 定义索引字段、源配置、模型与刷新目标。此前调参改变的是请求中的 scoring_config，没有修改这些服务定义，也没有重新 embedding。默认请求不传权重时仍使用原生默认配置。

目前探索结果最好的请求是：

```json
{
  "weights": {"texts": 1, "vectors": 1, "reranker": 3},
  "functions": {
    "text_boosts": [
      {"column": "chunk_text", "weight": 1},
      {"column": "section_path", "weight": 3}
    ]
  }
}
```

这是相对权重，不是百分比；整体关键词权重与其内部字段权重属于两层。该请求已成为应用配置默认，检索时已传给 service.search；实际实验参数保存在 EXPERIMENTS.params。默认和调参结果见 [实验记录](../../docs/experiments/README.md)。

[官方查询与评分参数](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-customize-scoring)。

## 后端职责

- `models.py`：定义请求、响应与来源的数据模型。
- `connection.py`：建立和关闭 Snowflake 连接，处理本地/SPCS 凭据。
- `services/retrieval.py`：调用 Cortex Search，返回带文件、页码和原文的 Source。
- `services/generation.py`：调用 AI_COMPLETE，读取结构化回答。
- `api.py`：HTTP 请求和响应；`/search` 只检索，`/ask` 直接串起检索、证据提示词、生成与引用校验，不增加独立业务层；检索和生成对象通过 FastAPI Depends 注入。

引用的文件、物理页码和原文来自检索结果，模型只引用来源编号。回答流程要求仅依据证据、证据不足时拒答，并拒绝不存在的编号或没有引用的正常回答。这些检查不能证明每项结论受证据支持；当前尚无自动语义核验，也未实现可点击的 PDF 链接。后续计划让模型逐条输出结论与 source_ids，再由前端渲染引用；具体边界见 [工程难点](../../docs/challenges.md#带引用的回答与校验边界)。

默认生成模型为 `claude-opus-5`，属于 Snowflake 当前支持的新一代模型，不宣称它是所有厂商中最新或本项目效果最佳的模型；本账户与云端 OAuth 身份下已成功调用；生成质量尚未做正式评测。[官方模型与函数说明](https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql-regional-availability)。配置可通过 RAG_MODEL、RAG_SEARCH_SERVICE、RAG_CONFIG_NAME 与 RAG_SCORING_CONFIG 覆盖；更换服务时同时核对来源配置与字段权重。

## 前端会话

`frontend/context_management.py` 管理当前 session_state：最多保存 20 轮问答及其来源，app.py 按轮展示并提供清空按钮。`get_recent_messages()` 取最近 5 轮的问答文本，预留给后续问题改写；当前请求仍只传本次问题，尚不能解析跨轮指代。仅检索的结果不进入问答历史。没有永久存储、摘要压缩或 token 预算控制。
