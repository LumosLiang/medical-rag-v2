# 用户动手

核心步骤由 agent 搭骨架，用户填写；用户明确要求代改时按请求做。已经实现不代表已经运行验证，实际状态见 `.harness/context/current-state.md`。

| 环节 | 位置 | 当前 |
|---|---|---|
| 2A 捕获变更 | ingest/30 的 CAPTURE_CHANGES | 已填写，用户已验证 |
| 3A 解析 | ingest/60 的 PARSE_FILE | 验收通过：12 页，重复调用 SKIPPED |
| 5A 切分 | ingest/70 的 CHUNK_DOC | 用户要求代改后本地已实现，待部署验收 |
| 6A task | ingest/90 | 已填写并加入部署，待运行验收 |

配置、判断变更、删旧块、RUN_INGEST 是 agent 提供的最简衔接，不需要现在重写。实验语句可放在文件开头或末尾，但保持注释，单独选中执行。

## 当前验收

- 捕获：调用一次把 stream 写进 FILE_CHANGES；再调用无新事件时返回 0。
- 解析：使用 directory table 的原始 etag（含双引号），真实 PDF 有一条成功记录，page_count 与返回 pages 数及原 PDF 一致；再次调用返回 SKIPPED。
- 切分：从成功解析记录的 `parse_result:value:pages` 取内容，按 recursive_1200_200 的 recursive 参数切分（默认 separators）、数 token、继续切超限块；空块、重复 ID、超过 512 token 的块均为 0，重跑 ID 不变。当前按页切，保留 0 起始页码。单文件检查用 `tests/chunk_one_file.sql`，可直接看每块全文。
- task：部署后先核对 task 定义和暂停状态；切分验收通过后 RESUME，再依次上传、覆盖、删除，验证自动处理，不手动刷新或 EXECUTE TASK。

后续再一起实现 Cortex Search 和带引用的回答，评测与应用暂不搭骨架。

## 官方参考

- [AI_PARSE_DOCUMENT](https://docs.snowflake.com/en/sql-reference/functions/ai_parse_document)
- [Recursive 切分](https://docs.snowflake.com/en/sql-reference/functions/split_text_recursive_character-snowflake-cortex)
- [Triggered tasks](https://docs.snowflake.com/en/user-guide/tasks-triggered)
