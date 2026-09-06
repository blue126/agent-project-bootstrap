#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

# --update reconciles against a hash recorded when bootstrap last wrote each
# file, so it can tell "the template moved on" from "the user edited this".
templates="${test_root}/templates"
cp -R "${repo_root}" "${templates}"
rm -rf "${templates}/.git"

target="${test_root}/project"
"${templates}/scripts/bootstrap.sh" \
  --target "${target}" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything \
  --skip-claude-auto-review >/dev/null

grep -q '^managed_files:$' "${target}/.agent/bootstrap.yml"
grep -q '^  AGENTS.md: [0-9a-f]\{64\}$' "${target}/.agent/bootstrap.yml"

# 1) Nothing changed anywhere.
output="$("${templates}/scripts/bootstrap.sh" --target "${target}" --update)"
grep -q 'already current' <<<"${output}"

# 2) The template moves forward and the project file is untouched: refresh it.
echo "- Added upstream." >> "${templates}/policies/core.md"
output="$("${templates}/scripts/bootstrap.sh" --target "${target}" --update)"
grep -q 'Refreshed bootstrap-managed files' <<<"${output}"
grep -q 'Added upstream' "${target}/.agent/policies/core.md"

# 3) The user edited the file: keep their version and say so.
echo "- Local project rule." >> "${target}/.agent/policies/git.md"
echo "- Added upstream too." >> "${templates}/policies/git.md"
output="$("${templates}/scripts/bootstrap.sh" --target "${target}" --update)"
grep -q 'Left alone' <<<"${output}"
grep -q 'Local project rule' "${target}/.agent/policies/git.md"
if grep -q 'Added upstream too' "${target}/.agent/policies/git.md"; then
  echo "update unexpectedly overwrote a user-edited file" >&2
  exit 1
fi

# 3b) Preservation must survive repeated updates, not just the first one.
output="$("${templates}/scripts/bootstrap.sh" --target "${target}" --update)"
grep -q 'Left alone' <<<"${output}"
grep -q 'Local project rule' "${target}/.agent/policies/git.md"

# 4) --force replaces user edits, but only when asked.
"${templates}/scripts/bootstrap.sh" --target "${target}" --update --force >/dev/null
grep -q 'Added upstream too' "${target}/.agent/policies/git.md"
if grep -q 'Local project rule' "${target}/.agent/policies/git.md"; then
  echo "--force did not replace the user-edited file" >&2
  exit 1
fi

# 5) Recorded selections are replayed, so an update needs no arguments.
grep -q '^workflow_id: github-workflow$' "${target}/.agent/bootstrap.yml"

# 5b) Governance state belongs to the consumer and survives managed-file updates.
sed -i.bak \
  -e 's/^  reviewer: none$/  reviewer: claude/' \
  -e 's/^  fixer: none$/  fixer: codex-action/' \
  -e 's/^  validation: pending$/  validation: configured/' \
  -e 's/^  validation_mode: review_only$/  validation_mode: shadow/' \
  -e 's|^  validation_adapter_manifest: none$|  validation_adapter_manifest: .agent/validation/adapter.json|' \
  -e 's/^  validation_adapter_sha256: none$/  validation_adapter_sha256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/' \
  "${target}/.agent/bootstrap.yml"
rm -f "${target}/.agent/bootstrap.yml.bak"
"${templates}/scripts/bootstrap.sh" --target "${target}" --update >/dev/null
grep -q '^  reviewer: claude$' "${target}/.agent/bootstrap.yml"
grep -q '^  fixer: codex-action$' "${target}/.agent/bootstrap.yml"
grep -q '^  validation: configured$' "${target}/.agent/bootstrap.yml"
grep -q '^  validation_mode: shadow$' "${target}/.agent/bootstrap.yml"
grep -q '^  validation_adapter_manifest: .agent/validation/adapter.json$' "${target}/.agent/bootstrap.yml"
grep -q '^  validation_adapter_sha256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef$' "${target}/.agent/bootstrap.yml"

# 6) --update must not relaunch installers for recorded selections. The recorded
#    value is carried forward even though this run installs nothing.
installed_target="${test_root}/installed"
"${templates}/scripts/bootstrap.sh" \
  --target "${installed_target}" \
  --workflow none \
  --skip-skills \
  --skip-understand-anything >/dev/null
sed -i.bak 's/^  curated_skills: skip$/  curated_skills: install/' "${installed_target}/.agent/bootstrap.yml"
rm -f "${installed_target}/.agent/bootstrap.yml.bak"
output="$("${templates}/scripts/bootstrap.sh" --target "${installed_target}" --update)"
grep -q '^  curated_skills: install$' "${installed_target}/.agent/bootstrap.yml"

