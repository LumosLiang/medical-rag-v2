# 现状

2026-09-28 更新。以实际代码和实测为准;写"计划"的都还没做。

| 组件 | 状态 | 说明 |
|---|---|---|
| 仓库结构、文档、检查规则 | 已实现 | |
| 提交前检查 | 已实现 | 禁止内容扫描、Terraform 格式和校验;本机提交前跑一次,推送后 GitHub Actions 再跑一次 |
| Azure 的 Terraform 代码 | 已实现 | 第一阶段已 apply;第二阶段(角色分配、事件订阅)的代码未经 apply 验证 |
| Azure 资源(第一阶段) | 已验证 | 2026-09-28 建成:资源组、存储账户(ADLS Gen2)、容器、队列、system topic。已核对实际设置;apply 后 plan 无差异 |
| Azure 资源(第二阶段) | 计划 | 等两个集成 consent、service principal 出现 |
| Snowflake 存储集成、通知集成 | 已实现待验证 | `sql/01_integrations.sql` 已写,等用户批准执行 |
| Git 仓库对象和部署入口 | 计划 | |
| stage、stream、task | 计划 | |
| FILE_STATE、PARSED_DOCS、CHUNKS | 计划 | |
| 切分过程 `sql/20_chunk.sql` | 计划 | 由用户写 |
| 入库过程 `sql/30_ingest.sql` | 计划 | 其中按 (路径, etag) 判断新增、覆盖、删除并替换块的一段由用户写 |
| Cortex Search 服务 | 计划 | |
| 数据检查 `RUN_DATA_CHECKS` | 计划 | |
| 评测 `RUN_EVAL` | 计划 | evidence 匹配函数 `eval/10_match.sql` 由用户写 |
| 标注集 | 计划 | 先 30 题,再扩到 60 题以上 |
| 检索、生成模块,FastAPI、Streamlit | 计划 | |
| SPCS 部署 | 计划 | |
| 语料脚本 | 计划 | |

## 先验证

三项都待验证,方法和判断标准见 `docs/decisions.md`。第 1、2 项要等 Azure 资源和两个集成就绪。

## 未决

- 失败文件怎么重试:Task 的 WHEN 不能查表,失败文件不会自动重试。写入库过程时定,可以加一个低频定时的重试 task,也可以手动调用。
- 代码检查什么时候从"本机加推送后 CI"改成"PR 上 CI 通过才合并":`app/` 有代码后再定。
- 本机的 snow CLI 还不能用:连接配置里 account 是大写,connector 判断"Snowflake 是不是 OAuth 服务方"时主机名大小写对不上,不走内置的 LOCAL_APPLICATION,报 client_id 为空(从 connector 代码推断,待验证)。
