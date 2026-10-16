# 检索与回答服务

Cortex Search 构建检索索引，FastAPI 串起检索和生成，Streamlit 展示答案及引用。实现位于 [src/serving/](../src/serving/)，搜索定义在 cortex_search/，应用在 medical_rag/；发布步骤见 [部署](deployment.md)，运行验收见 [current-state](../.harness/context/current-state.md)。

## 搜索服务

原有四个服务使用 snowflake-arctic-embed-l-v2.0；两个 8K 服务使用 snowflake-arctic-embed-l-v2.0-8k。所有服务使用 chunk_id 主键及 1 小时 TARGET_LAG。

| SQL | 切分配置 | 关键词输入 | 向量输入 |
|---|---|---|---|
| `recursive.sql` | recursive_once_1200_200 | chunk_text | chunk_text |
| `structured_markdown/body.sql` | markdown_header_table_1200_200 | chunk_text | chunk_text |
| `structured_markdown/heading_prefix.sql` | 同上 | 最近标题 + 正文 | 最近标题 + 正文 |
| `structured_markdown/multi_index.sql` | 同上 | chunk_text、完整 section_path 两个索引 | 仅 chunk_text |
| `structured_markdown/arctic_8k_control.sql` | markdown_header_table_1200_200 | chunk_text、完整 section_path | chunk_text，8K 模型 |
| `structured_markdown/arctic_8k_large.sql` | structured_markdown_8k_body_1024 | chunk_text、完整 section_path | chunk_text，8K 模型 |

单 ON 字段的服务也是混合检索，包含关键词、向量及原生重排。ATTRIBUTES 是筛选字段，不会仅因列在 SELECT 中就参与关键词搜索。前缀服务在源查询构造 search_text，原始 chunk_text 保留用于展示和评分；代价是标题占用 embedding 窗口。Multi-index 让章节单独提供关键词信号，不为章节增加向量。

8K CONTROL 只换模型；BODY_1024 同时扩大正文、保留完整摘要/表格并清理明确噪声。请求沿用已选定的权重；2026-10-16 应用显式切换到 BODY_1024 服务，CONTROL 保留为模型对照。切分定义见 [长窗口配置](chunking.md)。

实际服务名写在各 SQL 中。应用与日常入库统一采用 structured_markdown_8k_body_1024，搜索服务为 MEDICAL_CHUNKS_STRUCTURED_MARKDOWN_8K_BODY_1024。新增文件处理后进入同一索引，TARGET_LAG 为一小时。旧服务保留为对照；日后调整应用或 active 时，仍需同时核对两端选择。

## 服务定义与查询调参是两层配置

SQL 定义索引字段、源配置、模型与刷新目标。此前调参改变的是请求中的 scoring_config，没有修改这些服务定义，也没有重新 embedding。默认请求不传权重时仍使用原生默认配置。

旧 512 方案调参选定、8K 对照实验继续沿用的请求是：

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

这是相对权重，不是百分比；整体关键词权重与其内部字段权重属于两层。该请求已成为应用配置默认，检索时已传给 service.search；实际实验参数保存在 EXPERIMENTS.params。默认和调参结果见 [实验记录](experiments/README.md)。

[官方查询与评分参数](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-customize-scoring)。

## 后端职责

- `models.py`：定义请求、响应与来源的数据模型。
- `connection.py`：建立和关闭 Snowflake 连接，处理本地/SPCS 凭据。
- `services/retrieval.py`：调用 Cortex Search，返回带文件、页码和原文的 Source。
- `services/generation.py`：调用 AI_COMPLETE，读取结构化回答。
- `api.py`：HTTP 路由，/ask 保留检索、提示、生成、校验与响应的完整调用顺序；检索和生成对象通过 FastAPI Depends 注入。
- `prompts.py`：回答约束及证据提示词构造。
- `citations.py`：逐结论引用校验、编号去重与答案文本拼接；全部校验通过后标记被引用来源。

回答按 `claims` 返回，每条结论包含 `citations`：来源编号 `source_id` 与必要的原文摘录 `quote`。后端逐条检查引用不为空、编号属于本次检索、摘录在对应片段中存在；仅合并空白差异，不删除标点或改变数字。通过后由后端生成 [1] 等标记及供展示、会话使用的 answer，前端在来源卡片中展示对应结论、引用原句与完整片段。文件、页码和 chunk_id 始终来自检索，不由模型生成。

`insufficient_evidence` 仍是模型判断，不允许绕过事实结论的校验。有支持的部分结论可保留，并追加固定的证据不足提示；完全没有支持的结论返回空 claims 与固定提示。非法引用或摘录返回 502，前端显示错误而不保存未经校验的答案；当前不自动重试。

摘录存在只证明文本来自检索片段，不证明其支持结论；解析本身也可能与 PDF 不一致。提示词要求保留研究条件、人群、不确定性与矛盾结果，不将相关性表述成因果或将单篇发现推广成治疗建议。引用页码是来源块的范围，不是摘录精确所在页。尚无独立语义核验或可点击 PDF 链接。工程取舍见 [工程难点](challenges.md#带引用的回答与校验边界)。

默认生成模型为 `claude-opus-5`，属于 Snowflake 当前支持的新一代模型，不宣称它是所有厂商中最新或本项目效果最佳的模型；本账户与云端 OAuth 身份下已成功调用；生成质量尚未做正式评测。[官方模型与函数说明](https://docs.snowflake.com/en/user-guide/snowflake-cortex/aisql-regional-availability)。配置可通过 RAG_MODEL、RAG_SEARCH_SERVICE、RAG_CONFIG_NAME 与 RAG_SCORING_CONFIG 覆盖；更换服务时同时核对来源配置与字段权重。

## 前端会话

`frontend/app.py` 负责页面交互和 HTTP 请求，`frontend/views.py` 渲染答案与来源卡片。`frontend/context_management.py` 管理当前 session_state：最多保存 20 轮问答及其来源，app.py 按轮展示并提供清空按钮。`get_recent_messages()` 取最近 5 轮的问答文本，预留给后续问题改写；当前请求仍只传本次问题，尚不能解析跨轮指代。仅检索的结果不进入问答历史。没有永久存储、摘要压缩或 token 预算控制。

会话记录保存与模型上下文选择分别处理。后续可以用最近几轮将追问改写成独立问题，再重新检索；历史帮助理解指代，不直接作为新的事实证据。对话增长后再考虑 token 预算与旧对话摘要；需要跨会话恢复时，数据库负责持久化，应用仍负责选择和组织上下文。这些属于后续设计，当前未实现。
