# 核心决定

- 事件走 Event Grid → Storage Queue → directory table → stream → task，以 SQL 处理新增、覆盖和删除。[官方自动刷新](https://docs.snowflake.com/en/user-guide/data-load-dirtables-auto-azure)、[Triggered tasks](https://docs.snowflake.com/en/user-guide/tasks-triggered)。
- Azure 用 Terraform，SQL 从 Snowflake Git 仓库部署并记 sha。账号参数只在执行时传入。MEDRAG 对象归 MEDRAG_ADMIN，v1 只读保留。
- FILE_CHANGES 每条变更一行，不增加另一张文件状态表。各步骤分开提交、便于理解；先删旧块再写新块。失败后可能暂时搜不到文档，重试和复杂版本顺序稍后做。
- 解析输出先保存，改切分不重新解析。当前基线 `recursive_once_1200_200` 每页只切一次，带 overlap、默认分隔符；超 512 token 仅记录。`recursive_resplit_to_512_tokens_1200_200` 是反复补切的改进版；已部署的旧配置 `recursive_1200_200` 保留历史数据。前缀和参考文献过滤关闭。
- 已部署配置名对应固定参数；换参数新建配置名。后续评测标注 evidence 原文，避免绑定 chunk_id。
- 各切分策略共用 CORE.CHUNKS，以 config_name 区分；每个策略有独立 Cortex Search 服务，服务名后缀与配置名一致。当前只部署基线服务。评测时按配置筛选相同文件版本，不另建块表。
- 当前先跑通核心链路，用户写捕获、解析、切分、task；其余衔接用最简版。

## 已验证与待验证

2026-09-28 实验确认：Azure 上传、覆盖、删除能自动刷新 directory table 和 stream；只 SELECT 不消费 stream。stream 记录两次消费之间的净变化：已消费文件覆盖是一删一增；同一区间新增再覆盖只剩最新新增；新增再删除没有行。

task 自动触发仍待验证；解析的当前验收见 `.harness/context/current-state.md`。不开 directory table 是否也能解析、批量解析耗时不影响当前链路，暂不扩展实验。
