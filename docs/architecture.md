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

PDF 保留在 Azure，不额外复制进 Snowflake 内部 stage。解析结果和文本块落在 Snowflake 表里。入库用 SQL；应用采用 FastAPI、Streamlit，两个 Docker 容器，部署目标为 SPCS。

前端通过 HTTP 调用 `/search` 或 `/ask`，不直接连接 Snowflake。后端使用 Cortex Search Python API 检索，AI_COMPLETE 生成回答；检索原文与页码一起返回前端。当前核心 API、前端 HTTP 和 session_state 尚待实现。SPCS 中只公开前端，由 Snowflake 认证；后端用挂载的 OAuth token 以服务所有者 MEDRAG_ADMIN 执行查询。各用户访问同一语料，尚无按用户分文档的权限设计。

## 入库约定

- stage 指向容器的 `pdf/`，文件名为 `<PMCID>.pdf`；传给 TO_FILE 的路径不再带 `pdf/`。
- Azure 只发支持的 BlobCreated、BlobDeleted，使用 Event Grid schema。只逐个删文件、不重命名；Storage Queue 只由 Snowflake 消费。
- `FILE_CHANGES` 每条文件变更一行，用 `(relative_path, etag)` 区分版本。
- `CAPTURE_CHANGES` 用 INSERT SELECT 消费 stream，写 PENDING；`CLASSIFY_CHANGES` 把 DELETE 分到 TO_REMOVE，其余分到 TO_PARSE。
- `REMOVE_OLD_CHUNKS` 先删 TO_REMOVE 版本的块，再设 DONE；`RUN_INGEST` 对 TO_PARSE 逐条解析、切分，最后设 DONE 或 FAILED。
- 各步分开提交，不包成一个大事务；处理所有符合输入状态的行。当前不自动重试 FAILED。先删后写，新版本失败时文档会暂时不可检索。

## 解析和切分

`PARSE_FILE` 从 PIPELINE_CONFIG 取 LAYOUT、page_split 参数，调用一次 AI_PARSE_DOCUMENT，完整结果先落 PARSED_DOCS。成功时 error_message 为 NULL；同一版本成功后再次调用跳过。切分只读解析表，不重复解析；当前按页切并保留 0 起始页码。

当前默认配置为 `recursive_once_1200_200`：每页调用一次 recursive 切分，格式 `none`，1200 字符、200 字符 overlap，省略 separators 参数以使用 Snowflake 默认分隔符。记录 `token_count`，但超出 512 token 不再补切或让入库失败。`recursive_resplit_to_512_tokens_1200_200` 是改进策略：超限块反复缩小尺寸补切，直到不超过 512 token；若无法达标才报错。已部署的旧名 `recursive_1200_200` 及其历史块保留，不改名。前缀和去参考文献暂时关闭。换策略或参数新建配置名，入库只用唯一 active 配置。

CORE.CHUNKS 存放各策略的块，以 config_name 区分；chunk_id 包含配置名，确定且唯一。表只做增量 DML，开启 CHANGE_TRACKING；切分过程删除同版本同配置的旧块、写新块放在一个事务里。
`CHUNK_DOC` 通过 `chunk_method` 调用对应的 `CORE.CHUNK_<METHOD>` 过程；每个算法接受同一组参数，只负责生成和插入块。配置检查、删旧块、事务及通用验收留在 `CHUNK_DOC`。新算法增加独立过程和配置，不扩写切分入口。

## 检索与部署

每个切分配置对应独立 Cortex Search 服务，服务名采用 `MEDICAL_CHUNKS_<CONFIG_NAME>`。当前只部署 `MEDICAL_CHUNKS_RECURSIVE_ONCE_1200_200`，源查询固定筛选 `recursive_once_1200_200`，主键为 chunk_id，模型与 token_model 一致。其他策略的块可共存于同一表，需要检索时再建对应服务，并确保该配置覆盖同一批文件版本。切换 active 配置不会自动重切历史文件，也不会改变已有服务的源查询。基线块超过模型的 512-token 窗口时，语义向量只使用截断部分，关键词检索仍使用全文。应用通过 RAG_CONFIG_NAME 选择相应服务，不更改入库 active 配置。评测稍后实现。

应用与入库分开部署：本机使用 `compose.yaml`，SPCS 文件在 `deploy/spcs/`，不加入根目录 deploy.sql。前端只保存当前问题的结果；暂不将历史对话送入模型。运行说明见 `docs/deployment.md`。

Azure 用 Terraform；setup 是一次性引导。日常 SQL 从 Snowflake Git 仓库对象部署，deploy.sql 记录 sha，执行入库和搜索各模块。实验语句不执行；task 创建时默认暂停，运行时需显式 RESUME；现有部署的运行状态见验收记录。项目对象归 MEDRAG_ADMIN，v1 MEDICAL_RAG 不改。

## 官方参考

- [Azure directory table 自动刷新](https://docs.snowflake.com/en/user-guide/data-load-dirtables-auto-azure)
- [Triggered tasks](https://docs.snowflake.com/en/user-guide/tasks-triggered)
- [AI_PARSE_DOCUMENT](https://docs.snowflake.com/en/sql-reference/functions/ai_parse_document)
- [Recursive 切分](https://docs.snowflake.com/en/sql-reference/functions/split_text_recursive_character-snowflake-cortex)
- [COUNT_TOKENS](https://docs.snowflake.com/en/sql-reference/functions/count_tokens-snowflake-cortex)
- [递归 CTE](https://docs.snowflake.com/en/sql-reference/constructs/with)
- [Cortex Search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview)
