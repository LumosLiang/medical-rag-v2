# 当前状态

2026-10-02 更新。代码部署与运行验收分开记录。

| 部分 | 状态 |
|---|---|
| Azure ADLS Gen2 → Event Grid → Queue → directory table | 已建立；此前实测新增、覆盖、删除可自动刷新 |
| Snowflake 入库 SQL | Git 提交 `4b39ec3` 已部署，`OPS.DEPLOY_LOG` 为 `SUCCEEDED` |
| CAPTURE_CHANGES、CLASSIFY_CHANGES、REMOVE_OLD_CHUNKS、RUN_INGEST | 10 条既有 PENDING 已手工触发处理：9 条 DONE、1 条 FAILED；自动触发尚未验收 |
| PARSE_FILE | 已验收：真实 etag 的 PDF 解析出 12 页，重复调用返回 SKIPPED；失败文件也已成功解析 12 页 |
| CHUNK_DOC | 新版已部署。9 份已完成文档补齐 700 个基线块：ID 唯一，无空块、NULL token 或过期版本；17 块超过 512 token，符合基线设计。同一文件重复切分两次均为 69 块且 ID 稳定。补切配置在一份文档上生成 69 块，均不超过 512 token。`PMC9883575.pdf` 仍为 FAILED，未补入基线 |
| INGEST_TASK | 已部署，监听 CORPUS_STREAM；`SHOW TASKS` 显示 `suspended`，尚未验证自动触发 |
| Cortex Search | 基线服务 `MEDICAL_CHUNKS_RECURSIVE_ONCE_1200_200` 已部署并手动刷新，索引 700 行；查询返回文本、文件名和页码。补切配置的 69 块未进入该服务 |
| 回答生成 | 尚未实现 |
| 自动数据检查、评测、应用与 SPCS | 后续再做 |

`recursive_once_1200_200` 是 active 配置；补切策略名为 `recursive_resplit_to_512_tokens_1200_200`。旧名 `recursive_1200_200` 和历史块保留。切分代码位于 `ingest/chunk/`。本次没有更改 Azure 资源。CLI 当前使用受限 PAT 会话，验收时显式指定 `MEDRAG_ADMIN`，临时副本去掉 `USE ROLE`；仓库脚本保留标准角色声明。

## 下一步

下一步实现检索后的带引用回答。之前 FAILED 的文件仍需单独重试；task 自动触发仍待验收，当前保持暂停。
