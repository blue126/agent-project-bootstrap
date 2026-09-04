#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT
state="${test_root}/threads.json"

cat > "${state}" <<'EOF'
{
  "active_fingerprints": ["still-active"],
  "threads": [
    {"id":"bot-gone","owner":"bot","fingerprint":"gone","resolved":false},
    {"id":"bot-active","owner":"bot","fingerprint":"still-active","resolved":false},
    {"id":"bot-done","owner":"bot","fingerprint":"old","resolved":true},
    {"id":"human-gone","owner":"human","fingerprint":"gone","resolved":false}
  ]
}
EOF
result="$("${repo_root}/scripts/select-resolvable-bot-threads.sh" --state "${state}")"
test "$(jq -r '.resolvable_thread_ids | length' <<<"${result}")" = 1
test "$(jq -r '.resolvable_thread_ids[0]' <<<"${result}")" = bot-gone
test "$(jq -r .human_threads_touched <<<"${result}")" = false
if jq -e '.resolvable_thread_ids | index("human-gone") != null' <<<"${result}" >/dev/null; then
  echo "human thread was unexpectedly selected for automatic resolution" >&2
  exit 1
fi

echo "thread resolution tests passed"
