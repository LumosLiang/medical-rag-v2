# 文档切分

切分将缓存的 LAYOUT 解析结果转为可检索块。不同策略共用 CORE.CHUNKS，以 config_name 区分；同一论文可以保留多套结果，评测依据原 PDF 的证据而非某个 chunk_id。

## 入口与策略

实现位于 [chunk/](../src/ingestion/sql/chunk/)。schema.sql 只定义块表；CHUNK_DOC 只负责读取配置、验证输入、按 chunk_method 分派算法，以及同版本同配置的事务替换。失败时回滚旧结果。策略只生成块及执行自身验收，不另开事务。

```text
chunk/
├── schema.sql
├── chunk_doc.sql
└── strategies/
    ├── recursive_baseline.sql
    ├── recursive_token_limited.sql
    └── structured_markdown/
        ├── chunk_document.sql       # 组织处理步骤、计数、写入
        ├── compatibility.sql        # 历史算法名的转调入口
        ├── document/                # 页规范化、去噪、摘要边界
        ├── tables/                  # 表格提取、行组装、脚注
        └── annotate_chunks.sql      # 完整章节路径与页码定位
```

算法保持统一的十参数接口，CHUNK_DOC 动态调用 CORE.CHUNK_<METHOD>，新增策略无需给入口添加分支。旧 markdown_header_table 配置仍通过兼容过程调用 CHUNK_STRUCTURED_MARKDOWN，保留搜索服务和历史实验的引用。

| 策略 / 配置 | 处理方式 | 取舍 |
|---|---|---|
| recursive_once_1200_200 | 每页 recursive 一次，默认分隔符，1200 字符 / 200 overlap；token 只记录 | 简单，但不处理跨页章节和表格结构，允许超过 512 tokens |
| recursive_resplit_to_512_tokens_1200_200 | recursive 初切，超限后递归缩小尺寸 | 保证窗口上限，但可能把语义和表格拆得更碎 |
| markdown_header_table_1200_200 | 全文标题切正文，表格按组及行切；表格软预算 450，硬上限 512 | 保留章节和表头，仍可能拆散需要多行共同支持的答案 |
| structured_markdown_8k_body_1024 | 同一结构化流程；正文目标 1024 tokens，摘要与表格尽量完整保留，模型硬上限 8192 | 更多上下文，但可能稀释精确相关性并扩大引用范围 |

参数由 [PIPELINE_CONFIG](../src/ingestion/sql/10_pipeline_config.sql) 固定。日常 active 选择与实验配置独立，当前仍使用 recursive 基线；切换配置不会自动重切历史文件或更换应用索引。

## 结构化流程

```text
解析页 → 规范化并拼接全文 → 可选去噪、摘要识别
       → TEXT / TABLE 元素 → 正文标题切分 / 摘要保留 / 表格行组装
       → 章节与页码标注 → 精确 token 计数、超限递归补切 → CHUNKS
```

**文档准备。** document/normalize_pages.sql 去掉空行及行尾空白，按物理页号拼接全文，记录每页字符范围。跨页正文因此可以共享章节；全文也成为切分与页码定位的同一坐标系。去掉空行减少原生函数改写空白造成的定位失败，代价是段落空白不再保留；原解析结果仍在 PARSED_DOCS。

启用 method_options 后，document/prepare_document.sql 依次清理明确噪声、重建页范围、识别摘要。参考文献只按 References / Bibliography / Literature Cited 边界过滤，版权和许可只过滤明确行，不按正文引用数字删文字。前三页优先选择首个 Abstract，缺失时尝试 Summary，再尝试前两页具有方法、结果和结论标签的摘要；关键词行结束摘要。document/split_abstract_spans.sql 将识别区间从正文中隔离。没有可靠边界时仍按普通正文处理，不猜测所有论文的摘要。

**正文和表格分别切分。** tables/extract_elements.sql 根据管道表头与标准分隔行提取表格，同时保留原顺序的 TEXT 段。正文使用 Snowflake 原生 SPLIT_TEXT_MARKDOWN_HEADER，按 #、##、### 及配置尺寸细切，自带 overlap；识别出的摘要不做这轮细切。

表格的 prefix 包含紧邻表名、缩写说明和表头。首列空白的开头行作为多层表头，只有首格有字的行作为组标签。tables/build_table_chunks.sql 优先保留整组；预算不够再按行拆，每块重复表名、表头和组标签。逐行 COUNT_TOKENS 相加估算预算，随后对完整块精确复核。8K 配置将表格软预算提高到 8000；tables/attach_notes.sql 只加入紧邻且格式明确的 Note / Abbreviations / 符号脚注。

例如 Results > Cardiovascular outcomes 下的 Table 2 包含 Group A 的低、高剂量死亡率，两行被拆开时，两个块仍带表名、Deaths (%) 列名和 Group A，不会只留下一个没有归属的百分比。表名即使写成 ### Table 2，也不作为正文新章节。

**标注和窗口验收。** annotate_chunks.sql 从全文标题位置恢复完整 section_path，不从每个被表格分隔的 TEXT 段重新起算；新的 h2 清除旧 h3。正文按原文子串定位，从上一块起点之后查找以允许 overlap，找不到时使用所属 TEXT 段的页码范围。表格范围包含数据行和重复组标签；8K 配置还包含表名、表头及识别到的脚注。

chunk_document.sql 对候选精确计数。超过正文目标或模型硬上限时，使用原生 recursive splitter 递归缩小尺寸；后代保留原候选的章节与页码范围。极端表格补切不保证重复完整表头。页码保持解析器的 0 起始物理页号，不能把重复前缀的合成块说成原文中的连续子串。

## 边界与结果

表格规则是结构启发式，不理解合并单元格语义；仅识别标准管道表格，不保证 HTML 或图片表格、分离或多行表名。跨页续表可能识别为两段，后半段可能缺表名；首列空白也可能是数据，组标签识别可能误判。字母脚注和缺失 References 标题尚无兜底。扩大窗口不能补回解析时丢失的内容。

method_options 控制正文目标、表格预算、摘要保留、去参考文献、出版噪声及脚注处理，旧配置为空时保持旧行为。处理模块按职责组织，8K 是配置组合而非另一套重复算法。section_path 保存在元数据中，如何参与检索见 [检索与回答](serving.md)。chunk_text_raw 仍是兼容冗余列，各策略写入与 chunk_text 相同的内容。

本轮 8K 配置已在固定 209 篇上回填，识别的 171 段摘要与 618 张表格全部单块保留；这不证明 PDF 解析准确或所有摘要均被识别。切分完整性与相关度排序分别评测，结果见 [实验报告](experiments/README.md)，运行状态见 [current-state](../.harness/context/current-state.md)。
