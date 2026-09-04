#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT
metadata="${test_root}/metadata.json"
validation="${test_root}/validation.json"
old_sha="0123456789abcdef0123456789abcdef01234567"
new_sha="89abcdef0123456789abcdef0123456789abcdef"

write_metadata() {
  jq -n --arg old "${old_sha}" --arg new "${new_sha}" '{
    repository:"acme/project", pull_request:12, state:"open", draft:false, fork:false,
    head_repository:"acme/project", actor:"fixer-bot", allowed_actors:["fixer-bot"],
    head_ref:"fix/pr-12", default_branch:"main", api_head_sha:$old,
    expected_head_sha:$old, proposed_commit_sha:$new, proposed_parent_sha:$old,
    changed_paths:["src/application.txt"]
  }' > "${metadata}"
}
write_validation() {
  jq -n --arg sha "${new_sha}" '{
    repository:"acme/project", pull_request:12, validated_sha:$sha,
    adapter:{id:"fixture",version:"1",manifest_sha256:("a" * 64)},
    status:"pass",summary:"passed"
  }' > "${validation}"
}
write_metadata
write_validation
result="$("${repo_root}/scripts/authorize-fixer-push.sh" \
  --metadata "${metadata}" --validation-result "${validation}" \
  --policy "${repo_root}/templates/sensitive-paths.txt")"
test "$(jq -r .authorized <<<"${result}")" = true
test "$(jq -r .push_mode <<<"${result}")" = normal-fast-forward

for mutation in \
  '.fork=true' \
  '.actor="unknown"' \
  '.head_ref="main"' \
  '.api_head_sha=("b" * 40)' \
  '.proposed_parent_sha=("b" * 40)' \
  '.draft=true' \
  '.changed_paths=[".github/workflows/unsafe.yml"]'; do
  write_metadata
  jq "${mutation}" "${metadata}" > "${metadata}.new"
  mv "${metadata}.new" "${metadata}"
  if "${repo_root}/scripts/authorize-fixer-push.sh" \
    --metadata "${metadata}" --validation-result "${validation}" \
    --policy "${repo_root}/templates/sensitive-paths.txt" >/dev/null 2>&1; then
    echo "Fixer authorization unexpectedly accepted mutation: ${mutation}" >&2
    exit 1
  fi
done

write_metadata
jq '.validated_sha=("c" * 40)' "${validation}" > "${validation}.new"
mv "${validation}.new" "${validation}"
if "${repo_root}/scripts/authorize-fixer-push.sh" \
  --metadata "${metadata}" --validation-result "${validation}" \
  --policy "${repo_root}/templates/sensitive-paths.txt" >/dev/null 2>&1; then
  echo "Fixer authorization unexpectedly accepted stale validation" >&2
  exit 1
fi

echo "Fixer authorization tests passed"
