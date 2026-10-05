# 核心决定

- 事件走 Event Grid → Storage Queue → directory table → stream → task，以 SQL 处理新增、覆盖和删除。[官方自动刷新](https://docs.snowflake.com/en/user-guide/data-load-dirtables-auto-azure)、[Triggered tasks](https://docs.snowflake.com/en/user-guide/tasks-triggered)。
- Azure 用 Terraform，SQL 从 Snowflake Git 仓库部署并记 sha。账号参数只在执行时传入。MEDRAG 对象归 MEDRAG_ADMIN，v1 只读保留。
- FILE_CHANGES 每条变更一行，不增加另一张文件状态表。各步骤分开提交、便于理解；先删旧块再写新块。失败后可能暂时搜不到文档，重试和复杂版本顺序稍后做。
- 解析输出先保存，改切分不重新解析。当前基线 `recursive_once_1200_200` 每页只切一次，带 overlap、默认分隔符；超 512 token 仅记录。`recursive_resplit_to_512_tokens_1200_200` 是反复补切的改进版；已部署的旧配置 `recursive_1200_200` 保留历史数据。前缀和参考文献过滤关闭。
- 已部署配置名对应固定参数；换参数新建配置名。评测题只关联原始 PDF(doc_id、页码、证据原文、文件哈希),不绑定 chunk、解析结果或检索配置,见 `.harness/rules/eval-rules.md`。
- 各切分策略共用 CORE.CHUNKS，以 config_name 区分；每个策略有独立 Cortex Search 服务，服务名后缀与配置名一致。当前只部署基线服务。评测时按配置筛选相同文件版本，不另建块表。

## 已验证与待验证

2026-09-28 实验确认：Azure 上传、覆盖、删除能自动刷新 directory table 和 stream；只 SELECT 不消费 stream。stream 记录两次消费之间的净变化：已消费文件覆盖是一删一增；同一区间新增再覆盖只剩最新新增；新增再删除没有行。

上传、覆盖、删除都已通过 task 自动触发验收(2026-10-03):覆盖后旧块删除、只剩新版本块,检索返回新内容;删除后块为 0,检索结果消失。块表约 2 分钟内更新;检索服务按 target_lag(当前 1 小时)刷新,手动 REFRESH 立即生效。最新运行记录见 `.harness/context/current-state.md`。


## Markdown 表格实验（2026-10-04）

- 按职责拆分辅助函数，算法入口继续复用 CHUNK_DOC 的十参数接口、配置分派和事务；不增加入口分支。
- 表格目标 450 token 暂作为算法常量，不借用字符长度配置列；正文大小、overlap、计数模型和硬上限从配置传入。
- 新策略用于 `corpus_2026_10_03` 固定快照；未来配置保持 inactive，不参与日常 ingest。当前尚未新增这条配置。
- 用户确认接受第一道门槛的 5/8 及其限制后继续；少数超长表格块允许 recursive 补切兜底，此时不保证每块重复完整表头，原文不丢弃。详见实验记录。
