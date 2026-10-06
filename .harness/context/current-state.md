# 当前状态

2026-10-06 更新。代码部署与运行验收分开记录。入库、容器和 task 的状态沿用下列历史验收记录，不代表本轮重新验收。实验数字集中在 `docs/experiments/`。

| 部分 | 状态 |
|---|---|
| Azure ADLS Gen2 → Event Grid → Queue → directory table | 已建立；此前实测新增、覆盖、删除可自动刷新 |
| Snowflake SQL | 2026-10-06 的 30 个入库、搜索和评测模块已通过本机 CLI 部署；原所有者保留。Git 部署日志最近的历史记录仍为提交 `4b39ec3` / SUCCEEDED，本轮未通过 Git 入口执行 |
| CAPTURE_CHANGES、CLASSIFY_CHANGES、REMOVE_OLD_CHUNKS、RUN_INGEST | 2026-10-02 自动触发验收通过(见 INGEST_TASK 行):FILE_CHANGES 共 209 条 DONE、1 条 FAILED(`PMC9883575.pdf`,旧版切分留下的) |
| PARSE_FILE | 已验收：真实 etag 的 PDF 解析出 12 页，重复调用返回 SKIPPED；失败文件也已成功解析 12 页 |
| CHUNK_DOC | 新版已部署。9 份已完成文档补齐 700 个基线块：ID 唯一，无空块、NULL token 或过期版本；17 块超过 512 token，符合基线设计。同一文件重复切分两次均为 69 块且 ID 稳定。补切配置在一份文档上生成 69 块，均不超过 512 token。2026-10-04 为固定快照比较补入 `PMC9883575.pdf` 的 64 个缺失基线块，当前 13666 块/209 篇；FILE_CHANGES 历史 FAILED 状态未改 |
| Markdown 章节+表格策略 | 2026-10-04 新配置 `markdown_header_table_1200_200` 与过程已直接部署，保持 inactive。209 篇固定快照已回填 14526 块，最大 511 token；版本、页码、空块、重复 ID 与超限检查均为 0；跨页块 1841。正文定位回退 0.374%(48/12850)，无缺失页码。完整记录见 docs/experiments/chunking.md |
| INGEST_TASK | 2026-10-02 已 RESUME,现为 started。正式语料分 10 批上传(每批 20 篇,上一批处理完再传下一批),全程没有手动刷新或执行:上传后约 1 分钟 directory table 和 stream 自动更新,task 随即触发。共成功运行 11 次,每次 338–1825 秒,都在默认 60 分钟时限内;新增 200 篇没有失败 |
| Cortex Search | 4 个服务均 ACTIVE、行数与源表一致：基线 `MEDICAL_CHUNKS_RECURSIVE_ONCE_1200_200`(13666 行)；同一批 markdown 块上的三个实验服务 `..._MARKDOWN_HEADER_TABLE_1200_200`、`..._MARKDOWN_HEADING_PREFIX_1200_200`、`..._MARKDOWN_MULTI_INDEX_1200_200`(各 14526 行)。应用和入库默认仍是基线 |
| 回答生成 | 本地已准备 AI_COMPLETE 与引用处理；/ask 留给用户填写，尚未做真实模型验收 |
| 项目结构 | 入库位于 `src/ingestion/sql/`，搜索服务与 Python 应用位于 `src/serving/`，评测位于根目录 `eval/`；手工 SQL 分为 `tests/sql/checks/`(验收)与 `scripts/sql/`(回填、跑实验)。2026-10-04 整理：合并重复脚本、SQL 统一格式(只改空白和关键字大小写，已逐文件比对)，检索实现现已拆至 eval/retrieval/ |
| 前后端 | FastAPI / Streamlit 骨架已准备；Cortex Search 调用、API 路由、前端 HTTP 请求和 session_state 留给用户填写。完整链路尚未实现 |
| Docker / SPCS | 本机两个容器已启动，探针和页面返回 200，前端容器可请求后端 /search（未填写，返回 501）。SPCS 文件已准备但未执行，setup 含账户权限变更 |
| 自动数据检查 | 后续再做 |
| 评测题库 | 快照 `corpus_2026_10_03`:209 篇、2428 页 pypdf 文字层和 sha256。题库 50 条 APPROVED、22 条 REJECTED，`qset_v1` 固定 50 题。PMC12412449、PMC8721628 的证据表名仍未按上轮意见修正，不能写成 50 题均已复核完成。生成质量评测未实现 |
| 正式语料 | 2026-10-02 在本机下载 200 篇 PDF 到 `data/corpus/`(另有已入库的样本 10 篇在 `data/sample/`),分 10 批上传,每批跑完本机检查脚本并人工看题目后才跑下一批;最终全量检查 0 失败。数据只在本机(`.gitignore`)，语料下载和检查脚本目前仅保留本机（scripts/ 已被忽略）。入库后 209 篇解析出的页数与本地记录逐篇一致 |

