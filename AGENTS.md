# AGENTS.md

这份文件给在本仓库里干活的 agent 和人看。它保持简短,是每次都要读的入口;具体的规则和现状放在 `.harness/`,按任务只读需要的那一份。

## 项目是什么

医学文献 RAG 的第二版,建在 Snowflake 上:Azure 上的 PDF 一有新增、覆盖或删除,Snowflake 自动完成解析、切分和上下线;Cortex Search 检索;AI_COMPLETE 生成带引用的回答;FastAPI 和 Streamlit 部署在 SPCS。入库、切分、索引、评测用 SQL,Python 只用于 FastAPI、Streamlit 和一次性的语料脚本。

第一版(库 MEDICAL_RAG)只读保留,作参考。两版语料不同,指标不能放在一起比。

## 以什么为准

有冲突时按这个顺序:

1. `docs/architecture.md`
2. 本文件
3. `.harness/` 里对应的文件
4. 现有代码和配置的写法

和 `docs/architecture.md` 冲突的改动,先停下来说明冲突,不要自己决定。

## 按任务读哪份

- 改入库、解析、切分、索引:`.harness/rules/pipeline-rules.md`
- 改检索配置、标注或评测:`.harness/rules/eval-rules.md`
- 动手前看现在做到哪、哪些只是计划、哪些模块由用户写:`.harness/context/current-state.md`
- 找文件、Snowflake 对象、Azure 资源:`.harness/context/project-map.md`
- 说"做完了"之前:`.harness/checklists/verification.md`
- 查坑:`docs/pitfalls.md`;查为什么这样定:`docs/decisions.md`

## 常驻规则

- 本机只写代码,不跑重的东西。要执行的工作放在 Snowflake 里,或由用户在外部机器上执行。az、snow、gh、terraform 这类只调接口的命令可以在本机用。
- 关键步骤先停下来问,用户批准后再做:
  - 花钱的操作:terraform apply、建 Cortex Search 服务、跑 AI_PARSE_DOCUMENT、建 compute pool 和 SPCS 服务;先说清要花多少。
  - 权限和安全对象:集成、角色分配、secret、GitHub 仓库设置。
  - 删除,或对已有对象 CREATE OR REPLACE。
- 需要用户介入的(在浏览器里 consent、建访问令牌、在 Snowflake 里存 secret),停下来说清楚要做什么,做完再继续。
- 仓库和文档里不出现账户标识、连接名、租户和订阅 ID、存储账户名、密钥、本机路径。这些值放在不进仓库的本地文件里,执行时传入。提交前跑 `scripts/check_forbidden.sh`。
- 用户自己写的模块(见 `current-state.md`)只搭接口、写清要求和验收方法,不替他写。
- 只做 Snowflake 这一套。不引入 LangChain 等编排框架,除非某一步确实更省事且说得清用途。
- 涉及 Snowflake、Azure 的行为和限制,以官方文档或实测为准,写明出处;没验证的标"待验证"。

## 改动的规矩

- 一次推进一步;每步说清改了什么、检查结果、下一步。
- 改完检查调用方、配置示例、启动命令、文档和本文件要不要同步。
- 文档写现状,不把计划写成现状;做完的 TODO 删掉或更新。
- 用户同意的设计改动,同步改 `docs/architecture.md`、本文件和 `.harness/` 里相关的文件。
