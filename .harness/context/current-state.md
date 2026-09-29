# 当前状态

2026-09-29。本阶段先跑通核心链路；代码实现和运行验证分开记录。

| 部分 | 状态 |
|---|---|
| Azure 存储、队列、Event Grid、角色分配 | 已建立；既有实测上传、覆盖、删除可自动刷新；本次只读核对存储和事件订阅设置符合配置 |
| Snowflake 角色、集成、库、schema、Git 仓库对象 | 已建立并验证 |
| deploy、配置、CORPUS_STAGE / STREAM、入库表与过程骨架 | 已从 Git 仓库部署，既有记录 sha 为 7d3cdd2；不代表后续本地修改已部署 |
| 捕获变更 CAPTURE_CHANGES | 已填写；本次核实 10 个 PDF 都已进入 FILE_CHANGES，状态 PENDING，含 LAST_MODIFIED 显式类型转换 |
| 判断变更、删旧块、RUN_INGEST | 最简版已实现；判断和空表删块有既有验证记录，整条链路尚未跑通 |
| 解析 PARSE_FILE | 已运行验收通过：用 directory table 原始 etag 首次返回 PARSED、再次 SKIPPED；当前版本成功记录 1 行、页数 12，与原 PDF 一致；远程解析过程与本地一致 |
| 切分 CHUNK_DOC | 骨架已部署，核心留空，调用会抛 NOT_IMPLEMENTED；当前 CHUNKS 为 0 行 |
| task | 留空，未加入 deploy；本次 SHOW TASKS 确认未建 |
| Cortex Search、回答生成 | 尚未实现；本次确认库内没有搜索服务 |
| 自动数据检查、评测、应用与 SPCS | 后续再做 |

本次已注释用户在 ingest/20、30、60 中添加的实验查询和 CALL，保留原部署步骤；文档和 harness 已精简。本地禁止内容扫描、diff 格式检查、受版本控制的 Terraform 格式检查和 validate 通过。没有 commit / push，没有变更 Azure 资源或 Snowflake 对象定义；验收新增一条真实 etag 的解析记录。

本次已成功连接 Snowflake 只读核对上述状态。CORPUS_STREAM 未过期，STALE_AFTER 为 2026-10-13（账户返回时间）；但 task 尚未建立。

2026-09-29 已完成真实 etag 的解析与重复调用验收：PARSED → SKIPPED，无错误，当前版本仅一条成功记录；只读核对 stream 为 0 行。旧手工测试记录保留，不删除，实际调用必须取 directory table 原值。

远程捕获过程与本地仅差一个已移除的未使用异常声明，核心 SQL 相同。本地文档和注释整理尚未提交部署；DEPLOY_LOG 最近成功记录仍为 7d3cdd2。

本地配置已新增 `recursive_1200_200` 为下次部署的 active 基线：recursive、none 格式、1200 字符 / 200 字符 overlap、默认分隔符；旧 base_1200 保留停用。仅更新配置和说明，尚未部署，远程 active 仍是 base_1200，切分核心仍留空。

## 下一步

明天填写 ingest/70 的 recursive 切分核心，使用新配置。按页切还是拼页后切，先讨论再写。暂不运行 RUN_INGEST 验收整条链路，因为切分仍留空。
