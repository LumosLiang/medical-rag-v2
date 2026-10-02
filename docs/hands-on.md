# 用户动手

核心步骤由 agent 搭骨架，用户填写；用户明确要求代改时按请求做。已经实现不代表已经运行验证，实际状态见 `.harness/context/current-state.md`。

| 环节 | 位置 | 当前 |
|---|---|---|
| 2A 捕获变更 | ingest/30 的 CAPTURE_CHANGES | 已填写，用户已验证 |
| 3A 解析 | ingest/60 的 PARSE_FILE | 验收通过：12 页，重复调用 SKIPPED |
| 5A 切分 | ingest/chunk/ 的 CHUNK_DOC 与算法 | 旧版已部署；新版基线与改进策略待部署验收 |
| 6A task | ingest/90 | 已部署且暂停，待验证自动触发 |
| 7A 检索 | search/10 的 MEDICAL_CHUNKS_RECURSIVE_ONCE_1200_200 | 本地已准备，待部署和查询验收 |

配置、判断变更、删旧块、RUN_INGEST 是 agent 提供的最简衔接，不需要现在重写。实验语句可放在文件开头或末尾，但保持注释，单独选中执行。

## 当前验收

- 捕获：调用一次把 stream 写进 FILE_CHANGES；再调用无新事件时返回 0。
- 解析：使用 directory table 的原始 etag（含双引号），真实 PDF 有一条成功记录，page_count 与返回 pages 数及原 PDF 一致；再次调用返回 SKIPPED。
- 切分：基线每页只 recursive 切一次，带 overlap，token_count 仅观察；空块、重复 ID 应为 0。改进版才反复补切到不超过 512 token。单文件检查用 `tests/chunk_one_file.sql` 看每块全文；两种新逻辑均待部署验收。
- task：已核对暂停状态；新版切分部署并验收后 RESUME，再依次上传、覆盖、删除，验证自动处理。

部署后用 `tests/backfill_baseline.sql` 补齐已完成文件的基线块，再用 `tests/cortex_search_one_query.sql` 验收检索；带引用的回答、评测与应用暂不搭骨架。

## 官方参考

- [AI_PARSE_DOCUMENT](https://docs.snowflake.com/en/sql-reference/functions/ai_parse_document)
- [Recursive 切分](https://docs.snowflake.com/en/sql-reference/functions/split_text_recursive_character-snowflake-cortex)
- [Triggered tasks](https://docs.snowflake.com/en/user-guide/tasks-triggered)
