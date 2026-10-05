# 当前交付检查

## 本地

```sh
bash scripts/check_forbidden.sh
git diff --check
terraform -chdir=infra/azure fmt -check main.tf variables.tf outputs.tf versions.tf
terraform -chdir=infra/azure validate
```

再看 git status、部署顺序、调用方和文档链接。实验语句保留为注释；用户未填写的核心步骤仍留空。

应用检查：`.venv/bin/python -m pytest`，Docker 启动后检查 `/healthz` 和前端页面。骨架未填写处允许返回 501；完整 HTTP → 检索链路应在用户填写后另做验收。SPCS 部署与入库部署分开。

## Snowflake

写完和运行通过分开报告。只对已实现的步骤验收：捕获后 stream 前进，解析表有结果且页数正确，重复解析返回 SKIPPED；基线切分验空块、重复 ID 和重复调用，token 超限只观察；改进版另验没有超限块。
检索服务部署后用 `tests/sql/checks/verify_search_service.sql` 核对源行数只来自对应配置、服务 ACTIVE，并看能否返回文本、文件名和页码。

正式部署由用户提交推送后从 Git 仓库对象执行，核对 DEPLOY_LOG 的 sha 和 SUCCEEDED。未运行就写待验证；需要浏览器登录时等用户操作。RUN_DATA_CHECKS 和生成质量评测尚未实现。检索评测已有 RUN_RETRIEVAL_EVAL/RESCORE_EXPERIMENT，按下列要求验收。

## 评测

- 审核状态与 PDF 复核意见一致；冻结题集不改旧题，修订使用新题/新题集。
- 校准证据规则：正负号、小数、比较符号、组别/数值对应关系，以及表格行列标签。
- 实验用 `scripts/sql/run_experiment.sql`：同一题集、文件版本；确认检索服务对应配置且已刷新。指标分母包含零结果题，未完成实验不计为最终结果。
- 保存 top-k 原始结果与实验时的覆盖依据；改评分规则记录版本并重算，不把实时 CHUNKS 变化归因为原实验问题。


## Markdown 章节表格策略

- 回填用 `scripts/sql/backfill_snapshot.sql`(5 篇/批;20 篇/批会触发 180 秒超时),验收用 `tests/sql/checks/verify_chunks.sql`:209 篇覆盖、块 ID 唯一、无空块与 NULL token、没有超限块。
- 用 `tests/sql/checks/verify_markdown_locations.sql` 统计正文候选的原样定位与回退率。页码在该版本解析页范围内；定位失败用 TEXT 段范围，补切后代用母块范围，不伪装精确定位。
- 跨页、相邻表格、多层表头、组标签、h1/h2/h3 继承分别验收；单篇重跑结果稳定(`tests/sql/checks/chunk_one_file.sql`)。
- 新配置保持 inactive；服务行数只来自新配置，确认索引刷新完成后用原题集比较。

## 章节上下文搜索对照

- `tests/sql/checks/verify_search_service.sql`：核对新服务 ACTIVE、各 14526 行，源块哈希不变；标题前缀服务另记加前缀后超过 512 token 的块数，不能只检查原正文 token。
- `scripts/sql/run_experiment.sql`：同一 config、原 50 题、相同模型和评分；每次 500 行且 finished_at 有值。评分用原 chunk_text，不用注入标题后的 search_text。
- 两个模块重复部署已实测跳过现有服务；应用仍默认基线。
- 权重对照:scoring_config 作为第 7 个参数传入,完整落进 params,源块哈希不变;六参数入口默认重跑与原指标一致。已实跑 8 组,各 50 题/500 行。
- 结果只写在 docs/experiments/(markdown-search-context.md、multi-index-tuning.md)。
