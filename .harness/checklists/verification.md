# 交付前检查清单

说"做完了"之前,按改动类型跑下面的检查。汇报时只写跑过的;没跑的写明"未跑"和原因。

## 所有改动

- `bash scripts/check_forbidden.sh`:仓库里没有本机路径、账户地址、密钥,也没有 Terraform 状态和变量文件。账号相关的具体值(账户标识、连接名、租户和订阅 ID、存储账户名等)写在本机的 `.harness/local/forbidden-patterns.txt`(每行一个正则,不进仓库),脚本会一起检查;CI 里可以通过 `EXTRA_FORBIDDEN_PATTERNS` secret 传入。
- `git status --short`、`git diff --check`:改动范围对,没有多余文件。
- 文档里引用的路径和文件都存在。

## Terraform(`infra/azure/`)

- `terraform fmt -check -recursive`、`terraform validate`。
- 贴出 `terraform plan` 的变更摘要。apply 要用户批准。
- plan 通过不等于资源建好了;apply 之后用 `terraform output` 和 Azure 上的实际状态核对。

## Snowflake SQL(`sql/`、`eval/`)

- 通过 Git 仓库对象从这次提交执行过(`EXECUTE IMMEDIATE FROM`),记下提交的 sha。
- 入库相关的改动:`RUN_DATA_CHECKS` 全部通过。
- 涉及检索质量的改动:`RUN_EVAL` 的 run_id 和结论。
- 写完不等于在 Snowflake 里跑过,汇报时分开说。

## 留空(`docs/hands-on.md`)

- 搭骨架的改动:`grep -rn "你来写" sql eval app scripts` 列出的空和 `docs/hands-on.md` 的清单一一对应;空都没写时部署仍能执行;调用到没写的空,抛出的是 `NOT_IMPLEMENTED`,不是别的错。
- 用户填完一个空:按它在 `docs/hands-on.md` 里的验收逐条跑,汇报跑了哪几条、结果是什么;再把表里的状态改成"完成"。

## Python(`app/`)

- CI 里的 pytest 通过。测试用假的检索和生成模块,不连 Snowflake。
- 单元测试通过不等于在 SPCS 上跑通。

## 当前基线

有引导 SQL(`sql/00`–`03`,已执行)和部署入口 `sql/deploy.sql`;还没有 Python 代码,也没有测试。CI 只有两项检查:禁止内容扫描、Terraform 格式和校验。
