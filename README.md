# medical-rag-v2

医学文献 RAG,建在 Snowflake 上。Azure 上新增、覆盖、删除 PDF 后,Snowflake 自动完成解析、切分和上下线;Cortex Search 检索;AI_COMPLETE 生成带引用的回答;FastAPI 和 Streamlit 部署到 SPCS。

架构见 `docs/architecture.md`,取舍和出处见 `docs/decisions.md`,踩过和已知的坑见 `docs/pitfalls.md`,每个环节留给用户动手的部分见 `docs/hands-on.md`,跑通之后的目标见 `docs/roadmap.md`。在本仓库里改东西之前先读 `AGENTS.md`。

## 现状

骨架阶段:仓库结构、文档、检查规则已就位;Azure 两个阶段的资源都已建好(存储、队列、事件订阅、给 Snowflake 的权限);Snowflake 的两个集成、专用角色 MEDRAG_ADMIN、MEDRAG 库和四个 schema 已建好;Git 仓库对象已建好,SQL 可以从仓库执行。逐项状态见 `.harness/context/current-state.md`。

## 目录

| 目录 | 内容 |
|---|---|
| `infra/azure/` | Azure 资源的 Terraform:存储账户(ADLS Gen2)、容器、事件队列、Event Grid、给 Snowflake 的角色分配 |
| `setup/` | 一次性引导 SQL:专用角色、集成、schema、Git 仓库对象。新环境里按编号手动执行一次,不进部署 |
| `ingest/` | 入库的 SQL,一个文件一步,按数据流向编号;由根目录的部署入口 `deploy.sql` 执行 |
| `spike/` | 先验证的实验脚本。只在本机,不进仓库 |
| `eval/` | 标注集和评测过程(计划) |
| `app/` | 检索和生成模块、FastAPI、Streamlit、测试、镜像、SPCS 规格(计划) |
| `scripts/` | 提交前检查 `check_forbidden.sh`(进仓库,CI 要跑);其它辅助脚本只在本机 |
| `data/` | 本机下载的语料样本。只在本机,不进仓库 |
| `docs/` | 架构、决定、坑 |
| `.harness/` | 给 agent 和人看的现状、规则、检查清单 |

## 检查

| 层 | 什么时候跑 | 入口 | 现状 |
|---|---|---|---|
| 代码检查 | 每次提交 | 本机提交前跑 `bash scripts/check_forbidden.sh` 和 `terraform fmt`、`validate`;推送后 GitHub Actions 再跑一遍 | 已就位;Python 测试等 `app/` 有代码后加 |
| 数据检查 | 每次入库后 | `CALL MEDRAG.OPS.RUN_DATA_CHECKS()` | 计划 |
| 评测 | 改动解析、切分、检索配置时 | `CALL MEDRAG.EVAL.RUN_EVAL('<配置名>')` | 计划 |

## 部署顺序

1. Azure 第一阶段:`infra/azure` apply 资源组、存储账户、容器、队列、Event Grid system topic。(已完成)
2. Snowflake:`setup/01_azure_integrations.sql` 建存储集成和通知集成;在 Azure 租户里对两者 consent。(已完成)
3. Azure 第二阶段:填入两个 service principal 的对象 ID,再 apply 角色分配和事件订阅。(已完成)
4. Snowflake:`setup/00_role_and_database.sql` 建专用角色 MEDRAG_ADMIN 和 MEDRAG 库,再执行一次 `setup/01_azure_integrations.sql` 把两个集成的 USAGE 授给它,然后 `setup/02_schemas.sql`。新环境从头部署时按 00、01、02 的顺序执行。(已完成)
5. Snowflake:用户建只读 GitHub token 的 secret,再执行 `setup/03_git_repository.sql` 建 Git 仓库对象。(已完成)

之后改了 SQL,都从 Git 仓库对象部署:先推送,再 `ALTER GIT REPOSITORY MEDRAG.OPS.REPO FETCH`,再 `EXECUTE IMMEDIATE FROM @MEDRAG.OPS.REPO/branches/main/deploy.sql`(用 MEDRAG_ADMIN;要传的值见文件头)。每次部署在 `MEDRAG.OPS.DEPLOY_LOG` 记一行提交 sha。

6. 先验证三项(见 `docs/decisions.md`),再写入库过程。
