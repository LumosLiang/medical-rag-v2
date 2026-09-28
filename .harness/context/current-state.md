# 现状

2026-09-28 更新。以实际代码和实测为准;写"计划"的都还没做。每个环节留给用户的空及其状态见 `docs/hands-on.md`,这里只记骨架和对象的状态。

| 组件 | 状态 | 说明 |
|---|---|---|
| 仓库结构、文档、检查规则 | 已实现 | |
| 提交前检查 | 已实现 | 禁止内容扫描、Terraform 格式和校验;本机提交前跑一次,推送后 GitHub Actions 再跑一次 |
| Azure 的 Terraform 代码 | 已实现 | 两个阶段都已 apply |
| Azure 资源(第一阶段) | 已验证 | 2026-09-28 建成:资源组、存储账户(ADLS Gen2)、容器、队列、system topic。已核对实际设置;apply 后 plan 无差异 |
| Azure 资源(第二阶段) | 已验证 | 2026-09-28 建成:两条角色分配、事件订阅。已在 Azure 上核对角色、范围和订阅的过滤条件;apply 后 plan 无差异。Snowflake 这边还没有 stage,端到端没有测过 |
| Snowflake 存储集成、通知集成 | 已实现 | 2026-09-28 用 `sql/01_integrations.sql` 建成,两者 ENABLED;USAGE 已授给 MEDRAG_ADMIN |
| 专用角色 MEDRAG_ADMIN、MEDRAG 库 | 已验证 | 2026-09-28 用 `sql/00_role.sql` 建成。已用 SHOW GRANTS 核对:挂在 SYSADMIN 下、已授给当前用户;拥有库;有 EXECUTE TASK、CORTEX_USER、两个 warehouse 和两个集成的 USAGE |
| schema | 已验证 | 2026-09-28 用 `sql/02_schemas.sql` 建成 INGEST、CORE、EVAL、OPS,owner 都是 MEDRAG_ADMIN |
| Git 仓库对象 | 已验证 | 2026-09-28 用 IDE 连接执行 `sql/03_git_repo.sql` 第 2、3 段建成:Git 用的 API 集成 MEDRAG_GIT_API_INT(ENABLED,USAGE 已授给 MEDRAG_ADMIN)、仓库对象 MEDRAG.OPS.REPO(owner MEDRAG_ADMIN);只读 token 的 secret 由用户建。FETCH 后 main 的提交和本地 HEAD 一致,四个 SQL 文件的 blob 哈希和 `git ls-tree` 一致;从仓库执行 `02_schemas.sql` 成功(可重复执行,没有新建对象) |
| 部署入口 `sql/deploy.sql`、`OPS.DEPLOY_LOG` | 已验证 | 2026-09-28 从仓库对象执行成功:`OPS.DEPLOY_LOG` 已建(owner MEDRAG_ADMIN),记下的 commit_sha 和刚推送的提交一致,状态 SUCCEEDED。第一次执行在 SET 上报错(已修,见 `docs/pitfalls.md`),失败前只执行了建表。现在还没有要嵌套执行的文件 |
| stage、stream `sql/04_stage.sql` | 已实现待验证 | 已写,没执行;要和 `31_task` 一起加进部署入口,避免 stream 空放过期 |
| task | 计划 | |
| FILE_STATE、PARSED_DOCS、CHUNKS | 计划 | |
| 切分过程 `sql/20_chunk.sql` | 计划 | 切分本身是环节 5A |
| 入库过程 `sql/30_ingest.sql` | 计划 | 消费 stream、判断变更、解析是环节 2A、2B、3A |
| Cortex Search 服务 | 计划 | |
| 数据检查 `RUN_DATA_CHECKS` | 计划 | |
| 评测 `RUN_EVAL` | 计划 | evidence 匹配 `eval/10_match.sql` 等见 `docs/hands-on.md` 环节 9 |
| 标注集 | 计划 | 先 30 题,再扩到 60 题以上 |
| 检索、生成模块,FastAPI、Streamlit | 计划 | |
| SPCS 部署 | 计划 | |
| 语料脚本 | 计划 | |

## 先验证

三项都待验证,方法和判断标准见 `docs/decisions.md`。Azure、两个集成、角色、schema 和 Git 仓库对象都已就绪,第 1、2 项可以随时做。

## 未决

- 失败文件怎么重试:Task 的 WHEN 不能查表,失败文件不会自动重试。写入库过程时定,可以加一个低频定时的重试 task,也可以手动调用。
- 代码检查什么时候从"本机加推送后 CI"改成"PR 上 CI 通过才合并":`app/` 有代码后再定。
- 本机的 snow CLI:连接配置里 account 是大写,直接用会报 client_id 为空;执行时用 `--account` 传小写可以登录(已实测)。但没开 token 缓存,每次登录都要在浏览器里 2 分钟内完成,超时就失败(已实测)。内置的 SNOWFLAKE$LOCAL_APPLICATION 会发 90 天的 refresh token;要不要改本机配置(account 改小写、开 token 缓存和刷新),由用户定。
