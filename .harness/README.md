# .harness

给 agent 和人看的简短指引,不替代 `docs/`、`setup/`、`ingest/`、`eval/`、`app/tests/`、`scripts/`。能执行的检查放在代码目录里;这里只写什么时候跑哪个检查、怎么判断。

- `context/` 写实际情况:已实现并验证、已实现待验证、计划。以代码和实测为准。
- `rules/` 写必须遵守的规则。规则可以先于实现存在;某条规则有没有落实,看 `context/current-state.md`,不要从规则反推实现。
- `checklists/` 写说"做完了"之前要跑的检查。

不放密钥、账号标识、大段日志和生成的结果。`local/` 只在本机使用,已在 `.gitignore` 里。
