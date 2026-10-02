# 当前需要的坑

以下实测来自既有项目记录，未在本次全部复现；其余以官方参考为准。

## 已遇到

- directory table 的 etag 本身包含双引号；传入 PARSE_FILE 时保留原值，不能手动去掉，否则会成为另一个版本键。（2026-09-29 远程核对）

- directory table / stream 的 LAST_MODIFIED 是 TIMESTAMP_TZ，写进 FILE_CHANGES 要显式转 TIMESTAMP_LTZ。（2026-09-29 实测）
- Queue 的 Message Processor 角色建 AUTO_REFRESH stage 报 403；改成队列范围的 Storage Queue Data Contributor 后通过。（2026-09-28 实测）
- 解析不要放入会重复引用的 CTE；先调用一次保存结果，再展开。（v1 实测）第三个参数 TRUE 返回顶层 value、error、metadata；页数从 metadata.pageCount 取。[官方](https://docs.snowflake.com/en/sql-reference/functions/ai_parse_document)。
- AI_COUNT_TOKENS 对当前 embedding 模型返回 NULL，使用 SNOWFLAKE.CORTEX.COUNT_TOKENS。（v1 实测）
- 表的 PRIMARY KEY 不强制唯一，chunk_id 需要自己检查。512 token 在当前基线中只是观察阈值；改进策略才强制达标。（v1 曾实测 token 上限问题）
- CREATE PROCEDURE 的 COMMENT 放在 EXECUTE AS 前；过程签名改变会留下旧重载。（既有实测）改签名先讨论，不直接 DROP。
- SET UUID_STRING 要包 SELECT 子查询；部署模板连 SQL 注释也会渲染，注释不要写未传入的 Jinja 变量。（既有部署实测）
- Git API 集成引用的 secret 必须先存在；token 换了，Snowflake secret 也要同步。（2026-09-28 实测）
- CLI 的 OAuth 连接 account 含大写曾导致 client_id 为空；执行时传小写。未开 token 缓存时每次需要浏览器登录。（2026-09-28 实测，不擅自改连接设置）

## 保留的限制

- 先建 stage（REFRESH_ON_CREATE=FALSE），再建 stream，再 REFRESH，避免已有文件漏进入库流程。已部署表只改 CREATE TABLE 不会增加列，需 ALTER。
- 自动刷新只处理支持的 BlobCreated / BlobDeleted 和 Event Grid schema；逐个删文件，不重命名、不删目录。[官方](https://docs.snowflake.com/en/user-guide/data-load-dirtables-auto-azure)。
- 一个队列只给一个通知集成，排错只 peek；ADLS stage 仍使用 blob 端点。NOTIFICATION_INTEGRATION 名字写大写。[官方](https://docs.snowflake.com/en/user-guide/data-load-dirtables-auto-azure)。
- stream 只 SELECT 不前进；保留期看 STALE_AFTER。当前 task 已建立但暂停，不能假定 stream 会被自动维护。[官方](https://docs.snowflake.com/en/user-guide/streams-intro)。
- EXECUTE IMMEDIATE FROM 中途失败，前面已执行的语句不回滚；DEPLOY_LOG 会停在 STARTED。实验 CALL 不能随部署运行。[官方](https://docs.snowflake.com/en/sql-reference/sql/execute-immediate-from)。
- 切分开启事务后出错会回滚。实测 PMC9883575.pdf 在二次切分后仍有 2 块超过 512 token；本地已改为单次切分基线和递归补切改进版，尚未部署验收。Task 尚待自动触发验收。
- Cortex Search 的 arctic-embed-l-v2.0 只有 512-token 窗口；超长基线块会截断语义向量输入，但关键词索引仍用全文。[官方](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview)。

参考文献、页眉、检索评测、正式语料和应用的细节等做到对应步骤再补。
