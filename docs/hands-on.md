# 动手清单

每个环节的骨架由 agent 搭,关键处留空给你写,或者讨论之后你来写。这份文件列出每个空在哪、要做什么、怎么验收,状态以这里为准。

## 留空怎么留

- **SQL**:留给你的地方用一对标记框出来,框里写清要做什么、输入输出、要注意的坑、怎么验收:
  ```sql
  -- ===== 你来写:环节 2A 消费 stream =====
  -- ...
  -- ===== 到这里 =====
  ```
  没写之前,框里只有一行 `RAISE not_implemented;`,调用时抛出 `NOT_IMPLEMENTED: …`,过程不会半截执行,外层也不会把它当成功。写完把这一行删掉。
- **Python**(环节 10 起):函数体写 `raise NotImplementedError("你来写:...")`,配好验收测试。你写完之前,这些测试在 CI 里标成跳过,CI 不会因此变红;写完去掉标记,测试开始算数。
- **实验**:不写代码的环节(比如环节 1),框里是要你自己写的查询和要你回答的问题。
- **讨论项**:影响骨架怎么搭的,先讨论再搭;影响不到骨架的,边做边讨论。
- **你写完之后**:agent 跑验收、看代码、指出问题,不替你改。你要示范时,agent 写一个同类的小例子,不写你那一题。
- 所有空都能搜到:`grep -rn "你来写" sql eval app scripts`。

状态:**等骨架**(还没搭)、**待你做**、**讨论中**、**完成**。

## 全流程

| # | 环节 | agent 搭的骨架 | 你动手的部分 | 要讨论的 | 状态 |
|---|---|---|---|---|---|
| 1 | 自动刷新 | Terraform、集成、`sql/04_stage.sql`、实验脚本 `sql/spike/10_auto_refresh.sql` | 在 `spike/` 上传、覆盖、删除,自己写查询看 directory table 和 stream,记下看到的 | 为什么先建 stream 再 REFRESH;stream 为什么会过期 | 待你做 |
| 2 | 消费 stream | `INGEST.FILE_STATE`;`INGEST.RUN_INGEST` 外壳 | 2A 消费 stream 的 `INSERT … SELECT`;2B `INGEST.PLAN_BATCH`:判断新增、覆盖、删除 | 事务边界放在哪 | 待你做 |
| 3 | 解析 | `INGEST.PARSE_FILE` 外壳:跳过已解析的版本、检查结果 | 3A 调 `AI_PARSE_DOCUMENT` 写进 `INGEST.PARSED_DOCS`;跑先验证第 1、3 项(花钱,先说) | 失败文件怎么重试 | 待你做 |
| 4 | 配置 | `CORE.PIPELINE_CONFIG`,以及"已部署的配置不可改"的检查 | 4A 定第一个配置的参数值 | 哪些参数值得放进配置 | 待你做 |
| 5 | 切分 | `CORE.CHUNK_DOC` 外壳:读配置和解析结果、先删旧块、事务 | 5A 四步切分,chunk_id 怎么生成 | CHUNKS 还要哪些列(影响引用和过滤) | 待你做 |
| 6 | Task | `sql/31_task.sql` 文件 | 6A task 定义;6B 端到端跑一次新增、覆盖、删除(先验证第 2 项后半) | 失败重试;用哪个 warehouse | 待你做(等 2–5) |
| 7 | Cortex Search | `sql/40_search.sql` 和核对查询 | `CREATE CORTEX SEARCH SERVICE` 本身(花钱,先说) | 哪些列做过滤 | 等骨架 |
| 8 | 数据检查 | `RUN_DATA_CHECKS` 框架和结果表 | 几条关键检查,比如块的 etag 必须等于当前版本 | 哪条不过就停 | 等骨架 |
| 9 | 评测 | `RUN_EVAL` 流程外壳和结果表 | evidence 匹配 `eval/10_match`;Recall@k、MRR 的算法;第一批标注题 | 基线怎么定 | 等骨架 |
| 10 | 检索模块 | Python 接口、Snowflake 连接、假实现、测试框架 | 调 Cortex Search 的那一段:查询、过滤、返回列、结果映射 | | 等骨架 |
| 11 | 生成和引用 | 接口、AI_COMPLETE 调用封装、测试框架 | prompt;解析和校验引用:引用的块必须来自这次检索,否则拒答或降级 | 校验不过时给用户看什么 | 等骨架 |
| 12 | FastAPI | 应用骨架、配置、健康检查、SPCS 上的认证 | `/ask` 的编排:检索、生成、校验、返回;出错时返回什么 | | 等骨架 |
| 13 | Streamlit | 页面 | 引用怎么展示(点一个引用就能看原文块) | | 等骨架 |
| 14 | SPCS 部署 | Dockerfile、服务规格骨架、部署步骤 | 按步骤亲手部署(镜像在外部机器上构建) | compute pool 大小和费用 | 等骨架 |
| 15 | 语料 | 语料脚本骨架(下载、上传到 ADLS) | 选片规则:年份分层、期刊白名单、许可、固定种子 | | 等骨架 |

