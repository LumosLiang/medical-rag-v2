# medical-rag-v2

医学文献 RAG,建在 Snowflake 上。Azure 上新增、覆盖、删除 PDF 后,Snowflake 自动完成解析、切分和上下线;Cortex Search 检索;AI_COMPLETE 生成带引用的回答;FastAPI 和 Streamlit 部署到 SPCS。

架构见 `docs/architecture.md`,取舍和出处见 `docs/decisions.md`,踩过和已知的坑见 `docs/pitfalls.md`。在本仓库里改东西之前先读 `AGENTS.md`。

## 现状

骨架阶段:仓库结构、文档、检查规则已就位;Azure 第一阶段资源(存储账户、容器、队列、Event Grid system topic)已建好;Snowflake 的存储集成和通知集成已建好,Azure 那边的权限还没给。逐项状态见 `.harness/context/current-state.md`。

## 目录

| 目录 | 内容 |
|---|---|
| `infra/azure/` | Azure 资源的 Terraform:存储账户(ADLS Gen2)、容器、事件队列、Event Grid、给 Snowflake 的角色分配 |
| `sql/` | Snowflake 对象,按编号顺序执行(计划) |
| `eval/` | 标注集和评测过程(计划) |
| `app/` | 检索和生成模块、FastAPI、Streamlit、测试、镜像、SPCS 规格(计划) |
| `scripts/` | 提交前检查;一次性语料脚本(计划) |
| `docs/` | 架构、决定、坑 |
| `.harness/` | 给 agent 和人看的现状、规则、检查清单 |

## 检查

| 层 | 什么时候跑 | 入口 | 现状 |
|---|---|---|---|
| 代码检查 | 每次提交 | 本机提交前跑 `bash scripts/check_forbidden.sh` 和 `terraform fmt`、`validate`;推送后 GitHub Actions 再跑一遍 | 已就位;Python 测试等 `app/` 有代码后加 |
| 数据检查 | 每次入库后 | `CALL MEDRAG.OPS.RUN_DATA_CHECKS()` | 计划 |
| 评测 | 改动解析、切分、检索配置时 | `CALL MEDRAG.EVAL.RUN_EVAL('<配置名>')` | 计划 |

## 部署顺序(计划)

1. Azure 第一阶段:`infra/azure` apply 资源组、存储账户、容器、队列、Event Grid system topic。
2. Snowflake:建存储集成和通知集成;在 Azure 租户里对两者各做一次 consent。
3. Azure 第二阶段:填入两个 service principal 的对象 ID,再 apply 角色分配和事件订阅。
4. Snowflake:建 Git 仓库对象,之后的 SQL 都从仓库执行。
5. 先验证三项(见 `docs/decisions.md`),再写入库过程。
