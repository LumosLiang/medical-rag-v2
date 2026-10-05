# 章节上下文搜索对照

2026-10-04，Snow CLI 直接创建两个服务并完成原 50 题评测。结论：本轮 multi-index 总体最好；保留为实验服务，不切换应用或入库默认。不把 50 题的一次结果称为普遍最佳实践。

## 对照条件

两个新服务复用 `markdown_header_table_1200_200` 的同一批 209 篇、14526 个块；没有改解析、切分、题库或评分。源数据 HASH_AGG 在创建服务前后相同。模型均为 snowflake-arctic-embed-l-v2.0；原 qset_v1、evidence_covered_v2、top-k=10、默认权重与重排。基础 Markdown 与 recursive 的结果沿用同快照已完成实验，未重新运行这两个基础实验。

| 搜索实验 | 服务名（CORE 下） | 索引输入 |
|---|---|---|
| 最近标题前缀 | MEDICAL_CHUNKS_MARKDOWN_HEADING_PREFIX_1200_200 | 源查询生成 search_text = 最近一级标题 + 换行 + 正文，ON search_text |
| Multi-index | MEDICAL_CHUNKS_MARKDOWN_MULTI_INDEX_1200_200 | TEXT INDEXES chunk_text, section_path；VECTOR INDEXES chunk_text |

前缀不写回 CHUNKS；两个服务都返回原始 chunk_text，评分不会把注入的标题当作额外证据。Multi-index 的普通 query 搜索全部已索引字段，现有 RUN_RETRIEVAL_EVAL 可直接复用，无需改签名。完整路径独立作为关键词信号，不为标题新增 embedding，也不假定原生重排内部的多字段拼接方式。

## 结果

两次新实验均已完成 50 题、500 条原始结果，零结果分母问题未触发；各服务 ACTIVE，源行数 14526。

| 指标 | Recursive 基线 | Markdown 原服务 | 最近标题前缀 | Multi-index |
|---|---|---|---|---|
| Hit@1 | 0.280 | 0.280 | 0.360 | 0.380 |
| Hit@5 | 0.680 | 0.620 | 0.660 | 0.740 |
| Hit@10 | 0.740 | 0.800 | 0.800 | 0.840 |
| MRR | 0.439 | 0.442 | 0.490 | 0.529 |
| 单块覆盖上限 | 0.860 | 0.940 | 0.940 | 0.940 |
| 检索调用 p50 ms | 803 | 800 | 908 | 1111 |

相对原 Markdown 服务，前缀让 4 题进入前五、2 题掉出前五；multi-index 让 6 题进入前五、0 题掉出前五。相对 recursive 基线，multi-index 是 8 题改善、5 题退步，净增 3 题，并非逐题全部改善。

| 题型 | 题数 | 前缀 Hit@5 | Multi-index Hit@5 | 前缀 MRR | Multi-index MRR |
|---|---|---|---|---|---|
| 事实 | 10 | 0.500 | 0.800 | 0.363 | 0.466 |
| 数值 | 12 | 0.917 | 1.000 | 0.708 | 0.757 |
| 结论 | 10 | 0.900 | 0.800 | 0.625 | 0.621 |
| 方法 | 10 | 0.600 | 0.700 | 0.413 | 0.438 |
| 表格 | 8 | 0.250 | 0.250 | 0.250 | 0.264 |

PMC9771656 的结论从原 Markdown 第 7 名到两个新服务的第 1 名，支持章节上下文有用的假设。但 PMC12281667 的数据库列表、PMC13384364 的 EPDS 数值证据仍未进入前十；PMC10586829 的结论从第 6 名变为前缀第 6 / multi-index 第 8。标题不足以解决全部排序问题。

## 限制与验收

- 229 个块没有 section_path。标题前缀后有 5 个搜索文本超过 512 token，最长 528；向量窗口可能截断少量尾部，未为实验重切。这一限制不适用于正文 embedding 不变的 multi-index。
- Multi-index 用完整路径；前缀仅用最近标题。本次比较的是两套完整方案，不能把差异全部归因为索引方式。若需归因，后续应统一标题范围。
- 原题集两题证据表名问题、词袋覆盖及“答案正确但指定证据未覆盖”的评分限制保留。表格题 Hit@5 两边均 2/8；前缀 Hit@10 2/8，multi-index 3/8，没有解决全部表格检索问题。
- 延迟为各次实验的观察值，受到并发、缓存和运行时间影响，不当作正式性能基准。
- 新 SQL 模块重复执行实测返回 already exists，不重建服务。根 deploy.sql 已接入，但未通过 Git 仓库入口运行，不新增 DEPLOY_LOG 成功声明。未 commit、push。

运行入口：scripts/sql/run_experiment.sql(当时为两条独立脚本，已合并为模板)；只读验收：tests/sql/checks/verify_search_service.sql。实验参数写入 EXPERIMENTS.params，不新增切分配置。

实验 ID：`markdown_heading_prefix_k10_20261004`、`markdown_multi_index_k10_20261004`。
