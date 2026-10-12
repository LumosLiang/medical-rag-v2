#!/usr/bin/env bash
# 提交前检查:仓库里不能出现本机路径、账户地址、密钥,也不能跟踪 Terraform 状态、变量和 plan 文件。
#
# 账号相关的具体值(账户标识、连接名、租户和订阅 ID、存储账户名等)不能写进本脚本,
# 否则脚本自己就把它们带进了仓库。这些值按每行一个正则写在:
#   - 本机:.harness/local/forbidden-patterns.txt(已在 .gitignore 里)
#   - CI:secret EXTRA_FORBIDDEN_PATTERNS
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

patterns_file="$(mktemp)"
trap 'rm -f "$patterns_file"' EXIT

cat >"$patterns_file" <<'EOF'
/Users/[A-Za-z0-9._-]+
/home/[A-Za-z0-9._-]+/
[A-Za-z0-9-]+\.snowflakecomputing\.com
-----BEGIN [A-Z ]*PRIVATE KEY-----
AccountKey=[A-Za-z0-9+/=]{20,}
SharedAccessSignature=
[?&]sig=[A-Za-z0-9%+/=]{20,}
gh[pousr]_[A-Za-z0-9]{30,}
github_pat_[A-Za-z0-9_]{30,}
EOF

if [[ -f .harness/local/forbidden-patterns.txt ]]; then
  grep -v -e '^[[:space:]]*$' -e '^#' .harness/local/forbidden-patterns.txt >>"$patterns_file" || true
fi
if [[ -n "${EXTRA_FORBIDDEN_PATTERNS:-}" ]]; then
  printf '%s\n' "$EXTRA_FORBIDDEN_PATTERNS" | grep -v -e '^[[:space:]]*$' >>"$patterns_file" || true
fi

# 先确认规则本身合法:对空输入,grep 返回 1 表示正则没问题,返回 2 表示正则有错。
# 不先查的话,一条写错的规则会让下面的扫描静默通过。
set +e
grep -iE -f "$patterns_file" /dev/null >/dev/null
rc=$?
set -e
if [[ "$rc" -eq 2 ]]; then
  echo "检查规则里有无效的正则。" >&2
  exit 2
fi

status=0

# 已跟踪的文件,加上还没跟踪、也没被忽略的文件,也就是下一次提交会带上的内容。
matches="$(git ls-files -z -co --exclude-standard -- . ':(exclude).github/scripts/check_forbidden.sh' \
  | while IFS= read -r -d '' file; do
      if [[ -f "$file" ]]; then
        grep -nIiE -f "$patterns_file" -- "$file" || true
      fi
    done)"
if [[ -n "$matches" ]]; then
  printf '%s\n' "$matches"
  echo "上面这些行含有不该进仓库的内容。" >&2
  status=1
fi

state_files="$(git ls-files -co --exclude-standard | grep -E '(\.tfstate(\..*)?|\.tfvars|\.tfplan)$' || true)"
if [[ -n "$state_files" ]]; then
  printf '%s\n' "$state_files"
  echo "Terraform 状态、变量或 plan 文件不能进仓库。" >&2
  status=1
fi

if [[ "$status" -eq 0 ]]; then
  echo "check_forbidden: 通过"
fi
exit "$status"
