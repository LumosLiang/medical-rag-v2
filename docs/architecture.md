# 架构

本文从整体到实现讲 medical-rag-v2 怎么搭。除非标明"已实现",下文描述的都是计划;逐项状态见 `.harness/context/current-state.md`,取舍和出处见 `decisions.md`。

## 1. 背景

第一版(Snowflake 库 MEDICAL_RAG)跑通了解析、切分、Cortex Search 检索和一套 50 题评测,但全部是按顺序手动执行的 SQL 文件,留下三个问题:

- 入库没有事件驱动,新增、修改、删除文档都要人工触发。
- 语料按 PMC 编号倒序选出:全是 2026 年、全是 CC BY;约 30% 不是医学期刊;集中在一家出版社。
- 标注绑定 chunk_id,一改切分就要重新映射,上次有 2 题映射失败。

第二版在新仓库、新库 MEDRAG 里重做。第一版只读保留;两版语料不同,指标不能混用。原则是尽量用 Snowflake 托管的功能:入库、切分、索引和评测用 SQL;Python 只写 FastAPI、Streamlit 和一次性的语料脚本。

## 2. 整体流程

```
PDF 新增 / 覆盖 / 删除(Azure,ADLS Gen2)
  → Event Grid → Storage Queue → Snowflake 通知集成
  → 外部 stage 的 directory table 自动刷新
  → stream:记录文件的新增和删除
  → Task:WHEN SYSTEM$STREAM_HAS_DATA
  → 入库存储过程:FILE_STATE → 解析(PARSED_DOCS)→ 切分 → 块表(CHUNKS)
  → Cortex Search:PRIMARY KEY (chunk_id),增量刷新
  → 检索模块、生成模块(AI_COMPLETE,带引用)
  → FastAPI ← Streamlit(SPCS)
```

每一层只依赖上一层的输出。Azure 只负责存文件和发事件;从 stage 开始由 Snowflake 接手,解析、切分、索引都在 Snowflake 里完成;应用只通过检索和生成两个模块接触数据。

## 3. 存储和事件(Azure)

Azure 资源全部由 `infra/azure/` 的 Terraform 管理,分两个阶段 apply:

- 第一阶段:资源组、存储账户(StorageV2 + 分层命名空间,即 ADLS Gen2)、容器、事件队列、Event Grid system topic。
- 第二阶段:Snowflake 的两个集成在 Azure 租户里完成 consent、各自的 service principal 出现之后,把两者的对象 ID 填进变量再 apply,建两条角色分配和事件订阅。事件订阅放在最后,避免队列权限就绪前往队列里堆消息。

存储集成和通知集成各有一个 service principal(官方写明两者不同)。存储这边只给 Storage Blob Data Reader:Snowflake 只需要读 PDF,不写也不删。队列这边给 Storage Queue Data Message Processor,这是官方写的最小角色。

事件订阅只投递 BlobCreated 和 BlobDeleted,并按 `data.api` 过滤成官方列出的操作:CopyBlob、PutBlob、PutBlockList、FlushWithClose、SftpCommit、DeleteBlob、DeleteFile、SftpRemove。ADLS 上建空文件的 CreateFile 被排除,只有内容提交(FlushWithClose)才算。事件格式保持 Event Grid schema,Snowflake 不支持 CloudEvents。

开了分层命名空间之后,删目录只发 DirectoryDeleted,重命名只发 BlobRenamed,Snowflake 都不处理。所以约定只逐个删文件、不改名;万一做了,手动刷新 directory table。

容器里的路径:`pdf/<PMCID>.pdf` 放语料,`manifest/` 放语料清单,`spike/` 只在先验证时用。

Terraform 状态保存在本机的 `infra/azure/terraform.tfstate`,不进仓库:状态里有存储账户密钥。存储账户名这类具体值写在同样不进仓库的 `terraform.tfvars` 里。

## 4. 入库

Snowflake 账户在 AWS 东京,文件在 Azure。官方写明,directory table 的 Azure 自动刷新支持托管在任何云上的 Snowflake 账户。

- 存储集成和通知集成(账户级对象)把 Snowflake 接到 Azure 上。
- 外部 stage 指向容器里的 `pdf/`,开 directory table 和自动刷新。
- stream 建在这个 stage 上,记录 directory table 里文件的新增和删除。
- Task 用 `WHEN SYSTEM$STREAM_HAS_DATA(...)` 触发。空闲时这个检查本身能防止 stream 过期;积压超过 14 天仍会过期,要监控 STALE_AFTER。Triggered task 12 小时没运行时,Snowflake 会安排一次健康检查(官方,时间不保证)。不设 SCHEDULE 能不能触发,是先验证的第 2 项。
- 入库过程第一步用 INSERT … SELECT 把这一批变更写进 FILE_STATE(每个文件一行:路径、etag、状态、错误、重试次数)。stream 只有被 DML 消费才会前进,只 SELECT 不算。然后逐个文件处理:
  - 新文件:解析、切分、写块。
  - 覆盖(同一路径、新 etag):删旧块,写新块。
  - 删除:删块,文档下线。
  - 失败:在 FILE_STATE 里留下错误原文,重试次数加一。Task 的 WHEN 不能查表,失败文件不会自动重试;重试方式在写入库过程时定。
