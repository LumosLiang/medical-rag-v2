# 架构与设计取舍

项目面向以 PDF 为主、包含标题和表格的医学论文。PDF 保留在 Azure；Snowflake 保存解析结果、不同策略的块及检索索引。目标是文件变化自动进入检索，再通过前后端给出带证据引用的回答。事件入库已验证，检索与带引用回答已在 SPCS 服务身份下通过验收。当前入库 active 与应用索引配置独立，固定语料问答已贯通；新增文件尚不会自动进入应用所选索引。

## 事件如何变成可检索文档

```text
ADLS Gen2 中 PDF 新增 / 覆盖 / 删除
  → Event Grid → Storage Queue → Snowflake notification integration
  → stage directory table 自动刷新 → stream → task → RUN_INGEST
  → FILE_CHANGES → 解析 / 删除旧块 / 切分 → CHUNKS → Cortex Search
  → FastAPI → Streamlit 的答案与引用
```

storage integration 授权 Snowflake 读取 PDF；notification integration 授权读取事件队列。directory table 保存文件元数据，stream 记录其净变化，业务 SQL 不直接消费 Storage Queue。采用这条链路可以让对象存储与下游处理分离，文件不必再复制到 Snowflake 内部 stage。[官方 Azure 自动刷新流程](https://docs.snowflake.com/en/user-guide/data-load-dirtables-auto-azure)。

stream 是两次消费之间的净变化：已登记版本被覆盖时是一删一增；同一区间新增再删除可能没有行。CAPTURE_CHANGES 用 INSERT SELECT 消费这些变化并持久化，避免后续处理依赖 stream 重读。文件版本以 `(relative_path, etag)` 标识，batch_id 只标识一次捕获。

## 入库各步骤的边界

| 步骤 | 输入 → 输出 | 负责什么 |
|---|---|---|
| 捕获 | stream → PENDING | 保存变化，不决定处理策略 |
| 分类 | PENDING → TO_PARSE / TO_REMOVE | 根据 INSERT / DELETE 分配动作 |
| 删除 | TO_REMOVE → DONE | 删除该文件版本在所有配置下的旧块 |
| 解析 | 文件版本 → PARSED_DOCS | 保存一次 AI_PARSE_DOCUMENT 原始结果 |
| 切分 | 解析结果 + 配置 → CHUNKS | 不同策略共存，事务替换同版本同配置 |
| 协调 | TO_PARSE → DONE / FAILED | 逐文件调用解析和切分，记录失败并继续 |

日常入库必须且只能有一个 active 配置，不按名字或创建时间猜“最新”。实验显式指定配置，切换 active 不会自动重切历史文件或更换搜索服务。配置参数按名称固定；新参数建立新配置。配置初始化只在没有 active 时选择基线，不在每次部署时覆盖运行选择。

各步骤分开提交，便于独立处理和排错；CHUNK_DOC 内部的删旧块与写新块处于同一事务。取舍是覆盖文件时先删旧版本，新版本解析失败会暂时不可检索；失败行当前不自动重试，任务由新 stream 变化触发。

## 为什么选择 LAYOUT

AI_PARSE_DOCUMENT 的 OCR 模式只提取文字，LAYOUT 同时提取布局和结构内容，并返回 Markdown。这里需要按标题切正文、让表头和数值保持关联，因此选择 LAYOUT；page_split 保留 0 起始物理页号，后续仍可拼接全文解决跨页切分。[官方模式定义](https://docs.snowflake.com/en/sql-reference/functions/ai_parse_document)。

取舍是依赖模型恢复的 Markdown：标题层级可能不准，复杂表格、脚注或数学符号仍可能解析错误。LAYOUT 不等于保留完整 PDF 版式，也不代表理解图片内容；当前没有启用图片提取或图像问答。若任务只需要普通文字而不需要结构，OCR 可以作为更简单的输出；本项目没有做 OCR / LAYOUT 的成本和质量对照，不能宣称哪一个普遍更优。

PARSED_DOCS 让切分实验复用同一次解析。当前成功缓存只按文件版本判断，换 parse_mode 不会自动重新解析；公平比较解析策略还需要独立的解析版本设计。

## 切分与检索解耦

所有策略写入 CORE.CHUNKS，以 config_name 区分，chunk_id 由文件版本、配置与块序号生成。chunk/schema.sql 定义块表，chunk_doc.sql 中的 CHUNK_DOC 负责输入检查、动态分派和事务；strategies/ 中的算法只负责生成块及策略自己的验收，不把算法分支堆进入口。

基线逐页 recursive 一次，1200 字符、200 overlap、Snowflake 默认分隔符，token_count 仅观察；它简单可复现，但跨页证据或表格可能被切散。补切版在超过 512 token 时递归缩小尺寸，满足模型窗口，代价是更碎的块。章节表格策略拼接全文、分开正文和表格，尽量保住标题及数值归属，但仍受复杂表格启发式与窗口大小限制。长窗口实验配置复用该流程，正文目标 1024 tokens，摘要/表格允许到 8192 tokens，另加保守的参考文献与出版噪声过滤；处理选项存于 method_options，旧配置保持原行为。流程、取舍和边界统一见 [切分策略](chunking.md)。

当前 chunk_text_raw 是为既有表结构保留的冗余列，各算法写入与 chunk_text 相同的内容；展示、评测及检索统一读取 chunk_text。检索专用标题前缀在服务源查询中生成，不写回这两个字段。

Cortex Search 的原有四套索引分别比较基线、章节正文、标题前缀和章节 multi-index；8K 实验另建旧块模型对照和长窗口配置服务。服务决定哪些字段进入关键词/向量索引；请求决定查询权重和重排强度。切分配置、索引配置与请求配置是三个不同因素。详见 [检索配置](serving.md)，历史结果见 [实验记录](experiments/README.md)。

## 评测与应用

题集依据原始 PDF、文件哈希、页码和证据建立，不依赖 chunk_id；固定同一套问题比较不同策略，避免某一种切法定义正确答案。题集构建与检索实验独立，流程和评分边界见 [eval](../eval/README.md)。当前评测是单块证据覆盖，不是生成答案质量，也不代表多块合并后的上下文质量。

前端只通过 HTTP 请求后端，不直接连接 Snowflake。后端连接层只管理连接；检索与生成分别调用 Cortex Search 和 AI_COMPLETE，`/ask` 路由串起完整请求链路，prompts.py 构造证据提示，citations.py 校验逐条结论的来源编号与摘录后生成回答标记。前端展示结论与原句的对应关系。校验只证明摘录来自检索块，不证明结论受支持；证据不足也不允许绕过已输出事实的校验。应用默认使用最佳历史 multi-index 服务及请求权重，独立于入库 active 配置。前端 context_management.py 在 session_state 中保留最近 20 轮问答及各轮引用，提供最近 5 轮的文本窗口和清空操作；当前不把历史对话送给模型，问题改写与 token 预算尚未实现。SPCS 只公开前端，由 Snowflake 认证；后端使用挂载 OAuth token，以服务所有者角色访问同一语料，尚无用户级文档权限设计。

`src/ingestion/` 放入库，`src/serving/` 放搜索和应用，`eval/` 放评测；Python 包名保持 medical_rag。基础设施、部署、工具与测试独立。部署方式见 [deployment](deployment.md)，主要工程问题及解决路径见 [challenges](challenges.md)。
