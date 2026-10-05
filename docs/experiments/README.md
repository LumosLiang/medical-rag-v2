# 实验记录

实验数字只写在本目录；其它文档只写结论并链接到这里。
所有实验都在同一条件下：快照 `corpus_2026_10_03`(209 篇)、题集 `qset_v1`(50 题)、评分 `evidence_covered_v2`、top-k = 10。
50 题时 Hit@5 的 95% 置信区间约 ±10 个百分点，几题之差要结合逐题结果看。

| 实验 ID | 改了什么 | Hit@1 | Hit@5 | Hit@10 | MRR | 单块上限 | 详情 |
|---|---|---|---|---|---|---|---|
| `baseline_once_1200_200_k10_20261004_complete` | 基线：逐页 recursive 1200/200，默认权重 | 0.28 | 0.68 | 0.74 | 0.439 | 0.86 | [markdown-table-gate](markdown-table-gate.md) |
| `markdown_header_table_1200_200_k10_20261004` | 整篇拼接 + 按标题切 + 表格单独分组；标题不进检索文本 | 0.28 | 0.62 | 0.80 | 0.442 | 0.94 | [markdown-table-gate](markdown-table-gate.md) |
| `markdown_heading_prefix_k10_20261004` | 同一批块；检索文本 = 最近一级标题 + 正文 | 0.36 | 0.66 | 0.80 | 0.490 | 0.94 | [markdown-search-context](markdown-search-context.md) |
| `markdown_multi_index_k10_20261004` | 同一批块；关键词索引正文 + 章节路径，向量只索引正文 | 0.38 | 0.74 | 0.84 | 0.529 | 0.94 | [markdown-search-context](markdown-search-context.md) |
| `multi_tune_rerank_section_k10_20261004` | multi-index + 权重 1:1:3、章节关键词 3 | 0.46 | 0.82 | 0.86 | 0.593 | 0.94 | [multi-index-tuning](multi-index-tuning.md) |

`multi_tune_*` 其余 7 组见 multi-index-tuning.md。权重调参是在同一批 50 题上选出来的，属于探索结果，需要独立新题验证。

账户里另有三个实验记录不进上表：`baseline_once_1200_200_k10`(补入 PMC9883575 之前的旧基线，已被 `_complete` 取代)，以及两个 `*_rerun_20261004b`(重跑确认结果完全可复现)。

新实验用 `scripts/sql/run_experiment.sql` 跑，跑完在上表加一行，并在对应文档写设置和结论。
