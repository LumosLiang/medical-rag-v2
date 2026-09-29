# 目标和路线

本阶段先把核心的事件驱动流程完整跑通一遍,细节放到跑通以后。这份文件列出跑通之后逐步要做的目标;逐项现状见 `.harness/context/current-state.md`,用户动手的部分见 `docs/hands-on.md`。

## 本阶段:先跑通

1. 配置、判断变更、删旧块用最简版(agent 写);捕获变更、解析、切分、task 由用户写。
2. 10 篇样本 PDF 传到 `pdf/`,task 自动完成捕获、解析、切分。
3. 建 Cortex Search 服务,用 SQL 检索一个问题,再用 AI_COMPLETE 生成带引用的回答。
4. 覆盖、删除各试一次,块跟着变。

## 跑通之后

### 入库

- 判断变更的完整版:失败重试(次数上限;低频定时的重试 task,或者手动)、同一路径在不同批次里的先后、先失败后删除的文件、不用处理的状态(比如 SKIPPED)。
- 删旧块成功、改状态失败时怎么办,保证重跑不出错。
- 再评估事务边界:捕获和判断放进同一个事务,出错时 stream 不前进。
- 监控:stream 的 STALE_AFTER;task 连续失败自动暂停(SUSPEND_TASK_AFTER_NUM_FAILURES)并告警。
- 先验证第 2 项的结论:不设 SCHEDULE 的 task 能否由 stream 触发、延迟多少(`docs/decisions.md`)。

### 解析和切分

- 先验证第 1、3 项:AI_PARSE_DOCUMENT 能否直接读 Azure 外部 stage;单篇耗时和成本。
- 换了解析参数,已经解析过的版本要不要重新解析。
- 切分的完整做法:加"标题 > 章节"前缀、去掉参考文献章节、回填页码和 section_path;按页切还是拼起来切。
- 每次改参数都新建一个配置名,用评测比较。
- 文档元数据(标题、期刊、年份)和检索的过滤列,要在建检索服务之前定下来。

### 检索

- 过滤列、TARGET_LAG、AUTO_SUSPEND;配置里的 token_model 和检索服务的 embedding 模型保持一致。

### 数据检查

- `.harness/rules/pipeline-rules.md` 里标了"数据检查"的各条:超标块、空块、重复 chunk_id、参考文献块都是 0;每篇解析成功的文档都有块;块的 etag 等于当前版本。
- 每次入库后自动跑,有一条不过就不往下跑评测。

### 评测

- 按 `.harness/rules/eval-rules.md`:标注是 (question, doc_id, evidence 原文),先 30 题,再扩到 60 题以上。
- evidence 匹配、Recall@k、MRR;定基线,MRR 绝对下降超过 0.02 判失败。

### 应用

- 检索模块、生成模块(引用必须来自这次检索,否则拒答或降级)、FastAPI 的 `/ask`、Streamlit(点一个引用就能看原文块)。
- 部署到 SPCS:镜像在外部机器上构建;先定 compute pool 大小和费用。

### 语料

- 正式的语料脚本:PMC OA 可商用、2021–2026 年、医学期刊白名单、按年份分层、固定种子、500–1000 篇;先解析 50 篇测成本。

### 工程

- `app/` 有代码后,CI 加 pytest;之后改成 PR 上 CI 通过才合并。
- 本机 snow CLI 的配置(account 改小写、开 token 缓存)。

## 现在不做

- 和 pgvector + infer-nexus 对比(`docs/architecture.md` 第 10 节)。
