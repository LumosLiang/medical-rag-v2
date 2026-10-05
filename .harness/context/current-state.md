# 当前状态

2026-10-05 更新。代码部署与运行验收分开记录。入库、容器和 task 的状态沿用下列历史验收记录，不代表本轮重新验收。实验数字只在 `docs/experiments/README.md`。

| 部分 | 状态 |
|---|---|
| Azure ADLS Gen2 → Event Grid → Queue → directory table | 已建立；此前实测新增、覆盖、删除可自动刷新 |
| Snowflake 入库 SQL | Git 提交 `4b39ec3` 已部署，`OPS.DEPLOY_LOG` 为 `SUCCEEDED` |
| CAPTURE_CHANGES、CLASSIFY_CHANGES、REMOVE_OLD_CHUNKS、RUN_INGEST | 2026-10-02 自动触发验收通过(见 INGEST_TASK 行):FILE_CHANGES 共 209 条 DONE、1 条 FAILED(`PMC9883575.pdf`,旧版切分留下的) |
| PARSE_FILE | 已验收：真实 etag 的 PDF 解析出 12 页，重复调用返回 SKIPPED；失败文件也已成功解析 12 页 |
| CHUNK_DOC | 新版已部署。9 份已完成文档补齐 700 个基线块：ID 唯一，无空块、NULL token 或过期版本；17 块超过 512 token，符合基线设计。同一文件重复切分两次均为 69 块且 ID 稳定。补切配置在一份文档上生成 69 块，均不超过 512 token。2026-10-04 为固定快照比较补入 `PMC9883575.pdf` 的 64 个缺失基线块，当前 13666 块/209 篇；FILE_CHANGES 历史 FAILED 状态未改 |
| Markdown 章节+表格策略 | 2026-10-04 新配置 `markdown_header_table_1200_200` 与过程已直接部署，保持 inactive。209 篇固定快照已回填 14526 块，最大 511 token；版本、页码、空块、重复 ID 与超限检查均为 0；跨页块 1841。正文定位回退 0.374%(48/12850)，无缺失页码。完整记录见 docs/experiments/markdown-table-gate.md |
| INGEST_TASK | 2026-10-02 已 RESUME,现为 started。正式语料分 10 批上传(每批 20 篇,上一批处理完再传下一批),全程没有手动刷新或执行:上传后约 1 分钟 directory table 和 stream 自动更新,task 随即触发。共成功运行 11 次,每次 338–1825 秒,都在默认 60 分钟时限内;新增 200 篇没有失败 |
| Cortex Search | 4 个服务均 ACTIVE、行数与源表一致：基线 `MEDICAL_CHUNKS_RECURSIVE_ONCE_1200_200`(13666 行)；同一批 markdown 块上的三个实验服务 `..._MARKDOWN_HEADER_TABLE_1200_200`、`..._MARKDOWN_HEADING_PREFIX_1200_200`、`..._MARKDOWN_MULTI_INDEX_1200_200`(各 14526 行)。应用和入库默认仍是基线 |
| 回答生成 | 本地已准备 AI_COMPLETE 与引用处理；/ask 留给用户填写，尚未做真实模型验收 |
| 项目结构 | Python 应用位于 `src/medical_rag/`，SQL 位于 `src/sql/`；手工 SQL 分为 `tests/sql/checks/`(验收)与 `scripts/sql/`(回填、跑实验)。2026-10-04 整理：合并重复脚本、SQL 统一格式(只改空白和关键字大小写，已逐文件比对)，`RUN_RETRIEVAL_EVAL` 七参数实现并回 `src/sql/eval/50` |
| 前后端 | FastAPI / Streamlit 骨架已准备；Cortex Search 调用、API 路由、前端 HTTP 请求和 session_state 留给用户填写。完整链路尚未实现 |
| Docker / SPCS | 本机两个容器已启动，探针和页面返回 200，前端容器可请求后端 /search（未填写，返回 501）。SPCS 文件已准备但未执行，setup 含账户权限变更 |
| 自动数据检查 | 后续再做 |
| 评测题库 | 快照 `corpus_2026_10_03`:209 篇、2428 页 pypdf 文字层和 sha256。题库 50 条 APPROVED、22 条 REJECTED，`qset_v1` 固定 50 题。PMC12412449、PMC8721628 的证据表名仍未按上轮意见修正，不能写成 50 题均已复核完成。生成质量评测未实现 |
| 正式语料 | 2026-10-02 在本机下载 200 篇 PDF 到 `data/corpus/`(另有已入库的样本 10 篇在 `data/sample/`),分 10 批上传,每批跑完本机检查脚本并人工看题目后才跑下一批;最终全量检查 0 失败。数据只在本机(`.gitignore`)，语料下载和检查脚本现已开放版本管理。入库后 209 篇解析出的页数与本地记录逐篇一致 |

