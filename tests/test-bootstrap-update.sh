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
  --skip-understand-anything >/dev/null

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