- 入库过程最后调用数据检查。

## 5. 解析和切分

- 解析用 AI_PARSE_DOCUMENT 的 LAYOUT 模式,按页分割,结果存进 PARSED_DOCS。之后改切分只读这张表,不重新解析:解析按页计费,是整个流程里最贵的一步。能不能直接读 Azure 外部 stage 上的文件、要不要开 directory table,是先验证的第 1 项。
- 切分用 SQL 官方函数,分四步:
  1. 用 SPLIT_TEXT_MARKDOWN_HEADER 按 #、##、### 切。块大小从约 1200 字符起调(v1 实测散文约 2.93 字符/token)。
  2. 丢掉参考文献章节(v1 里约占 15% 的块)。每块加"标题 > 章节"前缀后进索引,原文另存一列,用来展示。
  3. 用 SNOWFLAKE.CORTEX.COUNT_TOKENS 数加了前缀之后的 token。
  4. 超过 512 token 的块用 SPLIT_TEXT_RECURSIVE_CHARACTER 再切一次。
- 进索引的每块不超过 512 token。v1 照官方示例用 2000 字符,39.6% 的块超标,向量那一路被静默截断。
- 切分逻辑只有一份,入库和评测实验共用,参数来自 PIPELINE_CONFIG 里的某个配置。

## 6. 索引

块表开 CHANGE_TRACKING,只用增量 DML 修改。Cortex Search 服务设 PRIMARY KEY (chunk_id),刷新时只处理变化的行;embedding 模型沿用 v1 的 snowflake-arctic-embed-l-v2.0。serving 设 AUTO_SUSPEND(预览功能),闲置时挂起,不产生 serving 费用。

## 7. 检索、生成和应用

- 检索模块:问题进,排好序的块出,用 snowflake.core 的 Cortex Search 接口。
- 生成模块:用 AI_COMPLETE 生成回答,标出引用的块,并检查引用确实来自这次的检索结果。
- 以后要换成 Snowflake 以外的实现时,只替换这两个模块。
- FastAPI 提供检索和生成接口;Streamlit 只通过 HTTP 调 FastAPI。两者打成一个镜像、两个启动命令,部署到 SPCS。镜像构建和推送在外部机器上做。

## 8. 部署

- Azure:`infra/azure/` 的 Terraform,在本机执行 plan,apply 前由用户批准。
- Snowflake 的引导对象在本机执行一次(snow CLI 或 IDE 连接):专用角色 MEDRAG_ADMIN 和 MEDRAG 库(`sql/00_role.sql`)、两个集成(`sql/01_integrations.sql`)、schema(`sql/02_schemas.sql`)、Git 用的 API 集成、secret 和 Git 仓库对象。MEDRAG 库和里面的对象都归 MEDRAG_ADMIN,task 按它的权限运行;只有账户级对象(集成)由 ACCOUNTADMIN 建,再把 USAGE 授给 MEDRAG_ADMIN。
- 之后的 SQL 都从 Snowflake 的 Git 仓库对象执行(`EXECUTE IMMEDIATE FROM`),部署时记下提交的 sha,评测结果引用它。存储账户名、租户 ID 这类值通过 `USING` 在执行时传入,不写进仓库。模板不能 include Git 仓库里的其它文件,所以入口脚本用嵌套的 `EXECUTE IMMEDIATE FROM` 逐个执行(官方限制:最多嵌套 5 层)。
- 代码放在 GitHub 私有仓库。

## 9. 检查(harness)

分三层:

- 代码检查,每次提交都跑。现在有两项:禁止内容扫描(本机路径、账户地址、密钥、Terraform 状态)和 Terraform 格式、校验。`app/` 有代码后加 pytest,测试用假的检索和生成模块,不连 Snowflake。本机提交前跑一次,推送后 GitHub Actions 再跑一次。
- 数据检查,每次入库后在 Snowflake 里跑(RUN_DATA_CHECKS)。有一条不过,就不往下跑评测。
- 评测,改动解析、切分或检索配置时在 Snowflake 里跑(RUN_EVAL)。步骤和判定见 `.harness/rules/eval-rules.md`。

## 10. 现在不做的

- 和 pgvector + infer-nexus 对比。以后如果做,它们在 Snowflake 外面,从块表同步数据;Snowflake 里的代码不调用它们。
- 语料筛选工程。语料准备是一次性脚本,由用户在外部机器上运行。