# 7) Claude Auto Review selection is replayed without a reminder or selector.
selected_target="${test_root}/selected-auto-review"
"${templates}/scripts/bootstrap.sh" \
  --target "${selected_target}" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything \
  --select-claude-auto-review >/dev/null
grep -q '^schema_version: 5$' "${selected_target}/.agent/bootstrap.yml"
grep -q '^  claude_auto_review: selected$' "${selected_target}/.agent/bootstrap.yml"
update_output="$("${templates}/scripts/bootstrap.sh" --target "${selected_target}" --update)"
grep -q '^  claude_auto_review: selected$' "${selected_target}/.agent/bootstrap.yml"
if grep -q '/install-github-app' <<<"${update_output}"; then
  echo "--update unexpectedly repeated Claude Auto Review guidance" >&2
  exit 1
fi

if "${templates}/scripts/bootstrap.sh" \
  --target "${selected_target}" \
  --update \
  --select-claude-auto-review >/dev/null 2>&1; then
  echo "--update unexpectedly accepted a Claude Auto Review selection override" >&2
  exit 1
fi

if "${templates}/scripts/bootstrap.sh" \
  --target "${selected_target}" \
  --update \
  --skip-claude-auto-review >/dev/null 2>&1; then
  echo "--update unexpectedly accepted a Claude Auto Review skip override" >&2
  exit 1
fi

# 8) A v5 skipped selection is replayed without a reminder.
skipped_target="${test_root}/skipped-auto-review"
"${templates}/scripts/bootstrap.sh" \
  --target "${skipped_target}" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything \
  --skip-claude-auto-review >/dev/null
grep -q '^schema_version: 5$' "${skipped_target}/.agent/bootstrap.yml"
grep -q '^  claude_auto_review: skipped$' "${skipped_target}/.agent/bootstrap.yml"
skipped_update_output="$("${templates}/scripts/bootstrap.sh" --target "${skipped_target}" --update)"
grep -q '^  claude_auto_review: skipped$' "${skipped_target}/.agent/bootstrap.yml"
if grep -q '/install-github-app' <<<"${skipped_update_output}"; then
  echo "v5 skipped replay unexpectedly printed Claude Auto Review guidance" >&2
  exit 1
fi

# 9) v4 manifests migrate to v5 with the safe skipped default.
v4_target="${test_root}/v4-auto-review"
"${templates}/scripts/bootstrap.sh" \
  --target "${v4_target}" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything \
  --skip-claude-auto-review >/dev/null
sed -i.bak \
  -e 's/^schema_version: 5$/schema_version: 4/' \
  -e '/^  claude_auto_review: /d' \
  "${v4_target}/.agent/bootstrap.yml"
rm -f "${v4_target}/.agent/bootstrap.yml.bak"
v4_update_output="$("${templates}/scripts/bootstrap.sh" --target "${v4_target}" --update)"
grep -q '^schema_version: 5$' "${v4_target}/.agent/bootstrap.yml"
grep -q '^  claude_auto_review: skipped$' "${v4_target}/.agent/bootstrap.yml"
if grep -q '/install-github-app' <<<"${v4_update_output}"; then
  echo "v4 migration unexpectedly printed Claude Auto Review guidance" >&2
  exit 1
fi

# 9) Invalid persisted state fails closed.
sed -i.bak 's/^  claude_auto_review: skipped$/  claude_auto_review: enabled/' "${v4_target}/.agent/bootstrap.yml"
rm -f "${v4_target}/.agent/bootstrap.yml.bak"
if "${templates}/scripts/bootstrap.sh" --target "${v4_target}" --update >/dev/null 2>&1; then
  echo "--update unexpectedly accepted an invalid Claude Auto Review state" >&2
  exit 1
fi

# 7) Guard rails.
if "${templates}/scripts/bootstrap.sh" --target "${test_root}/never-bootstrapped" --update >/dev/null 2>&1; then
  echo "--update unexpectedly accepted a project without a manifest" >&2
  exit 1
fi

if "${templates}/scripts/bootstrap.sh" --target "${target}" --force >/dev/null 2>&1; then
  echo "--force unexpectedly accepted without --update" >&2
  exit 1
fi

# 8) A project whose manifest predates managed_files is treated as user-owned.
legacy="${test_root}/legacy"
"${templates}/scripts/bootstrap.sh" \
  --target "${legacy}" \
  --workflow none \
  --skip-skills \
  --skip-understand-anything >/dev/null
sed -i.bak '/^managed_files:$/,$d' "${legacy}/.agent/bootstrap.yml"
rm -f "${legacy}/.agent/bootstrap.yml.bak"
echo "- Drifted." >> "${templates}/policies/core.md"
output="$("${templates}/scripts/bootstrap.sh" --target "${legacy}" --update)"
grep -q 'Left alone' <<<"${output}"

echo "bootstrap update tests passed"
