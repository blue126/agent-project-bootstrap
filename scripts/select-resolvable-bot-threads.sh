#!/usr/bin/env bash
set -euo pipefail

state_file=""
usage() {
  cat <<'EOF'
Usage: scripts/select-resolvable-bot-threads.sh --state FILE

Return unresolved bot-owned thread IDs only when their finding fingerprint is
no longer active. Human-owned threads are never returned or modified.
EOF
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --state) [[ $# -ge 2 ]] || exit 2; state_file="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[[ -f "${state_file}" ]] || { echo "Thread state file does not exist" >&2; exit 2; }

jq -e '
  type == "object" and ((keys | sort) == (["active_fingerprints", "threads"] | sort)) and
  (.active_fingerprints | type == "array" and all(.[]; type == "string" and length > 0)) and
  ([.active_fingerprints[]] | length == (unique | length)) and
  (.threads | type == "array" and all(.[];
    type == "object" and ((keys | sort) == (["fingerprint", "id", "owner", "resolved"] | sort)) and
    (.id | type == "string" and length > 0) and
    (.owner == "bot" or .owner == "human") and
    (.fingerprint | type == "string" and length > 0) and
    (.resolved | type == "boolean"))) and
  ([.threads[].id] | length == (unique | length))
' "${state_file}" >/dev/null || { echo "Invalid review thread state" >&2; exit 1; }

jq '{
  resolvable_thread_ids: [
    .active_fingerprints as $active |
    .threads[] |
    .fingerprint as $fingerprint |
    select(.owner == "bot" and .resolved == false and ($active | index($fingerprint)) == null) |
    .id
  ],
  human_threads_touched: false
}' "${state_file}"
