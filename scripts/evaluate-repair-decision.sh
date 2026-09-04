#!/usr/bin/env bash
set -euo pipefail

state_file=""
max_rounds=3

usage() {
  cat <<'EOF'
Usage: scripts/evaluate-repair-decision.sh --state FILE [--max-rounds 1|2|3]

Return a deterministic fix_allowed or human_required JSON decision. This tool
does not invoke a model, obtain credentials, modify a repository, or push.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state) [[ $# -ge 2 ]] || exit 2; state_file="$2"; shift 2 ;;
    --max-rounds) [[ $# -ge 2 ]] || exit 2; max_rounds="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[[ -f "${state_file}" ]] || { echo "Decision state file does not exist" >&2; exit 2; }
[[ "${max_rounds}" =~ ^[123]$ ]] || { echo "--max-rounds must be 1, 2, or 3" >&2; exit 2; }

jq -e '
  type == "object" and
  ((keys | sort) == ([
    "ambiguous", "architectural", "conflict", "findings", "permission_ok",
    "previous_fingerprints", "round", "sensitive", "validation_passed"
  ] | sort)) and
  (.round | type == "number" and floor == . and . >= 0) and
  (.previous_fingerprints | type == "array" and all(.[]; type == "string" and length > 0)) and
  ([.previous_fingerprints[]] | length == (unique | length)) and
  (.findings | type == "array" and all(.[];
    type == "object" and
    ((keys | sort) == (["actionable", "fingerprint", "severity"] | sort)) and
    (.fingerprint | type == "string" and length > 0) and
    (.severity == "blocking" or .severity == "non_blocking") and
    (.actionable | type == "boolean")
  )) and
  (.validation_passed | type == "boolean") and
  (.permission_ok | type == "boolean") and
  (.conflict | type == "boolean") and
  (.sensitive | type == "boolean") and
  (.ambiguous | type == "boolean") and
  (.architectural | type == "boolean")
' "${state_file}" >/dev/null || { echo "Invalid repair decision state" >&2; exit 1; }

decision="fix_allowed"
reason="actionable_blocking_findings"
round="$(jq -r '.round' "${state_file}")"

if [[ "$(jq -r '.sensitive' "${state_file}")" == true ]]; then decision=human_required; reason=sensitive_path
elif [[ "$(jq -r '.permission_ok' "${state_file}")" != true ]]; then decision=human_required; reason=permission_failure
elif [[ "$(jq -r '.validation_passed' "${state_file}")" != true ]]; then decision=human_required; reason=validation_failure
elif [[ "$(jq -r '.conflict' "${state_file}")" == true ]]; then decision=human_required; reason=conflict
elif [[ "$(jq -r '.ambiguous' "${state_file}")" == true ]]; then decision=human_required; reason=ambiguous_finding
elif [[ "$(jq -r '.architectural' "${state_file}")" == true ]]; then decision=human_required; reason=architectural_finding
elif (( round >= max_rounds )); then decision=human_required; reason=max_rounds_reached
elif jq -e '[.findings[].fingerprint] as $current | any(.previous_fingerprints[]; . as $old | $current | index($old))' "${state_file}" >/dev/null; then
  decision=human_required; reason=repeated_fingerprint
elif ! jq -e 'any(.findings[]; .severity == "blocking" and .actionable == true)' "${state_file}" >/dev/null; then
  decision=human_required; reason=no_actionable_blocking_finding
fi

jq -n \
  --arg status "${decision}" \
  --arg reason "${reason}" \
  --argjson current_round "${round}" \
  --argjson next_round "$((round + 1))" \
  '{status: $status, reason: $reason, current_round: $current_round,
    next_round: (if $status == "fix_allowed" then $next_round else null end)}'