`recursive_once_1200_200` 是 active 配置；补切策略名为 `recursive_resplit_to_512_tokens_1200_200`。旧名 `recursive_1200_200` 和历史块保留。本次没有更改 Azure 资源。CLI 当前使用受限 PAT 会话，验收时显式指定 `MEDRAG_ADMIN`；仓库脚本保留标准角色声明。

## 2026-10-05 目录整理

- 操作 SQL 移至 `scripts/sql/`，内容未变；验收保留在 `tests/sql/checks/`，单元测试保留在 `tests/unit/`。
- 三个互相依赖的语料 Python 工具曾开放版本管理；当前 scripts/ 已被忽略，工具保留本机，数据与本机配置继续忽略；用法见 `docs/deployment.md`。
- 两个早期 spike SQL 原样归档到 `.harness/local/archive/spike/`；FLATTEN 练习移到 `.harness/local/learning/flatten.sql`。
- 四份历史人工审核文件原样移至 `data/eval/archive/`，PDF 和来源清单保留；未导出或修改冻结题集。
- 清除 scripts/tests 的 Python 缓存；本轮只整理本地文件，没有执行 Snowflake、Azure 或部署。
- 本地检查通过：14 个单元测试、三个语料工具的语法与导入、迁移路径、敏感信息扫描、`git diff --check`。未重新下载或联网检查语料。

## 2026-10-06 职责目录迁移

- `src/` 分为 ingestion（入库）与 serving（搜索、后端、前端）；评测独立移至根目录 `eval/`。
- Python 包名保留 medical_rag；同步 setuptools、pytest、Docker、前端启动命令、Git 部署入口及文档路径。
- 算法、过程签名、SQL 部署顺序、配置和用户学习占位保留；本轮仅本地迁移，没有执行云端部署。
- 本地验收通过：14 个单元测试、editable 构建与重装、仓库外导入及 /healthz；35 个迁移文件只变更路径引用，25 个部署模块和 Docker COPY 路径有效。敏感信息与 Git 格式检查通过；Docker 镜像未重建，Snowflake Git 部署待用户提交后验证。

## 2026-10-06 职责与解释重构

- 配置种子合并，共用参数定义一次；不再创建旧 recursive 别名，也不在每次部署覆盖 active。RUN_INGEST 在消费 stream 前要求 active 恰好一条，去掉字典序 MAX 选择。
- 切分目录为 structured_markdown，helper 按准备全文、提取元素、构建表格块、标注位置命名；新入口 CHUNK_STRUCTURED_MARKDOWN，旧 method/入口作为转调兼容既有配置，不改历史块和实验标识。
- 修复 Markdown 表名冒充章节与单元格尾部转义管道被去掉；新增对应回归检查。续表、表头启发式、脚注与附近正文关联的限制写入策略 README。
- eval 拆成 dataset 与 retrieval；指标代码保留零返回问题、只统计完成实验；空题集和非法 top_k 在调用前拒绝。评分 v2 不改，不重算既有结果。
- 搜索 SQL 按检索输入命名，明确配置、索引字段、模型和请求权重；调参是请求参数，未写进服务默认。
- 设计决定合入 architecture，下一步合入根 README，实验报告合为 chunking/search；旧文件本地归档。30 个模块已通过本机 CLI 部署，按各对象原所有者角色执行；历史验收与本轮复验分开记录。
- 本地 20 项测试通过（包括表名章节、转义管道、重复组标签来源范围及指标零返回/未完成状态），嵌入 Python、30 个模块路径、Markdown 链接、敏感信息和 Git 格式检查通过。指标基础查询在 SQLite 与 Snowflake 合成输入验证：零返回题保留，未完成实验排除。三篇真实论文临时重切通过，正式块未回填。

