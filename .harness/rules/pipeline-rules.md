# 当前入库规则

设计以 `docs/architecture.md` 为准；当前入库已验证；重试与自动数据检查尚未实现。

chunk/schema.sql 管理块表，chunk/chunk_doc.sql 是统一入口，chunk/strategies/ 保存策略；结构化策略按文档、表格和位置标注划分内部职责。

入库实现位于 `src/ingestion/sql/`：config.sql、source.sql 管理配置与数据源，task.sql 触发 run_pipeline.sql，stages/ 保存捕获、分类、删除和解析步骤；搜索服务与应用位于 `src/serving/`；评测独立位于根目录 `eval/`。

- Event Grid → Queue → directory table → stream → task；队列只给 Snowflake 用，排错只 peek。
- 消费 stream 用 INSERT SELECT；普通 SELECT 不消费。stream 只交给一个消费者。
- FILE_CHANGES 每条变更一行，以 `(relative_path, etag)` 识别版本，etag 保留 directory table 原值（含双引号）。PENDING → TO_PARSE / TO_REMOVE → DONE / FAILED。
- RUN_INGEST 按捕获、判断、删旧块、解析、切分的顺序调用；每一步处理所有输入状态的行，各步分开提交。
- 解析只调用一次，保存完整输出后再展开；成功版本再次调用跳过。切分只读 PARSED_DOCS 的 `parse_result:value:pages`，基线按页切并保留页码；章节表格策略规范化后拼接全文，通过字符范围回算页码。
- `recursive_once_1200_200` 为当前基线：每页只做一次 recursive 切分，none 格式、1200 字符 / 200 字符 overlap，separators 用 Snowflake 默认；token_count 仅作观察，不因超过 512 而失败。`recursive_resplit_to_512_tokens_1200_200` 是补切改进版，超限时递归缩小尺寸。旧配置 `recursive_1200_200` 及其历史块保留。两种新配置不加前缀、不去参考文献；chunk_id 唯一且重跑不变，不能有空块。
- 切分的删除和写入在同一个事务里；块表只用增量 DML，不重建。配置参数不可原地改，换参数新建配置名。
- CHUNK_DOC 统一校验配置和事务，按 `chunk_method` 调用同签名的 `CORE.CHUNK_<METHOD>`；算法过程生成块、做策略特有的验收并 INSERT，不开启自己的事务；超限策略自行检查 max_tokens 并抛异常，由 CHUNK_DOC 回滚。
- 各策略的块共用 CORE.CHUNKS，以 config_name 区分；每个检索服务只筛选一个配置，服务名后缀对应该配置名。新策略保持 inactive，固定快照回填和评测；日常 ingest 与应用目前统一使用 structured_markdown_8k_body_1024。
- stage 先建且 REFRESH_ON_CREATE=FALSE，再建 stream，再 REFRESH；stage 和 task 已部署，运行状态见 current-state。留意 SHOW STREAMS 的 STALE_AFTER，不把默认保留期当成固定保证。

`structured_markdown_8k_body_1024` 已于 2026-10-16 选为日常 active 与应用来源配置：正文目标 1024 tokens，摘要/表格硬上限 8192，method_options 控制完整摘要、表格预算与保守噪声过滤。只处理明确识别的参考文献章节，不按正文引用数字删文本；清理后重算全文页范围。旧配置 options 为空，保留原行为。

自动数据检查、失败重试尚未实现；参考文献标题缺失的兜底识别尚未实现。出处见 architecture 的官方参考，主要设计取舍见 `docs/challenges.md`。
