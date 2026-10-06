# 核心实现位置

入库代码已完成，教学占位已移除。应用中的 `你来写 / 到这里` 标记保留，按下列顺序推进：

1. `src/serving/medical_rag/backend/snowflake_access.py` 的 `search`：连接 Snowflake、调用 Cortex Search Python API、将结果转换为 `Source` 列表。
2. `src/serving/medical_rag/backend/api.py` 的 `/search`：接收请求、调用检索、返回 `SearchResponse`。
3. `src/serving/medical_rag/frontend/app.py` 的 `send_query`：通过 HTTP 请求后端；`save_result / load_result` 使用 `st.session_state` 保存和读取当前结果。
4. `api.py` 的 `/ask`：调用已有 `rag.py` 回答流程，返回回答与引用。

先完成检索，再启用生成回答。当前只保存本次结果，不把历史对话传给模型。代码注释保留学习所需的语法解释，未实现部分可启动，调用时提示未实现。

运行方式见 `docs/deployment.md`；实际验收见 `current-state.md`。切分和检索的手工 SQL 位于 `tests/sql/checks/`(验收)和 `scripts/sql/`(回填、跑实验)。