`recursive_once_1200_200` 是 active 配置；补切策略名为 `recursive_resplit_to_512_tokens_1200_200`。旧名 `recursive_1200_200` 和历史块保留。本次没有更改 Azure 资源。CLI 当前使用受限 PAT 会话，验收时显式指定 `MEDRAG_ADMIN`；仓库脚本保留标准角色声明。

## 2026-10-05 目录整理

- 操作 SQL 移至 `scripts/sql/`，内容未变；验收保留在 `tests/sql/checks/`，单元测试保留在 `tests/unit/`。
- 三个互相依赖的语料 Python 工具开放版本管理，数据与本机配置继续忽略；用法见 `scripts/README.md`。
- 两个早期 spike SQL 原样归档到 `.harness/local/archive/spike/`；FLATTEN 练习移到 `.harness/local/learning/flatten.sql`。
- 四份历史人工审核文件原样移至 `data/eval/archive/`，PDF 和来源清单保留；未导出或修改冻结题集。
- 清除 scripts/tests 的 Python 缓存；本轮只整理本地文件，没有执行 Snowflake、Azure 或部署。
- 本地检查通过：14 个单元测试、三个语料工具的语法与导入、迁移路径、敏感信息扫描、`git diff --check`。未重新下载或联网检查语料。

## 实验结论

见 `docs/experiments/README.md`。一句话：按标题切 + 表格单独分组提高了单块覆盖上限，但把标题剥离出检索文本后 Hit@5 下降；让章节信息回到检索(multi-index)并调高重排与章节权重后，是目前最好的一组。权重是在同一批 50 题上调出来的，需要独立新题验证。

## 已知问题

- 两题证据待修订：`PMC12412449` 的表名应为 “Intraclass correlation from Apple Watch”，库中仍写 “for”；`PMC8721628` 的表名不含 “age”，库中仍多出该词。已冻结题集不直接改，修订新题后建立新版题集。
- 评分 v2 是词袋启发式：比较符号相反、组别与数值对调会判为命中(本地复现)。`RETRIEVAL_METRICS` 从返回结果起算，会漏掉零结果题，也未排除未完成实验。
- 检索结果未保存 etag，重算上限读取实时 CHUNKS；比较不同配置前须核对同一文件版本、服务已刷新及配置覆盖范围。
- EVAL 下 QUESTION_SETS、EXPERIMENTS、COVERAGE_CEILING、RETRIEVAL_RESULTS、REVIEW_IMPORT、RETRIEVAL_METRICS 等由 ACCOUNTADMIN 持有，MEDRAG_ADMIN 不可见；`scripts/sql/run_experiment.sql` 因此暂用 ACCOUNTADMIN。改 owner 属于权限变更，待用户批准。
- 评测模块和 markdown/搜索实验模块都是 CLI 直接部署，`deploy.sql` 已接入，但尚未经过 Git 仓库入口运行，没有新的 DEPLOY_LOG 成功记录。
- 测试文件 `PMC13120580.pdf` 删除后未恢复，本机有原件。

## 下一步

应用继续按 `implementation.md` 实现前端 → /search → Cortex Search，再接 /ask；用户学习位置保留。FAILED 文件的重试、自动数据检查和 SPCS 尚未完成。
