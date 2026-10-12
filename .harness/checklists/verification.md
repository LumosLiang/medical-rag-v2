# 交付检查

## 本地

```sh
.venv/bin/python -m pytest
bash .github/scripts/check_forbidden.sh
git diff --check
```

目录或部署变化时核对包路径、Docker COPY、嵌套 SQL 路径、文档链接及直接调用方。改嵌入 Python 的算法时检查 handler 语法。Azure 代码变化才运行 Terraform fmt / validate。

## 入库与切分

- Stream 捕获后推进，FILE_CHANGES 保存动作与文件版本；Task 状态与逐文件 DONE / FAILED 分别检查。
- 成功解析版本重复调用为 SKIPPED；active 必须恰好一条，歧义在消费 Stream 前拒绝。
- tests/snowflake/chunk_one_file.sql 在临时表验收同篇重跑；tests/snowflake/verify_chunks.sql 核对缺文档、版本、页码、空块、重复 ID 和 token。
- 基线超限只观察；限窗策略不得超限。正文定位失败采用所属段范围，不伪装精确页码。跨页、表头、组标签、转义管道和章节继承分别核对。

## 搜索、应用与评测

- tests/snowflake/verify_search_service.sql 检查源配置、服务 ACTIVE、行数及实际返回。索引刷新完成再跑实验。
- /search 返回原文及来源；/ask 返回有效引用，非法编号与缺引用的正常回答被拒绝。编号正确不等于事实正确。
- SPCS 容器 READY；以实际服务身份请求 /search、/ask，核对公开端点认证。前端会话展示和模型上下文分别验收。
- 同一冻结题集、文件版本与评分规则比较，用新实验 ID 保存 top-k 与参数；零返回题保留，未完成实验排除。
- 核对单块上限与排序损失，不把 Hit@k 称为标准 Recall@k。重复请求有波动时同时报告，不挑选高分作为稳定结果。

## 发布边界

Git FETCH 只更新仓库副本，EXECUTE IMMEDIATE FROM 才执行指定版本。SQL 发布、评测工具与 SPCS 分开；不再依赖 DEPLOY_LOG。初始化或权限调整先确认；不擅自改 owner、重建表、重建索引或修改冻结题集。

本地通过、云端执行与全库回填分别记录。没有运行的入口明确写待验收，不能用模块历史成功代替新入口已通过。
