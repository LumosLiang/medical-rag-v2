# 架构

本阶段先跑通核心链路。实际进度只记在 `.harness/context/current-state.md`，下图包含尚未实现的步骤。

## 流程

```text
Azure ADLS Gen2 的 PDF 新增 / 覆盖 / 删除
  → Event Grid → Storage Queue → Snowflake 通知集成
  → CORPUS_STAGE 的 directory table 自动刷新
  → CORPUS_STREAM → task → RUN_INGEST
  → 捕获变更 → 判断变更 → 删旧块 → 解析 → 切分
  → CORE.CHUNKS → Cortex Search → AI_COMPLETE 带引用的回答
```

PDF 保留在 Azure，不额外复制进 Snowflake 内部 stage。解析结果和文本块落在 Snowflake 表里。入库、切分和检索用 SQL；后续 FastAPI、Streamlit 用 Python，部署到 SPCS。

## 入库约定

- stage 指向容器的 `pdf/`，文件名为 `<PMCID>.pdf`；传给 TO_FILE 的路径不再带 `pdf/`。
- Azure 只发支持的 BlobCreated、BlobDeleted，使用 Event Grid schema。只逐个删文件、不重命名；Storage Queue 只由 Snowflake 消费。
- `FILE_CHANGES` 每条文件变更一行，用 `(relative_path, etag)` 区分版本。
- `CAPTURE_CHANGES` 用 INSERT SELECT 消费 stream，写 PENDING；`CLASSIFY_CHANGES` 把 DELETE 分到 TO_REMOVE，其余分到 TO_PARSE。
- `REMOVE_OLD_CHUNKS` 先删 TO_REMOVE 版本的块，再设 DONE；`RUN_INGEST` 对 TO_PARSE 逐条解析、切分，最后设 DONE 或 FAILED。
- 各步分开提交，不包成一个大事务；处理所有符合输入状态的行。当前不自动重试 FAILED。先删后写，新版本失败时文档会暂时不可检索。

## 解析和切分

`PARSE_FILE` 从 PIPELINE_CONFIG 取 LAYOUT、page_split 参数，调用一次 AI_PARSE_DOCUMENT，完整结果先落 PARSED_DOCS。成功时 error_message 为 NULL；同一版本成功后再次调用跳过。切分只读解析表，不重复解析；当前按页切并保留 0 起始页码。

下一次部署的默认配置为 `recursive_1200_200`：直接 recursive 切分，格式 `none`，1200 字符、200 字符 overlap，省略 separators 参数以使用 Snowflake 默认分隔符；chunk_size 必填、overlap 默认 0，所以 1200 / 200 是项目选择。每块仍最多 512 token，模型 `snowflake-arctic-embed-l-v2.0`，超限块继续 recursive 切。旧配置 `base_1200` 保留并停用。前缀和去参考文献暂时关闭。配置名对应固定参数，换参数新建名字；入库只用唯一 active 配置。

CHUNKS 只做增量 DML，开启 CHANGE_TRACKING；chunk_id 是确定且唯一的字符串。切分过程删除同版本同配置的旧块、写新块放在一个事务里。

## 后续和部署

切分后建 Cortex Search，源为 CHUNKS，主键 chunk_id、模型与 token_model 一致，再用 AI_COMPLETE 生成带检索引用的回答。之后再做评测、FastAPI、Streamlit 和 SPCS；自动数据检查也是后续功能。

Azure 用 Terraform；setup 是一次性引导。日常 SQL 从 Snowflake Git 仓库对象部署，deploy.sql 记录 sha，当前执行 ingest/10–90。实验语句不执行；task 创建后暂停，切分验收通过再 RESUME。项目对象归 MEDRAG_ADMIN，v1 MEDICAL_RAG 不改。

## 官方参考

- [Azure directory table 自动刷新](https://docs.snowflake.com/en/user-guide/data-load-dirtables-auto-azure)
- [Triggered tasks](https://docs.snowflake.com/en/user-guide/tasks-triggered)
- [AI_PARSE_DOCUMENT](https://docs.snowflake.com/en/sql-reference/functions/ai_parse_document)
- [Recursive 切分](https://docs.snowflake.com/en/sql-reference/functions/split_text_recursive_character-snowflake-cortex)
- [COUNT_TOKENS](https://docs.snowflake.com/en/sql-reference/functions/count_tokens-snowflake-cortex)
