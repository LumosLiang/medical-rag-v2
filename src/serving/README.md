# 检索与回答服务

Cortex Search 从 CHUNKS 构建索引，FastAPI 负责接收问题、检索和回答，Streamlit 展示问题、答案与引用。应用包名为 medical_rag。当前 /search、/ask 和前端请求/会话管理仍留待用户实现。

## 四个搜索服务的区别

所有服务都用 snowflake-arctic-embed-l-v2.0、chunk_id 主键及 1 小时 TARGET_LAG；同批章节表格块上的三个服务只改变检索输入，不改变原始块。

| SQL | 切分配置 | 关键词输入 | 向量输入 |
|---|---|---|---|
| `10_recursive_baseline.sql` | recursive_once_1200_200 | chunk_text | chunk_text |
| `20_section_body.sql` | markdown_header_table_1200_200 | chunk_text | chunk_text |
| `30_heading_prefix.sql` | 同上 | 最近标题 + 正文 | 最近标题 + 正文 |
| `40_section_multi_index.sql` | 同上 | chunk_text、完整 section_path 两个索引 | 仅 chunk_text |

单 ON 字段的服务也是混合检索，包含关键词、向量及原生重排。ATTRIBUTES 是筛选字段，不会仅因列在 SELECT 中就参与关键词搜索。前缀服务在源查询构造 search_text，原始 chunk_text 保留用于展示和评分；代价是标题占用 embedding 窗口。Multi-index 让章节单独提供关键词信号，不为章节增加向量。

实际服务名保留现有标识，写在各 SQL 中。日常应用默认仍选基线，实验服务不自动成为线上默认。

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

这是相对权重，不是百分比；整体关键词权重与其内部字段权重属于两层。该请求尚未成为应用默认，实际实验参数保存在 EXPERIMENTS.params。默认和调参结果见 [实验记录](../../docs/experiments/README.md)。

[官方查询与评分参数](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-customize-scoring)。
