# AGENTS.md

医学文献 RAG v2，基于 Azure ADLS Gen2 和 Snowflake。第一版 MEDICAL_RAG 只读保留，两版语料不同，指标不混比。

## 先读

- `docs/architecture.md`：设计，以它为准；冲突先说明，不擅自改方向。
- `.harness/context/current-state.md`：已实现、已验证和下一步。
- 改入库读 `.harness/rules/pipeline-rules.md`；用户动手的位置看 `.harness/context/implementation.md`。
- 交付前看 `.harness/checklists/verification.md`；设计难点看 `docs/challenges.md`。

## 当前范围

事件入库、检索评测、前后端与 SPCS 已实现，状态以 current-state 为准。当前对固定语料继续研究检索质量；日常入库仍使用 recursive 基线，应用选择 Markdown multi-index，两者尚未统一，不自动切换配置。项目文档采用正式、连贯的叙述；代码注释保留易懂的语法和流程解释，优先可读性，不提前设计未实现的模块。

新步骤按用户指定范围推进。用户选择亲自实现的部分只搭骨架，明确要求代改时再实现；已完成代码不保留学习占位。一次推进一步并汇报，不主动实现下一项优化。

## 执行边界

- 本机写代码和做轻量检查；重计算放 Snowflake 或外部机器。只用 Snowflake 这一套，不引入编排框架。
- Azure `terraform apply`、权限和安全对象变更、删除或替换已有数据对象前先问。更新同签名的过程、函数是正常部署；改过程签名需要 DROP 时先问。
- 解析、搜索服务、RESUME task、SPCS 不因费用要求确认。浏览器 consent、token、secret 等用户操作，说明后等待。
- 不改 v1，不 commit、不 push，提交推送由用户做。
- MEDRAG 对象归 MEDRAG_ADMIN，SQL 先 USE ROLE；账户级对象用 ACCOUNTADMIN，再授权。
- 账号、连接名、租户和订阅 ID、存储账户名、密钥、本机路径不进仓库。放忽略的本地文件，执行时传入。
- 用户的实验语句保留并注释，不混入部署执行；用户 SQL 不擅自重写。

## 对齐和回复

改完对齐调用方、部署入口和相关文档；状态只写已经发生的事，代码检查和运行验收分开。设计改变同步 architecture 和相关规则。Snowflake、Azure 行为以官方文档或实测为准，没验证就说明。

中文默认最短充分回答：先结论，再下一步，一般三到五句；不主动罗列背景和风险。汇报一句改了什么、一句检查结果，再给必要的命令。只有用户要求详细分析时展开。
