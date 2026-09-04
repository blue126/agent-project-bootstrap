#!/usr/bin/env bash
set -euo pipefail

verdict_file=""
repository=""
pull_request=""
head_sha=""

usage() {
  cat <<'EOF'
Usage: scripts/evaluate-ai-review-gate.sh --verdict FILE --repo OWNER/REPOSITORY --pr NUMBER --sha FULL_SHA

Pass only a schema-valid structured review verdict bound to the current PR HEAD.
Comments, reactions, summaries, and provider-native approvals are not inputs.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verdict) [[ $# -ge 2 ]] || exit 2; verdict_file="$2"; shift 2 ;;
    --repo) [[ $# -ge 2 ]] || exit 2; repository="$2"; shift 2 ;;
    --pr) [[ $# -ge 2 ]] || exit 2; pull_request="$2"; shift 2 ;;
    --sha) [[ $# -ge 2 ]] || exit 2; head_sha="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${script_dir}/validate-review-verdict.sh" \
  --file "${verdict_file}" --repo "${repository}" --pr "${pull_request}" --sha "${head_sha}" >/dev/null

status="$(jq -r .status "${verdict_file}")"
case "${status}" in
  pass)
    jq -n --arg repository "${repository}" --argjson pull_request "${pull_request}" \
      --arg reviewed_sha "${head_sha}" \
      '{gate:"ai-review-gate",status:"pass",repository:$repository,
        pull_request:$pull_request,reviewed_sha:$reviewed_sha}'
    ;;
  needs_fix)
    echo "Structured review requires a fix for the current HEAD" >&2
    exit 10
    ;;
  human_required)
    echo "Structured review requires human intervention for the current HEAD" >&2
    exit 11
    ;;
  *)
    echo "Unexpected structured review status" >&2
    exit 1
    ;;
esac
