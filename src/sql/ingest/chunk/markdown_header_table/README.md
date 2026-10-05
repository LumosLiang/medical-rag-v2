# Markdown header + table

算法入口为 `CHUNK_MARKDOWN_HEADER_TABLE`，由 `CHUNK_DOC` 根据配置名分派。共享十参数接口；事务和同配置旧块替换仍由外层负责。

| 文件 | 职责 |
|---|---|
| `normalize_pages.sql` | 整篇拼接，保存规范化后的页码偏移 |
| `split_table_spans.sql` | 分开正文和表格，保留源文本位置 |
| `pack_table_rows.sql` | 按 token 预算分组，重复表名、表头和组标签 |
| `locate_chunks.sql` | overlap 定位、分级章节路径、字符范围换页码 |
| `chunk.sql` | 原生切分、计数、超限补切、写入和硬上限验收 |

Python helper 不调用 Snowflake，也不自行分词。SQL 调用原生 header splitter 和 COUNT_TOKENS，逐行计数结果再交给分组器。450 是表格软目标；1200/200、计数模型、补切尺寸与硬上限由配置提供。

无法精确定位的正文使用所属 TEXT 段页码范围。超长块的补切后代使用母块页码范围；少数超长表格兜底不保证完整重复表头。

单篇预览用 `tests/sql/checks/chunk_one_file.sql`，固定快照回填用 `scripts/sql/backfill_snapshot.sql`，只读验收用 `tests/sql/checks/verify_chunks.sql` 和 `tests/sql/checks/verify_markdown_locations.sql`。
