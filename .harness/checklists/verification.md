# 当前交付检查

## 本地

```sh
bash scripts/check_forbidden.sh
git diff --check
terraform -chdir=infra/azure fmt -check main.tf variables.tf outputs.tf versions.tf
terraform -chdir=infra/azure validate
```

再看 git status、部署顺序、调用方和文档链接。实验语句保留为注释；用户未填写的核心步骤仍留空。

## Snowflake

写完和运行通过分开报告。只对已实现的步骤验收：捕获后 stream 前进，解析表有结果且页数正确，重复解析返回 SKIPPED；基线切分验空块、重复 ID 和重复调用，token 超限只观察；改进版另验没有超限块。
检索服务部署后核对源行数只来自基线配置，再用 `tests/cortex_search_one_query.sql` 看能否返回文本、文件名和页码。

正式部署由用户提交推送后从 Git 仓库对象执行，核对 DEPLOY_LOG 的 sha 和 SUCCEEDED。未运行就写待验证；需要浏览器登录时等用户操作。RUN_DATA_CHECKS、RUN_EVAL 尚未实现，当前不要求执行。
