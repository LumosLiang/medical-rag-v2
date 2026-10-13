# 核心实现位置

入库代码已完成。后端检索、生成和两个路由已实现；本地模拟验收通过，真实 Snowflake 与云端 OAuth 检索、回答已验收。

1. `services/retrieval.py`：检查问题、top_k、筛选与 SDK 结果如何映射到 Source。
2. `api.py`：/search 返回片段；/ask 保留检索、提示、生成与校验调用链。`prompts.py` 构造证据输入，`citations.py` 校验引用和生成展示标记。
3. `frontend/context_management.py`：已实现会话历史（20 轮）、最近文本窗口（5 轮）及清空；app.py 负责查询和保存，views.py 负责回答及来源展示。SPCS 已部署，下一步由用户试用公开界面。

当前不把历史对话传给模型。代码优先使用明确命名、中间变量和逐步循环，保留学习所需的语法解释。结构化逐结论引用与摘录校验已实现；语义支持关系仍需人工复核。

运行方式见 `docs/deployment.md`；实际验收见 `current-state.md`。切分与搜索验收位于 `tests/snowflake/`，检索实验入口为 `eval/retrieval/run_experiment.sql`。
