# 现状

2026-09-29 更新。以实际代码和实测为准;写"计划"的都还没做。每个环节留给用户的空及其状态见 `docs/hands-on.md`,这里只记骨架和对象的状态。

| 组件 | 状态 | 说明 |
|---|---|---|
| 仓库结构、文档、检查规则 | 已实现 | |
| 提交前检查 | 已实现 | 禁止内容扫描、Terraform 格式和校验;本机提交前跑一次,推送后 GitHub Actions 再跑一次 |
| Azure 的 Terraform 代码 | 已实现 | 两个阶段都已 apply,队列角色的改动也已 apply |
| Azure 资源(第一阶段) | 已验证 | 2026-09-28 建成:资源组、存储账户(ADLS Gen2)、容器、队列、system topic。已核对实际设置;apply 后 plan 无差异 |
| Azure 资源(第二阶段) | 已验证 | 2026-09-28 建成两条角色分配和事件订阅。队列上原来的 Storage Queue Data Message Processor 不够,建 SPIKE_STAGE 报 403(`docs/pitfalls.md`);改成 Storage Queue Data Contributor 并 apply 后,SPIKE_STAGE 建成,上传和删除都自动进了 directory table 和 stream,apply 后 plan 无差异 |
| Snowflake 存储集成、通知集成 | 已实现 | 2026-09-28 用 `setup/01_azure_integrations.sql`(当时在 `sql/` 下)建成,两者 ENABLED;USAGE 已授给 MEDRAG_ADMIN |
| 专用角色 MEDRAG_ADMIN、MEDRAG 库 | 已验证 | 2026-09-28 用 `setup/00_role_and_database.sql` 建成。已用 SHOW GRANTS 核对:挂在 SYSADMIN 下、已授给当前用户;拥有库;有 EXECUTE TASK、CORTEX_USER、两个 warehouse 和两个集成的 USAGE |
| schema | 已验证 | 2026-09-28 用 `setup/02_schemas.sql` 建成 INGEST、CORE、EVAL、OPS,owner 都是 MEDRAG_ADMIN |
| Git 仓库对象 | 已验证 | 2026-09-28 用 IDE 连接执行 `setup/03_git_repository.sql` 第 2、3 段建成:Git 用的 API 集成 MEDRAG_GIT_API_INT(ENABLED,USAGE 已授给 MEDRAG_ADMIN)、仓库对象 MEDRAG.OPS.REPO(owner MEDRAG_ADMIN);只读 token 的 secret 由用户建。FETCH 后 main 的提交和本地 HEAD 一致,四个 SQL 文件的 blob 哈希和 `git ls-tree` 一致;从仓库执行 `02_schemas.sql` 成功(可重复执行,没有新建对象) |
| 部署入口 `deploy.sql`、`OPS.DEPLOY_LOG` | 改动待部署 | 2026-09-28 从仓库对象执行成功:`OPS.DEPLOY_LOG` 已建(owner MEDRAG_ADMIN),记下的 commit_sha 和推送的提交一致,状态 SUCCEEDED;第一次执行在 SET 上报错(已修,见 `docs/pitfalls.md`)。2026-09-29 从 `sql/` 移到根目录,改成按数据流向嵌套执行 `ingest/` 里的文件,还没从新位置部署过 |
| stage、stream `ingest/20_corpus_stage_and_stream.sql` | 已实现待部署 | 已加进部署入口,先于 task 部署,方便对着真实文件测解析;stream 14 天没人消费会过期。同样的建法在环节 1 的实验里用过 |
| task | 计划 | `ingest/90_ingest_task.sql` 只有留空(环节 6A),不进部署入口 |
| 配置 `ingest/10_pipeline_config.sql` | 已实现待部署 | 2026-09-28 部署过空表(`55fa971`)。2026-09-29 agent 写了最简配置 `base_1200`;`split_headers` 从 ARRAY 改成 SPLIT_TEXT_MARKDOWN_HEADER 要的 OBJECT,Snowflake 里的空表要 DROP 重建(待用户批准)。"已部署的配置不可改"的比对用会话临时表测过 |
| PARSED_DOCS、CHUNKS(`ingest/60_parse_documents.sql`、`70_chunk_documents.sql`) | 已验证 | 2026-09-28 部署(`55fa971`),owner 都是 MEDRAG_ADMIN,CHUNKS 的 change tracking 是 ON,都是空表。2026-09-29 表定义移进用它们的那一步,内容没变 |
| FILE_CHANGES(`ingest/30_capture_file_changes.sql`) | 已实现待部署 | 由 FILE_STATE 改名(`docs/decisions.md`)。Snowflake 里现在还是空表 FILE_STATE;部署前 DROP 它(用户已批准,删前再查一次行数),部署时建 FILE_CHANGES |
| 切分过程 `ingest/70_chunk_documents.sql` | 骨架已部署 | `CORE.CHUNK_DOC` 已建(`55fa971`);调用时先检查配置和解析结果(已测:配置不存在时报 -20111);切分本身是环节 5A。2026-09-29 换了文件,只改了注释和报错里的路径,新版本待部署 |
| 入库过程 `ingest/30`–`80` | 已实现待部署 | 2026-09-29 拆开:新建 `CAPTURE_CHANGES`、`CLASSIFY_CHANGES`、`REMOVE_OLD_CHUNKS`,`RUN_INGEST` 只剩调用顺序,`PARSE_FILE` 挪到 `60_parse_documents`;状态 READY 改名 TO_PARSE,新增 TO_REMOVE。判断变更和删旧块由 agent 写了最简版(按动作分、不重试);捕获、解析、切分留给用户。四个过程的语法用只编译的方式检查过。Snowflake 里现在还是 `55fa971` 的 `RUN_INGEST`、`PLAN_BATCH`、`PARSE_FILE`;部署前 DROP `PLAN_BATCH`(用户已批准) |
| Cortex Search 服务 | 计划 | |
| 数据检查 `RUN_DATA_CHECKS` | 计划 | |
| 评测 `RUN_EVAL` | 计划 | evidence 匹配 `eval/10_match.sql` 等见 `docs/hands-on.md` 环节 9 |
| 标注集 | 计划 | 先 30 题,再扩到 60 题以上 |
| 检索、生成模块,FastAPI、Streamlit | 计划 | |
| SPCS 部署 | 计划 | |
| 10 篇样本 `scripts/fetch_sample_pdfs.py` | 已验证 | 2026-09-28 按用户要求在本机跑:近 5 年、临床期刊白名单、允许商用的许可,10 篇来自 10 本期刊,每篇 md5 和 S3 上 JSON 给的一致。PDF 在 `data/sample/pdf/`(不进仓库),清单 `data/sample/manifest.csv`。还没传到 Azure |
| 正式语料脚本 | 计划 | 选片规则是环节 15(`docs/hands-on.md`) |

## 先验证

三项都没有最终结论,方法和判断标准见 `docs/decisions.md`。第 2 项里 stream 的部分已在环节 1 测过(实验用的 stage、stream 和文件已删),task 触发留到环节 6B。Azure、两个集成、角色、schema 和 Git 仓库对象都已就绪,带自动刷新的 stage 也已实测能建。

## 未决

- 失败文件怎么重试:Task 的 WHEN 不能查表,失败文件不会自动重试。写入库过程时定,可以加一个低频定时的重试 task,也可以手动调用。
- 代码检查什么时候从"本机加推送后 CI"改成"PR 上 CI 通过才合并":`app/` 有代码后再定。
- 本机的 snow CLI:连接配置里 account 是大写,直接用会报 client_id 为空;执行时用 `--account` 传小写可以登录(已实测)。但没开 token 缓存,每次登录都要在浏览器里 2 分钟内完成,超时就失败(已实测)。内置的 SNOWFLAKE$LOCAL_APPLICATION 会发 90 天的 refresh token;要不要改本机配置(account 改小写、开 token 缓存和刷新),由用户定。
