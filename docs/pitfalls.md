# 运行约束与排错

这里记录会影响执行的接口与已遇到的故障；设计原因见 [architecture](architecture.md)，命令见 [deployment](deployment.md)。既有实测未在本次全部复现。

## 事件与文件版本

| 情况 | 原因与处理 |
|---|---|
| stage 有文件而 stream 没有初始文件 | stream 不补记创建前的变化；首次以 REFRESH_ON_CREATE=FALSE 建 stage，建 stream 后 REFRESH |
| etag 相同文件却被当成另一版本 | DIRECTORY 的 etag 含双引号，参数需保留原值 |
| LAST_MODIFIED 写表类型不符 | directory/stream 是 TIMESTAMP_TZ，FILE_CHANGES 显式转 TIMESTAMP_LTZ |
| AUTO_REFRESH 报 403 | 既有实测使用队列范围 Storage Queue Data Contributor 后通过；权限由初始化管理 |
| 文件重命名或目录删除未触发预期入库 | 当前支持 BlobCreated/BlobDeleted 的 Event Grid schema；使用逐个文件操作 |
| 队列消息被其他程序取走 | 队列仅供通知集成消费；排错使用 peek |

ADLS stage 使用 blob 端点；Storage Queue 可以与 PDF 同存储账户，也可以独立配置，stage 不直接根据队列账户访问 PDF。通知集成名使用大写。[官方流程](https://docs.snowflake.com/en/user-guide/data-load-dirtables-auto-azure)。

## 处理与计算

| 情况 | 原因与处理 |
|---|---|
| 上传后迟迟没处理 | 核对 directory、stream、task 状态和 FILE_CHANGES；只 SELECT stream 不消费它 |
| task 暂停后恢复仍异常 | stream 保留期查 STALE_AFTER，不把固定天数当成保证 |
| 大批入库超时 | 已验收任务时限 60 分钟，逐篇解析可能较慢；既有 20 篇/批运行约 6–30 分钟 |
| 切分失败 | CHUNK_DOC 的同配置删写回滚；FILE_CHANGES 留 FAILED，当前不自动重试 |
| 多个 active 配置 | RUN_INGEST 拒绝歧义，不能用 MAX(config_name) 当作最新 |
| 解析或出题被重复调用 | 有外部 AI 调用的结果先落变量/临时表，再展开或引用；避免重复执行表达式 |
| token 计数为 NULL | 当前 embedding 模型使用 SNOWFLAKE.CORTEX.COUNT_TOKENS；既有 AI_COUNT_TOKENS 路径曾返回 NULL |
| 修改 parse_mode 后仍返回 SKIPPED | 成功解析缓存目前只按文件版本，不支持解析策略版本隔离 |

覆盖时先删旧版本，若新版本失败则文档暂时不可检索。每日 active 与实验回填不同；手工回填模板为 5 篇/批，避免既有 180 秒会话超时。参数和运行结果分别记录，不推断未完成验收。

## 搜索与评测

TARGET_LAG 是索引刷新目标，块写入不代表马上可以查到；核对 CORTEX_SEARCH_REFRESH_HISTORY 和服务行数。当前服务使用 1 小时目标，既有实测约 50 分钟增量刷新。[官方 Cortex Search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview)。

当前 embedding 模型窗口为 512 token；超长基线文本的向量输入截断，关键词仍使用全文。标题前缀还占用窗口，因此与章节关键词 multi-index 的取舍不同。

标准表 PRIMARY KEY 不强制唯一，批量工具串行执行并检查 ID。EVAL 部分旧对象仍属 ACCOUNTADMIN，MEDRAG_ADMIN 不可见；运行评测模板暂用 ACCOUNTADMIN，不自行变更 owner。覆盖评分的数学符号/组别限制与文件版本问题见 [eval](../eval/README.md)。

## 部署与认证

已存在表增加列使用 ALTER，CREATE IF NOT EXISTS 不会修改原表。更新同签名过程不会删除旧重载；本项目保留兼容入口，不直接 DROP。CREATE PROCEDURE 的 COMMENT 放在 EXECUTE AS 前。

Git 模块中途失败时前面已执行的语句不回滚，DEPLOY_LOG 保持 STARTED。手工回填、实验 CALL 和用户学习语句不随部署执行。Jinja 会渲染注释中的模板表达式，只有已传参数可以使用。

连接、token、secret 与账号配置留在本机。Git 集成引用的 secret 先存在，token 轮换时同步 secret；浏览器连接无缓存时可能重复授权。既有 CLI OAuth account 大写导致 client_id 为空的故障通过小写参数解决，不能因此猜测所有认证问题的原因。

## 语料来源

PMC 候选集合每天变化，同种子不保证不同日期抽样一致；来源和筛选依据以 manifest 为准。期刊分类、许可、版本、撤稿状态和文章类型需要核对，出版社标注不能替代人工看题目。下载时校验文件 md5；大版本号不一定应优先于出版版。

下载与检查工具使用 eSearch 找 PMCID，再读取公开 S3 文件，而不遍历整个桶；临床属性、发表日期、页数与出版集团分布均有检查。NCBI 无 API key 时需要限速，错误的过滤器可能只给警告。工具用法见 [本机工具说明](deployment.md#本机辅助工具)，PDF 保留供证据复核。