没列的环节你也想做,加一行就行。已经做完的部分(Azure、集成、MEDRAG_ADMIN、Git 仓库对象、部署入口)不挖空,想重写哪段说一声。

## 入库链路的各个空

这几个空按 1 到 6 的顺序做:前面的输出是后面的输入。环节 6 把它们连起来跑。`RUN_INGEST` 一开头就要求有生效的配置,所以端到端跑之前 4A 要先写好。

现在骨架都已部署(`.harness/context/current-state.md`),每个空写完就能单独调用验收。

### 环节 1:自动刷新(实验)

- **在哪**:`sql/spike/10_auto_refresh.sql`,只在 `spike/` 下做,不进部署入口。
- **要做什么**:按文件里的步骤,在 Azure 上传、覆盖、删除测试 PDF;每一步之后自己写查询,看 directory table 和 stream;回答文件末尾的问题,把"覆盖在 stream 里是什么样子"写进 `docs/decisions.md` 先验证第 2 项。
- **学什么**:事件怎么从 Azure 到 Snowflake;directory table 和 stream 各记什么;stream 什么时候前进。
- **看**:[Refresh directory tables automatically for Azure Blob Storage](https://docs.snowflake.com/en/user-guide/data-load-dirtables-auto-azure)、[Introduction to streams](https://docs.snowflake.com/en/user-guide/streams-intro)、[CREATE STREAM](https://docs.snowflake.com/en/sql-reference/sql/create-stream)。
- **验收**:能回答三个问题:建 stream 之前就登记的文件为什么不在 stream 里;覆盖在 stream 里是几行、各是什么;只 SELECT stream 它会不会前进。
- **讨论**:`04_stage.sql` 为什么先建 stream 再 REFRESH;stream 为什么会过期(`docs/pitfalls.md`)。

### 环节 2A:消费 stream

- **在哪**:`sql/30_ingest.sql` 的 `INGEST.RUN_INGEST`。
- **要做什么**:一条 `INSERT … SELECT`,把 `INGEST.CORPUS_STREAM` 这一批写进 `INGEST.FILE_STATE`,batch_id 用过程里的 `:v_batch_id`。
- **学什么**:stream 只有被 DML 消费才前进,只 SELECT 不算;stream 的元数据列怎么对应到表里。
- **注意**:`CORPUS_STREAM` 要等 `04_stage` 部署后才有;在那之前可以拿环节 1 的 `SPIKE_STREAM` 练同一条语句(写进你自己建的临时表)。
- **验收**:环节 6 端到端时,跑完 stream 为空,`FILE_STATE` 多出这一批的行,行数等于跑之前 stream 里的行数。
- **讨论**:消费和 2B 要不要放进同一个事务。

### 环节 2B:判断新增、覆盖、删除

- **在哪**:`sql/30_ingest.sql` 的 `INGEST.PLAN_BATCH(p_batch_id)`。它是单独的过程,可以不连 stream、用假数据测。
- **要做什么**:读 `FILE_STATE`,决定每一行接下来怎么办,改 status;把删除和被覆盖的旧版本在 `CORE.CHUNKS` 里的块删掉。
- **约定**(骨架依赖这几条):
  - 输入:这一批 `status = 'PENDING'` 的行,以及你决定要重试的 `FAILED` 行。
  - 要解析、切分的行设为 `READY`。`RUN_INGEST` 只处理 `READY` 的行,处理完设为 `DONE` 或 `FAILED`。
  - 不用再处理的行设为 `DONE`,或者你自己定的状态(比如 `SKIPPED`),同时写 `updated_at`。
- **要想清楚的**:覆盖是一删一增;同一路径在不同批次里的先后;以前新增失败的文件后来被删了,还要不要重试;重试几次算够(`.harness/context/current-state.md` 的未决项)。
- **学什么**:按 (路径, etag) 管版本;块表只做增量 DML(`.harness/rules/pipeline-rules.md`)。
- **验收**:往 `FILE_STATE` 插几组假数据(batch_id 用 `TEST_` 开头),`CALL INGEST.PLAN_BATCH('TEST_1')`,查 status 对不对。至少覆盖:新增、覆盖、删除、同一路径先失败后删除。要测删块,就往 `CHUNKS` 插路径以 `TEST_` 开头的假块,而且要在环节 7 建检索服务之前测。测完删掉测试行。

### 环节 3A:解析

- **在哪**:`sql/30_ingest.sql` 的 `INGEST.PARSE_FILE(p_relative_path, p_etag, p_config_name)`。解析选项(parse_mode、page_split)取这个配置。
- **要做什么**:调 `AI_PARSE_DOCUMENT` 解析这一个文件,结果写进 `INGEST.PARSED_DOCS` 一行,成功失败都写。
- **约定**:成功时 `error_message` 为 NULL、`page_count` 有值;失败时 `error_message` 写错误原文。骨架已经处理了两头:之前已解析成功过的版本直接跳过,不会重复计费;你的代码跑完,如果还没有成功的行就抛异常,外层把 `FILE_STATE` 标成 `FAILED`。
- **注意**(`docs/pitfalls.md`):不要放进 CTE,会重复调用、重复计费;用 `return_error_details` 拿错误原文和页数;`page_split` 按页返回;`doc_id` 是文件名去掉 `.pdf`。
- **看**:[AI_PARSE_DOCUMENT](https://docs.snowflake.com/en/sql-reference/functions/ai_parse_document)、[Parsing documents with AI_PARSE_DOCUMENT](https://docs.snowflake.com/en/user-guide/snowflake-cortex/parse-document)。
- **验收**:对一份真实 PDF 调一次,`PARSED_DOCS` 有一行、`page_count` 对;再调一次返回 `SKIPPED`。**这一步花钱,调之前先说一声。** 顺带做先验证第 1 项(能不能直接读 Azure 外部 stage)和第 3 项(单篇耗时和成本),方法见 `docs/decisions.md`。
- **讨论**:失败文件怎么重试。

### 环节 4A:第一个配置

- **在哪**:`sql/10_config.sql`。
- **要做什么**:写第一个配置的参数值,`is_active` 设为 TRUE。每个参数的意思见文件里的注释;起点值在 `docs/architecture.md` 第 5 节。
- **规则**(你定的):配置名一旦部署,参数就固定,要换参数就新建一个名字;只有 `is_active` 和 `note` 能改;入库用 `is_active` 的那个,必须正好一个。
- **学什么**:每个参数怎么影响切分;配置为什么要不可改(评测结果要能对上当时用的参数)。
- **验收**:部署通过,`PIPELINE_CONFIG` 里正好一个 `is_active`;故意改一个已部署配置的参数再部署,报 `-20101`,改回来再部署又通过。
- **讨论**:还缺哪些参数、哪些不该放这里(指标参数放评测自己的表,见 `.harness/rules/eval-rules.md`)。

### 环节 5A:切分

- **在哪**:`sql/20_chunk.sql` 的 `CORE.CHUNK_DOC(p_relative_path, p_etag, p_config_name, p_target_table)`。
- **要做什么**:四步切分(`.harness/rules/pipeline-rules.md`),结果写进 `p_target_table`。入库时它是 `MEDRAG.CORE.CHUNKS`,以后评测实验传别的表。
- **约定**:输入是 `PARSED_DOCS` 里这个版本解析成功的那一行,加上 `PIPELINE_CONFIG` 里 `p_config_name` 那一行。输出列见 `sql/11_tables.sql` 的 `CHUNKS`。骨架在你之前已经删掉同一版本、同一配置的旧块,并把整个过程包在事务里。
- **硬性要求**:每块不超过配置的 `max_tokens`,用 `SNOWFLAKE.CORTEX.COUNT_TOKENS(token_model, 文本)` 数(`AI_COUNT_TOKENS` 对 embedding 模型返回 NULL);`chunk_text` 是加了前缀的文本,`chunk_text_raw` 是原文;没有空块;没有参考文献章节;`chunk_id` 唯一、由确定的输入生成、重跑不变。
- **要想清楚的**:pages 先拼起来再切,还是按页切(拼起来标题能跨页,但页码难对上);`chunk_id` 用什么拼;前缀里的文档标题从哪来。
- **看**:[SPLIT_TEXT_MARKDOWN_HEADER](https://docs.snowflake.com/en/sql-reference/functions/split_text_markdown_header-snowflake-cortex)、[SPLIT_TEXT_RECURSIVE_CHARACTER](https://docs.snowflake.com/en/sql-reference/functions/split_text_recursive_character-snowflake-cortex)。
- **验收**:对一篇解析好的文档调用。超标块、空块、重复 chunk_id、参考文献块都是 0;再调一次,chunk_id 不变。
- **讨论**:CHUNKS 还要哪些列,比如标题、期刊、年份这类过滤列。这会影响环节 7:检索服务建好后再改列,会触发全量重新 embedding。

### 环节 6:task 和端到端

- **6A 在哪**:`sql/31_task.sql`。
- **6A 要做什么**:用 `CREATE OR ALTER TASK` 定义 `INGEST.INGEST_TASK`:WHEN 条件、warehouse、调用 `INGEST.RUN_INGEST()`。
- **看**:[CREATE TASK](https://docs.snowflake.com/en/sql-reference/sql/create-task),以及官方的 Triggered tasks 一页。
- **注意**:WHEN 只能用 `SYSTEM$STREAM_HAS_DATA` 这类函数,不能查表;task 建好是暂停的,`RESUME` 之后才会跑,跑就会解析、花钱,RESUME 前先说一声;`04_stage.sql` 和 `31_task.sql` 要一起加进部署入口,避免 stream 空放过期。
- **6B**:在 `pdf/` 下依次新增、覆盖、删除一个文件,不手动刷新、不 `EXECUTE TASK`,看 task 自己跑(先验证第 2 项后半)。
- **验收**:三次都在 30 分钟内自动触发;`FILE_STATE`、`PARSED_DOCS`、`CHUNKS` 和 Azure 上的文件对得上。
- **讨论**:失败重试;warehouse 用 MEDIUM 还是 X-SMALL(解析和切分在同一个 task 里)。

## 之后的环节

环节 7–15 的骨架搭好时,在这里补上各自的说明。
