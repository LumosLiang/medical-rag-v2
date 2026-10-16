# 评测

评测以原始 PDF 为依据，比较不同切分与检索方案能否找回完整证据。问题不绑定 chunk_id，也不以某次解析结果定义正确答案。评测工具独立部署，不参与日常入库或在线问答。这里采用固定语料和题集上的离线对照实验，不是线上用户随机分流的 A/B 测试。

```text
题集构建：PDF → 固定快照 → 模型草稿 → PDF 人工审核 → 冻结题集
检索实验：题集 + 搜索服务 + 请求参数 → 原始 top-k → 评分 → 指标
```

## 代码职责

`schema.sql` 集中定义全部评测表；`deploy.sql` 按依赖建立表、函数、过程和指标视图，不生成题目或启动实验。

| 模块 | 作用 |
|---|---|
| `dataset/snapshot.sql` | 记录 PDF 哈希与逐页文字层，辅助证据定位 |
| `dataset/draft_questions.sql` | AI_COMPLETE 起草 DRAFT 问题 |
| `dataset/review_questions.sql` | 应用审核决定；修订生成新题 |
| `dataset/question_sets.sql` | 将批准问题的 ID 冻结为固定题集 |
| `retrieval/run_experiment.sql` | 逐题调用搜索服务，保存原始结果及参数 |
| `retrieval/score_evidence.sql` | 判断单块证据覆盖，支持不重检索的重新评分 |
| `retrieval/metrics.sql` | 从完成实验的全部问题计算指标 |
| `tests/` | 指标分母与完成状态的本地回归 |

语料、问题和题集分别保存，避免文件版本、审核状态与实验结果互相覆盖。`REVIEW_IMPORT` 是审核输入，`EXPERIMENTS` 是实验元数据，`RETRIEVAL_RESULTS` 是原始返回，`COVERAGE_CEILING` 是单块覆盖的派生结果。这些表服务于不同阶段，保留它们以支持复核。

## 使用

先按 [部署说明](../docs/deployment.md#评测工具) 建立评测对象，再使用现有冻结题集运行实验。每次使用新的实验 ID，明确指定服务、切分配置和请求权重。例如原生默认权重：

```sql
CALL MEDRAG.EVAL.RUN_RETRIEVAL_EVAL(
  '<new_experiment_id>', 'qset_v1',
  'MEDRAG.CORE.MEDICAL_CHUNKS_MARKDOWN_MULTI_INDEX_1200_200',
  'markdown_header_table_1200_200', 10, '<experiment_note>',
  OBJECT_CONSTRUCT()
);
SELECT * FROM MEDRAG.EVAL.RETRIEVAL_METRICS
 WHERE experiment_id = '<new_experiment_id>';
```

第七个参数为 `scoring_config`；六参数兼容入口调用同一实现。重新评分使用 `RESCORE_EXPERIMENT`，不会重新调用搜索，但会按当前规则与当前块重算覆盖上限。

## 指标与限制

- **证据 Hit@k**：前 k 个结果中，是否至少有一个块完整覆盖该题证据，再对问题取平均。
- **证据 MRR**：首个覆盖块的排名倒数取平均，未命中记 0，排名范围受实验 top-k 限制。
- **单块覆盖上限**：当前配置的所有文档块中，是否存在一个块覆盖完整证据。

完成实验的零返回题仍进入分母，未完成实验排除；指标边界已在 Snowflake 合成输入中验证。这些指标不是标准 chunk Recall@k，也不是答案质量评分。

评分 v2 要求所有 evidence_parts 位于同一个块内；没有片段时使用 evidence_text。每个片段至少覆盖 90% 的词，数值全部出现。规则是词袋启发式，不能判断比较符号、组别与数值对应关系或结论是否受支持。

PDF 文字层可能抽错符号或表格，因此人工审核以 PDF 为准。评测页码从 1 开始，解析及块页码从 0 开始。冻结后修题建立新题及新题集，不覆盖历史依据。

当前快照 `corpus_2026_10_03` 有 209 篇，`qset_v1` 有 50 道批准题，其中两题证据表名待修订。该题集已用于调参，结果属于探索。检索结果尚未保存 etag，重新评分的上限读取实时 CHUNKS；比较前须确认同一文件版本、服务刷新完成与配置覆盖范围。解析缓存仅按文件版本复用，解析策略对照实验尚需版本隔离。

历史结果集中在 [实验报告](../docs/experiments/README.md)。

## 当前题集与最新评测

`qset_v1` 保留原 50 道开发题。2026-10-16 从未出题的论文中按固定种子选取 50 篇起草，经 PDF 审核、修订和剔除符号表题，形成 49 道 APPROVED，冻结为 `qset_holdout_49_20261016`。原题与修订通过 revised_from 追溯；本机最终 CSV 使用 original_question_id。按明确 ID 合并为 `qset_combined_99_20261016`，不使用会收集整个 snapshot 批准题的宽泛冻结入口。原题集内容不变，合并题集涵盖 99 篇不同论文。

在当前 8K multi-index 服务及应用权重下完成实验 `combined99_8k_20261016_r1`：99 题证据 Hit@5=77.8%、Hit@10=89.9%、MRR@10=0.577；原 50 题为 84.0% / 94.0% / 0.686，新增 49 题为 71.4% / 85.7% / 0.466。每题返回 10 条，共 990 条；49 道云端内容与最终 CSV 一致，源块和旧题集指纹未变。未按新题结果继续调参或删题。

data/eval/ 只保留 [questions.csv](../data/eval/questions.csv)（完整 99 题、来源、证据及逐题结果）和 [README.md](../data/eval/README.md)（审核历史及已知问题）。草稿、重复导出和 archive 已清理；正式原始检索返回保存在 Snowflake EVAL 中。完整配置、结果和边界见 [99 题报告](../docs/experiments/combined-99.md)。

证据只保留回答必需的内容，不因当前切分无法覆盖而删去必要表头、表注或实验归属。当前 EVIDENCE_COVERED 只读取 chunk_text，不读取 section_path；章节上下文仅在路径时可能被漏判，此问题留待 eval 层单独设计，本次没有改变评分输入。3 道新题因固定文字层字形问题无法自动定位，已对照 PDF 核实，未为提高匹配率改原始文字层。
