#!/usr/bin/env bash
set -euo pipefail

verdict_file=""
repository=""
pull_request=""
reviewed_sha=""

usage() {
  cat <<'EOF'
Usage: scripts/validate-review-verdict.sh --file FILE --repo OWNER/REPOSITORY --pr NUMBER --sha FULL_SHA

Validate a provider-neutral structured review verdict and bind it to one PR HEAD.
Natural-language comments and summaries are not accepted as gate input.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) [[ $# -ge 2 ]] || exit 2; verdict_file="$2"; shift 2 ;;
    --repo) [[ $# -ge 2 ]] || exit 2; repository="$2"; shift 2 ;;
    --pr) [[ $# -ge 2 ]] || exit 2; pull_request="$2"; shift 2 ;;
    --sha) [[ $# -ge 2 ]] || exit 2; reviewed_sha="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[[ -f "${verdict_file}" ]] || { echo "Verdict file does not exist" >&2; exit 2; }
[[ "${repository}" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || { echo "Invalid repository" >&2; exit 2; }
[[ "${pull_request}" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid pull request number" >&2; exit 2; }
[[ "${reviewed_sha}" =~ ^[0-9a-f]{40}$ ]] || { echo "A full lowercase commit SHA is required" >&2; exit 2; }

jq -e \
  --arg repository "${repository}" \
  --argjson pull_request "${pull_request}" \
  --arg reviewed_sha "${reviewed_sha}" '
  type == "object" and
  ((keys | sort) == (["findings", "pull_request", "repository", "reviewed_sha", "status"] | sort)) and
  .repository == $repository and
  .pull_request == $pull_request and
  .reviewed_sha == $reviewed_sha and
  (.status == "pass" or .status == "needs_fix" or .status == "human_required") and
  (.findings | type == "array") and
  (all(.findings[];
    type == "object" and
    ((keys | sort) == (["actionable", "fingerprint", "path", "severity", "summary"] | sort)) and
    (.fingerprint | type == "string" and length > 0 and length <= 256) and
    (.severity == "blocking" or .severity == "non_blocking") and
    (.actionable | type == "boolean") and
    (.path | type == "string" and length > 0 and
      (startswith("/") | not) and
      (split("/") | all(. != ".." and . != "." and . != ""))) and
    (.summary | type == "string" and length > 0 and length <= 2000)
  )) and
  ([.findings[].fingerprint] | length == (unique | length)) and
  (if .status == "pass" then
     all(.findings[]; .severity != "blocking")
   elif .status == "needs_fix" then
     any(.findings[]; .severity == "blocking" and .actionable == true)
   else true end)
' "${verdict_file}" >/dev/null || {
  echo "Verdict is invalid or does not match the requested repository, PR, and SHA" >&2
  exit 1
}

echo "Validated structured review verdict for ${repository}#${pull_request}@${reviewed_sha}"
