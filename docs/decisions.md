# 决定

记录已经定下的取舍和原因,以及"先验证"的结论。每条写明出处;没验证的标"待验证"。

## 已定的取舍

### 入库走 Event Grid → directory table → stream → task(2026-09-27)

新增、覆盖、删除都要自动处理,而且处理逻辑要能写成 SQL。Snowpipe 只把结构化文件装进表,Snowpipe Streaming 按行追加,两者都处理不了覆盖和删除。directory table 能在 Azure 事件到来时自动刷新,stream 记录它的新增和删除,task 在 stream 有数据时运行入库过程。

出处:官方 *Refresh directory tables automatically for Azure Blob Storage*(支持托管在任何云上的 Snowflake 账户;只处理 BlobCreated 和 BlobDeleted)、*Triggered tasks*(支持 directory table 上的 stream)。

### Azure 资源用 Terraform 管理(2026-09-28)

用户要求。状态文件留在本机、不进仓库,因为里面有存储账户密钥。分两个阶段 apply:第二阶段依赖 Snowflake 两个集成在 Azure 租户里 consent 之后才出现的 service principal。

### 存储账户开分层命名空间(ADLS Gen2)(2026-09-27)

用户定。代价是删目录、重命名不会同步到 Snowflake:删目录只发 DirectoryDeleted,重命名只发 BlobRenamed(Azure *Azure Blob Storage as an Event Grid source*),而 directory table 的自动刷新只处理 BlobCreated 和 BlobDeleted,重命名不触发(Snowflake 自动刷新文档)。约定:只逐个删文件,不改名。

### SQL 从 Snowflake 的 Git 仓库对象执行(2026-09-27)

用户定。全程在 Snowflake 里执行,部署时能记下提交的 sha,评测结果可以追溯到代码版本。限制:模板不能 include Git 仓库里的其它文件,嵌套执行最多 5 层(官方 *EXECUTE IMMEDIATE FROM*)。仓库放在 GitHub 私有仓库(2026-09-28 用户定)。

### 切分用官方函数,每块不超过 512 token(2026-09-27)

v1 的 8 条切分规则,MRR 只比官方切分高 0.03,算打平,块却多了 68%。v1 照官方示例用 2000 字符切,39.6% 的块超过 512 token,向量那一路被静默截断(Cortex Search 概览页建议每块不超过 512 token)。所以 v2 从官方函数起步,某条规则被评测证明有用再加。

### 标注绑定 evidence 原文片段,不绑定 chunk_id(2026-09-27)

v1 的标注绑定 chunk_id,改切分就要重新映射,有 2 题映射失败,被静默算成未命中。改成按"块是否包含 evidence"判定后,改切分不用重标。

### 块表只做增量 DML,Cortex Search 设主键(2026-09-27)

设了主键的服务,每次刷新只处理变化的行,不重新 embedding 没变的数据(官方 *ALTER CORTEX SEARCH SERVICE*)。块表被重建会让服务只能全量重刷(待验证)。

### v1 的搜索服务不需要手动挂起(2026-09-27)

核对结果:v1 的三个服务都已设 `AUTO_SUSPEND = 1800`,serving 均为 SUSPENDED,有查询时自动恢复。indexing 也不建议挂起:挂起时间超过源表的数据保留期,恢复时可能要重建服务(官方 *ALTER CORTEX SEARCH SERVICE*)。

## 先验证

### 1. AI_PARSE_DOCUMENT 能否直接读 ADLS 外部 stage 上的文件,是否必须开 directory table

- 文档怎么说:AI_PARSE_DOCUMENT 支持内部和外部 stage 上的文件;TO_FILE 用 stage 名加相对路径即可,没有要求 directory table。没有提到跨云(账户在 AWS,文件在 Azure)。
- 怎么验证:同一份 PDF,分别从不开 directory table 和开了 directory table 的两个 stage 解析;再上传一份 Content-Type 为 application/octet-stream 的副本对照。
- 判断:不开也能解析,就不需要;只有开了才能解析,就需要;都不能,按错误原文区分是权限问题还是文件类型识别问题。
- 结论:待验证。

### 2. 不设 SCHEDULE 的 triggered task 能否由 stage 上的 stream 触发

- 文档怎么说:triggered task 支持 directory table 上的 stream,要求 directory table 自动刷新或手动刷新,并给了示例(官方 *Triggered tasks*)。
- 怎么验证:在 Azure 上依次新增、覆盖、删除一个文件,不做任何手动刷新,也不 EXECUTE TASK,看 task 是否自动运行(TASK_HISTORY 的 SCHEDULED_FROM 为 TRIGGER),并记下延迟。顺带记录覆盖和删除在 stream 里是什么样子。
- 判断:30 分钟内三次都自动触发,就可用;否则逐段排查队列、directory table、stream、task,仍不行就改成 SCHEDULE + WHEN。
- 结论:待验证。

### 3. 解析 50 篇的单篇耗时和成本

- 文档怎么说:按页计费;warehouse 不超过 MEDIUM,更大也不会更快。
- 怎么验证:语料准备好后解析 50 篇,记下单篇耗时和页数,按官方单价算成本,再定语料规模(500–1000 篇)。
- 结论:待验证。
