# 入库、解析、切分、索引的规则

改 `ingest/` 里这几部分之前读这一份。规则可能先于实现;哪些已经落实看 `context/current-state.md`。标了"数据检查"的条目,由 `RUN_DATA_CHECKS` 兜底。

## 入库

- 事件只走一条路:Azure Event Grid → Storage Queue → 通知集成 → 外部 stage 的 directory table 自动刷新 → stream → task → 入库过程。不用 Snowpipe(只把结构化文件装进表)和 Snowpipe Streaming(按行追加),两者都处理不了覆盖和删除。
- 入库分四步,一步一个过程、一个文件,`ingest/80_run_ingest.sql` 的 RUN_INGEST 按顺序调用:捕获变更(30)→ 判断变更(40)→ 删旧块(50)→ 解析(60)、切分(70)。各步各自提交,不包成一个事务(`docs/decisions.md`);每一步处理所有处在它输入状态的行,不只这一批,所以中途失败留下的行下次运行接着处理。
- 捕获变更用 INSERT … SELECT 把 stream 里这一批变更写进 FILE_CHANGES,每条文件变更一行(覆盖一个已经捕获过的文件是一删一增两行)。只 SELECT 不会让 stream 前进。一个 stream 只给一个 task 消费(官方 CREATE TASK)。
- FILE_CHANGES 的 status 约定见 `ingest/30_capture_file_changes.sql` 文件头:PENDING → TO_PARSE(要解析、切分)或 TO_REMOVE(要删块)→ DONE 或 FAILED;每个状态只由一步处理。
- 覆盖按 (路径, etag) 判断:删旧块、写新块,先删后写,块表里只留当前版本。删除靠 stream 里的 DELETE 记录。
- 不支持重命名。开了分层命名空间后,删目录只发 DirectoryDeleted、重命名只发 BlobRenamed,Snowflake 都不处理,块不会下线。所以只逐个删文件、不改名;万一做了,手动 `ALTER STAGE … REFRESH`。
- 失败的文件留在 FILE_CHANGES,带错误原文和重试次数,不丢。Task 的 WHEN 只能用 SYSTEM$STREAM_HAS_DATA 这类函数、不能查表,所以失败文件不会自动重试;重试方式待定。
- Storage Queue 只给 Snowflake 用;排查时只用 peek。
- Task 空闲时,WHEN 里的 SYSTEM$STREAM_HAS_DATA 检查本身能防止 stream 过期;积压超过 14 天仍会过期,要监控 STALE_AFTER(官方 Introduction to streams)。

## 解析

- AI_PARSE_DOCUMENT,LAYOUT 模式,page_split。
- 结果先落表再展开,不要放进 CTE:优化器会内联,函数被重复调用、重复计费。展开 pages 时 FLATTEN 加 OUTER => TRUE,否则解析失败的文档会丢,下次又重新解析。
- PARSED_DOCS 是改切分时唯一的输入;改切分不重新解析。

## 切分

- 四步:SPLIT_TEXT_MARKDOWN_HEADER 按 #、##、### 切 → 丢掉参考文献章节,每块加"标题 > 章节"前缀 → SNOWFLAKE.CORTEX.COUNT_TOKENS 数加了前缀之后的 token → 超过 512 的块用 SPLIT_TEXT_RECURSIVE_CHARACTER 再切。块大小从约 1200 字符起调。
- 进索引的每块不超过 512 token,这是硬性要求。token 用 `SNOWFLAKE.CORTEX.COUNT_TOKENS('snowflake-arctic-embed-l-v2.0', …)` 数;AI_COUNT_TOKENS 对 embedding 模型返回 NULL。数据检查:超标块数为 0。
- 进索引的是加了前缀的文本;原文另存一列,用来展示。
- chunk_id 是 TEXT,唯一,由确定性的输入生成,重跑时不变。数据检查:重复数为 0。
- 没有空块;每篇解析成功的文档都有块;没有参考文献章节的块。数据检查各一项。
- v1 的其余切分规则不默认带入,评测证明有用再加。
- 切分逻辑只有一份(`ingest/70_chunk_documents.sql`),入库和评测实验都调它,参数来自 PIPELINE_CONFIG。
- PIPELINE_CONFIG 里的配置一旦部署,参数就固定;要换参数就新建一个配置名,部署时会检查(`ingest/10_pipeline_config.sql`)。入库用 `is_active` 的那个,正好一个。

## 索引

- 块表开 CHANGE_TRACKING,只用增量 DML(INSERT、DELETE、MERGE)。不对块表 CREATE OR REPLACE,也不整表删了重插;否则 Cortex Search 只能全量重刷、重新算全部向量。
- Cortex Search 设 PRIMARY KEY (chunk_id),刷新时只处理变化的行;主键列必须是 TEXT(官方 ALTER CORTEX SEARCH SERVICE)。embedding 模型用 snowflake-arctic-embed-l-v2.0。
- source query 的列在建服务前一次加齐:改它的 schema 会触发全量重新 embedding。
- 块表里每篇文档的 etag 必须等于 FILE_CHANGES 里的当前版本:删除或被覆盖的旧版本不能留下块。数据检查(建议项)。
