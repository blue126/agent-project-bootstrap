#!/usr/bin/env bash
set -euo pipefail

metadata_file=""
validation_file=""
policy_file=""

usage() {
  cat <<'EOF'
Usage: scripts/authorize-fixer-push.sh --metadata FILE --validation-result FILE --policy FILE

Fail closed unless trusted GitHub metadata, proposed commit ancestry, changed
paths, and deterministic validation all authorize one normal Fixer push.
This command never obtains a token or performs a push.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --metadata) [[ $# -ge 2 ]] || exit 2; metadata_file="$2"; shift 2 ;;
    --validation-result) [[ $# -ge 2 ]] || exit 2; validation_file="$2"; shift 2 ;;
    --policy) [[ $# -ge 2 ]] || exit 2; policy_file="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
for required_file in "${metadata_file}" "${validation_file}" "${policy_file}"; do
  [[ -f "${required_file}" ]] || { echo "Required authorization input is missing" >&2; exit 2; }
done

jq -e '
  type == "object" and
  ((keys | sort) == ([
    "actor", "allowed_actors", "api_head_sha", "changed_paths", "default_branch",
    "draft", "expected_head_sha", "fork", "head_ref", "head_repository",
    "proposed_commit_sha", "proposed_parent_sha", "pull_request", "repository", "state"
  ] | sort)) and
  (.repository | type == "string" and test("^[^/ ]+/[^/ ]+$")) and
  (.pull_request | type == "number" and floor == . and . >= 1) and
  .state == "open" and (.draft | type == "boolean") and (.fork | type == "boolean") and
  (.head_repository | type == "string") and (.actor | type == "string" and length > 0) and
  (.allowed_actors | type == "array" and all(.[]; type == "string" and length > 0)) and
  (.head_ref | type == "string" and length > 0) and (.default_branch | type == "string" and length > 0) and
  (.api_head_sha | test("^[0-9a-f]{40}$")) and (.expected_head_sha | test("^[0-9a-f]{40}$")) and
  (.proposed_commit_sha | test("^[0-9a-f]{40}$")) and (.proposed_parent_sha | test("^[0-9a-f]{40}$")) and
  (.changed_paths | type == "array" and length > 0 and all(.[];
    type == "string" and length > 0 and (startswith("/") | not) and
    (split("/") | all(. != ".." and . != "." and . != ""))))
' "${metadata_file}" >/dev/null || { echo "Invalid Fixer authorization metadata" >&2; exit 1; }

repository="$(jq -r .repository "${metadata_file}")"
pull_request="$(jq -r .pull_request "${metadata_file}")"
proposed_sha="$(jq -r .proposed_commit_sha "${metadata_file}")"

jq -e \
  --arg repository "${repository}" \
  --argjson pull_request "${pull_request}" \
  --arg proposed_sha "${proposed_sha}" '
  .repository == $repository and .pull_request == $pull_request and
  .validated_sha == $proposed_sha and .status == "pass"
' "${validation_file}" >/dev/null || { echo "Validation result does not authorize the proposed commit" >&2; exit 1; }

jq -e '
  .actor as $actor |
  .draft == false and .fork == false and .head_repository == .repository and
  (.allowed_actors | index($actor)) != null and
  .head_ref != .default_branch and
  .api_head_sha == .expected_head_sha and
  .proposed_parent_sha == .api_head_sha and
  .proposed_commit_sha != .api_head_sha
' "${metadata_file}" >/dev/null || { echo "Fixer push identity, PR state, branch, or ancestry check failed" >&2; exit 1; }

if jq -r '.changed_paths[]' "${metadata_file}" |
  "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/classify-sensitive-paths.sh" --policy "${policy_file}" >/dev/null; then
  echo "Fixer push touches governance-sensitive paths" >&2
  exit 1
else
  classifier_status=$?
  [[ "${classifier_status}" == 1 ]] || exit "${classifier_status}"
fi

jq -n \
  --arg repository "${repository}" \
  --argjson pull_request "${pull_request}" \
  --arg expected_head_sha "$(jq -r .expected_head_sha "${metadata_file}")" \
  --arg proposed_commit_sha "${proposed_sha}" \
  '{authorized:true, repository:$repository, pull_request:$pull_request,
    expected_head_sha:$expected_head_sha, proposed_commit_sha:$proposed_commit_sha,
    push_mode:"normal-fast-forward"}'
