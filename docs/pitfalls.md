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
- stream 只 SELECT 不前进；保留期看 STALE_AFTER。task 暂停时不能假定 stream 会被自动维护。[官方](https://docs.snowflake.com/en/user-guide/streams-intro)。
- task 一次运行默认最多 60 分钟(USER_TASK_TIMEOUT_MS = 3600000,2026-10-02 在 INGEST_TASK 上核对)。RUN_INGEST 在一次运行里逐篇解析,实测每篇约 1–1.5 分钟,20 篇一批用了 6–30 分钟;一次传几百篇会超时,剩下的要等 stream 再有数据才处理。批量入库按批上传。
- EXECUTE IMMEDIATE FROM 中途失败，前面已执行的语句不回滚；DEPLOY_LOG 会停在 STARTED。实验 CALL 不能随部署运行。[官方](https://docs.snowflake.com/en/sql-reference/sql/execute-immediate-from)。
- 切分开启事务后出错会回滚。旧版实测 PMC9883575.pdf 在二次切分后仍有 2 块超过 512 token；单次切分基线和递归补切改进版现已部署验收。
- Cortex Search 按 TARGET_LAG 自动增量刷新(实测约每 50 分钟一次),新块最多晚一个 TARGET_LAG 才能查到;刷新记录看 INFORMATION_SCHEMA.CORTEX_SEARCH_REFRESH_HISTORY。(2026-10-02 实测)
- Cortex Search 的 arctic-embed-l-v2.0 只有 512-token 窗口；超长基线块会截断语义向量输入，但关键词索引仍用全文。[官方](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview)。

## 语料(PMC)

2026-10-02 取 200 篇时实测。

- 不要按 PMC 编号取最新:v1 这样做,500 篇全是同一年,约 30% 不是医学期刊,集中在一家出版社。按时间窗和期刊随机抽,每本期刊只取一篇。
- 不要列举 S3 桶(约 800 万个前缀):先用 eSearch 查 PMCID,再按 `PMC<号>.` 前缀取(桶里 README.txt 的做法)。按许可分的目录已经没有了,许可看每个版本的 JSON。
- 版本号大不代表该用哪个,先排除作者手稿(JSON 的 is_manuscript)。JSON 里的地址带 md5,下载后逐篇校验。
- 出版社标的文章类型不可靠:社论、病例报告、研究方案、1 页的图片栏目都会标成 research-article,要看题目、页数、有没有结果章节。
- XML 里的发表日期也可能标错(实测比卷期晚 3 年),要和 eSummary 对照。只写季节的印刷日期按 1 月 1 日算会早于电子版。
- 期刊的 NLM 学科分类和 MeSH 都挡不住"以人为对象的基础神经科学"和偶尔离题的公共卫生论文,最后要人工看题目。
- 候选集合每天在变,同一个种子隔天会抽到别的文章;以清单为准,重跑只比较不改写。
- 不带 API key 调 NCBI,间隔 0.4 秒仍会 429。eSearch 对拼错的过滤器只给警告、返回 0 条。
- 本机 az 登录身份在存储账户上没有 Blob 数据角色,`--auth-mode login` 报权限不足;上传用 `--auth-mode key`(az 用管理权限现取密钥,不落盘)。没有给账号加角色。

参考文献、页眉、检索评测和应用的细节等做到对应步骤再补。
