# 测试与验收

本地测试验证代码行为，Snowflake SQL 验证实际数据与服务状态。检索质量对照位于独立的 [eval](../eval/README.md)，不混入单元测试。

| 位置 | 验证内容 |
|---|---|
| `ingestion/` | 表格边界、重复上下文、章节继承及位置标注的回归 |
| `serving/` | API 输入、检索映射、生成结果与引用错误处理 |
| `../eval/tests/` | 完成状态与零返回题的指标分母 |
| `snowflake/` | 单篇切分、全库块校验、定位统计与搜索服务检查 |

```sh
.venv/bin/python -m pytest
```

pytest 不连接 Azure 或 Snowflake。嵌入 Python handler 的检查不代替 Snowflake 原生函数运行验收；SQLite 指标测试只验证基础查询，不验证 Snowflake 的完整视图语法。

`chunk_one_file.sql` 将结果写入会话临时表，便于逐块查看，不替换生产 CHUNKS。其他 SQL 为只读检查，执行前选择配置与快照。基线允许超过 512 token；限窗策略要求没有超限块。单篇检查看页码、章节、完整原文及重复调用结果；全库检查看文件版本、缺文档、空块、重复 ID 和 token 分布。

这些测试覆盖已发生过的实质错误，目录整理保留其行为，不通过删测试减少表面复杂度。
