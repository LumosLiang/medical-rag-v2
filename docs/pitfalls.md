# 坑

所有坑只写在这一份;代码文件头只放指向这里的指针。按后果分类,因为查坑的时候通常是先看到了某个症状。

- 【v1 实测】来自第一版(库 MEDICAL_RAG)实际运行。
- 【文档】来自官方文档,本项目还没有实测。
- 【待验证】是推断,还没有出处或实测。

## 静默失败:不报错,结果是错的

- 【v1 实测】进索引的块超过 512 token,向量那一路被截断,关键词那一路仍用全文。按官方示例 2000 字符切,39.6% 的块超标。
- 【v1 实测】AI_COUNT_TOKENS 对 embedding 模型返回 NULL,不报错。用 `SNOWFLAKE.CORTEX.COUNT_TOKENS`。
- 【v1 实测】PRIMARY KEY 不强制唯一;Cortex Search 里主键重复的行被静默忽略。每次切完都要查重复数。
- 【v1 实测】RLIKE / REGEXP_LIKE 是整串匹配,模式两头要加 `.*`。不支持 `(?s)`、`(?i)` 这类内联标志,改用第三个参数 `'s'` 和 `LOWER()`。
- 【v1 实测】检索结果里没有 `score` 字段,分量分数在 `"@scores"` 下,键要加引号;reranker 只给前约 16 条打分。
- 【v1 实测】存储过程里的嵌套游标,内层第一轮就耗尽,之后静默返回空。改成在一个游标里做叉积。
- 【v1 实测】游标定义里看不到过程参数;报错发生在 FOR 展开时,前面的 INSERT 已经提交。
- 【v1 实测】从结果表出发算指标,会丢掉一条结果都没返回的题,指标变好看。要从题目表出发。
- 【v1 实测】LAYOUT 解析会把页眉页脚插进正文句子中间(抽 20 块有 11 块)。影响关键词匹配,也影响 evidence 匹配。
- 【v1 实测】LIST 返回 No data 不代表没权限,前缀不存在也是这个结果。判断能不能读,要拿一个确定存在的文件对照。
- 【v1 实测】自己算问题向量时(比如暴力检索对照),arctic-embed-l-v2.0 的查询前缀是 `"query: "`(模型卡)。误用 v1.x 的长前缀,MRR 掉 0.21。用 Cortex Search 时由服务内部加前缀,不用管。

## 花钱的

- 【v1 实测】AI_PARSE_DOCUMENT 按页计费。不要放进 CTE:优化器会内联,函数被重复调用、重复计费(同一份 2 页文件从 10.3 秒变成 27.8 秒)。先落表再展开。
- 【v1 实测】FLATTEN 展开 pages 时不加 `OUTER => TRUE`,解析失败的文档会丢,下次又重新解析一遍。
- 【v1 实测】改 Cortex Search source query 的 schema 会触发全量重新 embedding。列要在建服务前一次加齐。
- 【v1 实测】serving 按数据量持续计费,没人查询也照收。设 `AUTO_SUSPEND`(最小 1800 秒)。
- 【待验证】对块表 CREATE OR REPLACE 会让 Cortex Search 只能全量重刷。块表只用增量 DML。

## 编译期和权限限制

- 【v1 实测】SEARCH_PREVIEW 的两个参数都必须是编译期常量,SQL UDF 包不了动态参数的检索;响应体上限 300KB。Python 里直接用 snowflake.core 的 search 接口。
- 【v1 实测】owner's rights 的存储过程里读不了 INFORMATION_SCHEMA 里和当前用户有关的信息。
- 【v1 实测】改存储过程签名要先 DROP;CREATE OR REPLACE 会留下旧的重载。
- 【v1 实测】存储过程里 SQLERRM 要写成 `:SQLERRM`;`:rec.字段` 不合法,先赋给局部变量。
- 【v1 实测】COMMENT 只能是一个字符串字面量,不能拼接。
- 【文档】Task 的 WHEN 只支持 SYSTEM$STREAM_HAS_DATA、SYSTEM$GET_PREDECESSOR_RETURN_VALUE、布尔运算和比较运算,不能查表(官方 CREATE TASK)。
- 【文档】一个 stream 只应被一个 task 消费;只 SELECT 不会让 stream 前进(官方 CREATE TASK、Introduction to streams)。
- 【文档】EXECUTE IMMEDIATE FROM 的模板访问不了 Git 仓库里的其它文件(include、import 不行);嵌套执行最多 5 层;单个文件不超过 10MB。

## Azure 和外部 stage

- 【文档】consent 之后,service principal 可能要一小时以上才出现。存储集成和通知集成是两个不同的 service principal。删掉 service principal,对应的集成就失效。
- 【文档】角色分配最多 5 分钟生效。Snowflake 会缓存临时凭据,撤权后最长 60 分钟内仍能读。
- 【文档】directory table 自动刷新只由 BlobCreated 和 BlobDeleted 触发。ADLS Gen2 上要有 FlushWithClose 才算提交,只有 CreateFile 不会刷新。重命名不触发。
- 【文档】开了分层命名空间后,删目录只发 DirectoryDeleted,重命名只发 BlobRenamed,Snowflake 都不处理:这些文件的块不会下线。
- 【文档】stage 里 NOTIFICATION_INTEGRATION 的名字必须全大写。建完 directory table 先手动 REFRESH 一次,否则要等第一条事件才有数据。
- 【文档】Snowflake 只支持 Event Grid 事件格式,不支持 CloudEvents。
- 【文档】一个 Storage Queue 只能给一个通知集成;多个集成共用一个队列会丢消息。排查时只用 peek,get 会让消息暂时不可见。
- 【文档】ADLS Gen2 也要用 blob.core.windows.net 端点;stage URL 要以 `/` 结尾。
- 【文档】azurerm provider v5 默认不自动注册资源提供程序,要在 provider 里列出用到的(本项目是 Microsoft.Storage 和 Microsoft.EventGrid)。

## 本机工具

- 【待验证】snow CLI 用 OAUTH_AUTHORIZATION_CODE 登录时,如果连接配置里的 account 含大写字母,会报 "Oauth code flow requirement 'client_id' is empty"。原因(从 connector 4.7.1 代码推断):它用 host 拼出授权地址,再把解析出的主机名(已转成小写)和 host 原样比较,大小写不一致就认为 OAuth 服务方不是 Snowflake,不用内置的 LOCAL_APPLICATION 凭据。account 改成小写,或执行时用 `--account` 传小写,应该就能走通。

## 方法论

- 【v1 实测】20 道题分不出 10 个点的差异(10 个点就是 2 道题)。同一批数据重跑,R@5 会从 0.80 变成 0.85:检索排序不完全确定。
- 【v1 实测】单标注会低估 Recall,pooling 会高估 Recall。所有配置低估的程度相同,所以配置之间的比较仍然成立。
- 【v1 实测】MRR 只需要二值标注;nDCG 才需要分级标注。
- 【v1 实测】SEARCH_PREVIEW 的延迟不是生产延迟,但两个配置走同一条路时,差值仍然可比。
- 【v1 实测】实体类、带过滤类问题对混合检索太容易,分不出配置好坏。加题往关键词和语义类上加。
