# 当前入库规则

设计以 `docs/architecture.md` 为准；当前先跑通，不提前加入重试和复杂状态判断。

- Event Grid → Queue → directory table → stream → task；队列只给 Snowflake 用，排错只 peek。
- 消费 stream 用 INSERT SELECT；普通 SELECT 不消费。stream 只交给一个消费者。
- FILE_CHANGES 每条变更一行，以 `(relative_path, etag)` 识别版本，etag 保留 directory table 原值（含双引号）。PENDING → TO_PARSE / TO_REMOVE → DONE / FAILED。
- RUN_INGEST 按捕获、判断、删旧块、解析、切分的顺序调用；每一步处理所有输入状态的行，各步分开提交。
- 解析只调用一次，保存完整输出后再展开；成功版本再次调用跳过。切分只读 PARSED_DOCS 的 `parse_result:value:pages`。
- `recursive_1200_200` 为待部署基线：直接 recursive 切，none 格式、1200 字符 / 200 字符 overlap，separators 用 Snowflake 默认；不加前缀、不去参考文献。再用 COUNT_TOKENS 检查，超 512 token 继续 recursive 切。chunk_id 唯一且重跑不变，不能有空块。
- 切分的删除和写入在同一个事务里；块表只用增量 DML，不重建。配置参数不可原地改，换参数新建配置名。
- stage 先建且 REFRESH_ON_CREATE=FALSE，再建 stream，再 REFRESH；当前 stage 已部署，task 待填写。留意 SHOW STREAMS 的 STALE_AFTER，不把默认保留期当成固定保证。

自动数据检查、失败重试、完整前缀和参考文献处理在跑通后做。出处见 architecture 的官方参考，实测限制见 `docs/pitfalls.md`。
