#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT
state="${test_root}/state.json"

write_state() {
  jq -n \
    --argjson round "${1}" \
    --argjson previous "${2}" \
    --argjson findings "${3}" \
    --argjson validation_passed "${4}" \
    --argjson permission_ok "${5}" \
    --argjson conflict "${6}" \
    --argjson sensitive "${7}" \
    --argjson ambiguous "${8}" \
    --argjson architectural "${9}" \
    '{round:$round, previous_fingerprints:$previous, findings:$findings,
      validation_passed:$validation_passed, permission_ok:$permission_ok,
      conflict:$conflict, sensitive:$sensitive, ambiguous:$ambiguous,
      architectural:$architectural}' > "${state}"
}

finding='[{"fingerprint":"fp-1","severity":"blocking","actionable":true}]'
write_state 0 '[]' "${finding}" true true false false false false
result="$("${repo_root}/scripts/evaluate-repair-decision.sh" --state "${state}")"
test "$(jq -r .status <<<"${result}")" = fix_allowed
test "$(jq -r .next_round <<<"${result}")" = 1

# First rollout permits only one round.
write_state 1 '[]' "${finding}" true true false false false false
result="$("${repo_root}/scripts/evaluate-repair-decision.sh" --state "${state}" --max-rounds 1)"
test "$(jq -r .reason <<<"${result}")" = max_rounds_reached

# Repeated fingerprints stop before the global three-round ceiling.
write_state 1 '["fp-1"]' "${finding}" true true false false false false
result="$("${repo_root}/scripts/evaluate-repair-decision.sh" --state "${state}")"
test "$(jq -r .reason <<<"${result}")" = repeated_fingerprint

for field_reason in \
  'validation_passed:false:validation_failure' \
  'permission_ok:false:permission_failure' \
  'conflict:true:conflict' \
  'sensitive:true:sensitive_path' \
  'ambiguous:true:ambiguous_finding' \
  'architectural:true:architectural_finding'; do
  field="${field_reason%%:*}"
  remainder="${field_reason#*:}"
  value="${remainder%%:*}"
  expected="${remainder#*:}"
  write_state 0 '[]' "${finding}" true true false false false false
  jq --arg field "${field}" --argjson value "${value}" '.[$field] = $value' "${state}" > "${state}.new"
  mv "${state}.new" "${state}"
  result="$("${repo_root}/scripts/evaluate-repair-decision.sh" --state "${state}")"
  test "$(jq -r .status <<<"${result}")" = human_required
  test "$(jq -r .reason <<<"${result}")" = "${expected}"
done

echo "repair decision tests passed"
