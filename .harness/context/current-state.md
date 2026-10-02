# 当前状态

2026-10-02 更新。代码部署与运行验收分开记录。

| 部分 | 状态 |
|---|---|
| Azure ADLS Gen2 → Event Grid → Queue → directory table | 已建立；此前实测新增、覆盖、删除可自动刷新 |
| Snowflake 入库 SQL | Git 提交 `c7f3080` 已部署，`OPS.DEPLOY_LOG` 为 `SUCCEEDED` |
| CAPTURE_CHANGES、CLASSIFY_CHANGES、REMOVE_OLD_CHUNKS、RUN_INGEST | 10 条既有 PENDING 已手工触发处理：9 条 DONE、1 条 FAILED；自动触发尚未验收 |
| PARSE_FILE | 已验收：真实 etag 的 PDF 解析出 12 页，重复调用返回 SKIPPED；失败文件也已成功解析 12 页 |
| CHUNK_DOC | 已部署的旧版：9 份文档现有 718 块；`PMC9883575.pdf` 因超限状态 FAILED。新版使用会话临时过程和表在真实 PDF 上验证：基线 64 块、最大 652 token，补切版 70 块、最大 505 token；两者均无 NULL token 或重复 ID。新版尚未正式部署 |
| INGEST_TASK | 已部署，监听 CORPUS_STREAM；`SHOW TASKS` 显示 `suspended`，尚未验证自动触发 |
| Cortex Search | 基线服务 `MEDICAL_CHUNKS_RECURSIVE_ONCE_1200_200` 的 SQL 已在本地准备，源查询仅取对应配置；尚未部署或检索验收 |
| 回答生成 | 尚未实现 |
| 自动数据检查、评测、应用与 SPCS | 后续再做 |

本地部署 SQL 会把 `recursive_once_1200_200` 设为 active：只切一次，token_count 用于观察。补切策略用新名 `recursive_resplit_to_512_tokens_1200_200`；旧名 `recursive_1200_200` 和历史块保留。切分代码拆在 `ingest/chunk/`：入口统一负责事务，算法分别实现。2026-10-02 通过临时对象验证递归 CTE、动态分派和两种算法；验证对象随会话结束消失，正式 CHUNKS 未改。没有更改 Azure 资源。

## 下一步

用户提交推送后从 Snowflake Git 仓库部署，再手工运行 `tests/backfill_baseline.sql` 把已完成文件按基线重切，验收正式服务的索引与检索结果。切换 active 配置不会自动重切现有文档；之前 FAILED 的文件仍需单独重试，task 自动触发仍待验收。
