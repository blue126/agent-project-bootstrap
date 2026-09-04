#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT
sha="0123456789abcdef0123456789abcdef01234567"
verdict="${test_root}/verdict.json"

write_verdict() {
  jq -n --arg sha "${sha}" --arg status "$1" --argjson findings "$2" '{
    repository:"acme/project",pull_request:12,reviewed_sha:$sha,
    status:$status,findings:$findings
  }' > "${verdict}"
}

write_verdict pass '[]'
result="$("${repo_root}/scripts/evaluate-ai-review-gate.sh" \
  --verdict "${verdict}" --repo acme/project --pr 12 --sha "${sha}")"
test "$(jq -r .status <<<"${result}")" = pass
test "$(jq -r .gate <<<"${result}")" = ai-review-gate

blocking='[{"fingerprint":"fp-1","severity":"blocking","actionable":true,"path":"src/file","summary":"fix"}]'
write_verdict needs_fix "${blocking}"
set +e
"${repo_root}/scripts/evaluate-ai-review-gate.sh" \
  --verdict "${verdict}" --repo acme/project --pr 12 --sha "${sha}" >/dev/null 2>&1
status=$?
set -e
test "${status}" = 10

write_verdict human_required "${blocking}"
set +e
"${repo_root}/scripts/evaluate-ai-review-gate.sh" \
  --verdict "${verdict}" --repo acme/project --pr 12 --sha "${sha}" >/dev/null 2>&1
status=$?
set -e
test "${status}" = 11

write_verdict pass '[]'
if "${repo_root}/scripts/evaluate-ai-review-gate.sh" \
  --verdict "${verdict}" --repo acme/project --pr 12 \
  --sha 89abcdef0123456789abcdef0123456789abcdef >/dev/null 2>&1; then
  echo "ai-review-gate unexpectedly accepted a stale verdict" >&2
  exit 1
fi

echo "ai-review-gate tests passed"
