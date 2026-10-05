# Multi-index 权重实验

2026-10-04，用户授权在现有 MEDICAL_CHUNKS_MARKDOWN_MULTI_INDEX_1200_200 上调参。仅修改每次查询的 scoring_config；服务默认、chunks、题集、embedding 与评分规则不变。

同一批209篇/14526块，qset_v1 的50题，evidence_covered_v2，top-k=10。默认组重新运行，用于核对前次0.74/0.529的结果及六参数旧入口兼容性。全部结果作为这50题上的探索调参，不能视为独立测试集成绩。

## 首轮

权重为相对值，不是百分比。总体三个分量之外，关键词字段还可分别加权；未指定的字段权重保持原生默认。

| 配置 | keyword : vector : reranking | 正文 : 章节关键词 | Hit@1 | Hit@5 | Hit@10 | MRR |
|---|---|---|---|---|---|---|
| 默认重跑 | 1:1:1 | 默认 | 0.38 | 0.74 | 0.84 | 0.529 |
| 偏关键词 | 3:1:1 | 默认 | 0.36 | 0.74 | 0.80 | 0.511 |
| 偏向量 | 1:3:1 | 默认 | 0.28 | 0.64 | 0.82 | 0.434 |
| 偏重排 | 1:1:3 | 默认 | 0.44 | 0.80 | 0.84 | 0.579 |
| 偏正文关键词 | 1:1:1 | 3:1 | 0.34 | 0.74 | 0.78 | 0.493 |
| 偏章节关键词 | 1:1:1 | 1:3 | 0.38 | 0.78 | 0.86 | 0.542 |

首轮各50题/500行，全部finished_at非空。默认重跑与前次相同；源块哈希仍为原值。提高重排权重表现最好，提高向量权重退步。次轮比较1:1:2与“1:1:3 + 章节关键词加权”，不再扩展网格。

## 次轮与推荐参数

| 配置 | keyword : vector : reranking | 正文 : 章节关键词 | Hit@1 | Hit@5 | Hit@10 | MRR |
|---|---|---|---|---|---|---|
| 温和重排 | 1:1:2 | 默认 | 0.42 | 0.78 | 0.84 | 0.568 |
| 重排 + 章节 | 1:1:3 | 1:3 | 0.46 | 0.82 | 0.86 | 0.593 |

全部8组各50题/500行，共400次检索、4000行结果。最佳组合相对默认有4题进入前五、0题掉出前五；不意味着所有题的具体名次均改善。服务源块哈希未改变，覆盖上限仍0.94。默认重跑确认六参数入口能调用新重载，返回50 questions；各实验完整配置保存在params。

最佳配置仅作为候选，未写入服务默认或应用配置：

```json
{
  "weights": {"texts": 1, "vectors": 1, "reranker": 3},
  "functions": {
    "text_boosts": [
      {"column": "chunk_text", "weight": 1},
      {"column": "section_path", "weight": 3}
    ]
  }
}
```

两层权重含义不同：整体关键词分量仍为1；其内部章节字段相对正文为3。这不是让章节占整个最终分数的75%。本次观察支持更强的重排和章节信号，不能由权重数值推断模型内部因果机制。只进行了有限8组，不继续在同一批题上扩大搜索。

## 代码与运行

- src/sql/eval/50_retrieval_eval.sql：七参数 RUN_RETRIEVAL_EVAL 重载(原在 60_retrieval_scoring.sql，已合并)，最后一项为 scoring_config OBJECT；完整权重写 EXPERIMENTS.params。
- 原六参数入口保留签名，转调空配置；检索循环只维护一份，RESCORE_EXPERIMENT及评分函数不改。
- 当时用 tests/sql/tune_multi_index.sql 跑首轮六组、次轮两组；已合并为 scripts/sql/run_experiment.sql 模板，ID 一次性，重跑用新 ID。查询只展示finished_at非空的实验。
- 本次直接部署新增重载及同签名旧入口；deploy.sql已接入新模块，未跑Git部署入口。无需创建搜索服务或重新生成embedding。
- 第一次运行遇到OBJECT_CONSTRUCT不接受在INSERT VALUES中的语法限制；改为INSERT SELECT后重跑。失败发生在写入实验记录前，没有产生部分实验需要删除。

实验ID统一为multi_tune_<配置名>_k10_20261004；原历史实验保留。

官方参数：[Cortex Search scoring](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-customize-scoring)。本轮未关闭重排、未引入自定义重排模型。