## 2026-10-06 Snowflake 部署复验

- 30 个本机 SQL 模块已通过 CLI 部署，按原所有者执行，未变更 owner；根 Git 入口与 DEPLOY_LOG 尚未重新运行。
- 四个服务的定义、创建时间、模型、索引行数均未改变且 ACTIVE；所有配置的源块指纹、固定 50 题内容指纹和 active 选择不变，task 保持 started。
- PMC12681061、PMC8721628、PMC9972166 在临时表重切：基线 163 块、structured_markdown 182 块，正文、章节、页码、token 与旧结果相同；改进版最大 501 token，空块/缺页码/重复 ID 为 0。临时表会话结束销毁，正式数据未回填。
- 五组各 50 题/500 行完成。Hit@5：基线 0.68→0.68，章节正文 0.62→0.56，前缀 0.66→0.62，multi 默认 0.74→0.74，最佳权重 0.82→0.78；完整表见 docs/experiments/search.md，不宣称四组结果未变。
- 正文的 50 条历史/当前请求核对通过（问题、服务、列、top-k）；旧请求省略 scoring_config，新默认请求传空对象。同块证据评分相同。13 道差异题直接重复原生请求，有 6 题排名变化；服务内部具体原因未确定，不能直接归因于本轮重构。
- 指标边界在 Snowflake 合成输入验收：零返回题保留、未完成实验排除；既有实验指标在更新视图前后完全相同。检索差异及分项排查已记录，用户已授权提交本次重构。

- 分项定位：同块关键词/向量分数保持一致，reranker_score 存在整批为 0 或小幅非零变化。关闭 reranking 的 SQL 5题×3轮和 REST 3题×4轮均稳定；默认分别有4题、2题不稳定。完整响应无异常提示；刷新记录为 NO_DATA。内部超时/降级未证实，零分/正常请求 ID 与最小复现保留在 .harness/local/refactor_20261006/reranker_reproduction.md。未改默认、未外发报告；用户已授权本次本地 Git 提交，服务端根因仍待确认。

## 实验结论

见 `docs/experiments/README.md`。一句话：按标题切 + 表格单独分组提高了单块覆盖上限，但把标题剥离出检索文本后 Hit@5 下降；让章节信息回到检索(multi-index)并调高重排与章节权重后，是目前最好的一组。权重是在同一批 50 题上调出来的，需要独立新题验证。

## 已知问题

- 两题证据待修订：`PMC12412449` 的表名应为 “Intraclass correlation from Apple Watch”，库中仍写 “for”；`PMC8721628` 的表名不含 “age”，库中仍多出该词。已冻结题集不直接改，修订新题后建立新版题集。
- 评分 v2 是词袋启发式：比较符号相反、组别与数值对调会判为命中(本地复现)。指标视图已部署为冻结题集起算并排除未完成实验；Snowflake 合成输入检查通过，既有实验指标未因视图更新改变。
- 检索结果未保存 etag，重算上限读取实时 CHUNKS；比较不同配置前须核对同一文件版本、服务已刷新及配置覆盖范围。
- EVAL 下 QUESTION_SETS、EXPERIMENTS、COVERAGE_CEILING、RETRIEVAL_RESULTS、REVIEW_IMPORT、RETRIEVAL_METRICS 等由 ACCOUNTADMIN 持有，MEDRAG_ADMIN 不可见；`scripts/sql/run_experiment.sql` 因此暂用 ACCOUNTADMIN。改 owner 属于权限变更，待用户批准。
- 评测模块和 markdown/搜索实验模块都是 CLI 直接部署，`deploy.sql` 已接入，但尚未经过 Git 仓库入口运行，没有新的 DEPLOY_LOG 成功记录。
- 测试文件 `PMC13120580.pdf` 删除后未恢复，本机有原件。

## 下一步

应用继续按 `implementation.md` 实现前端 → /search → Cortex Search，再接 /ask；用户学习位置保留。FAILED 文件的重试、自动数据检查和 SPCS 尚未完成。
