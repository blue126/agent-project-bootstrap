#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

configured="${test_root}/configured"
"${repo_root}/scripts/bootstrap.sh" \
  --target "${configured}" --workflow none --skip-skills --skip-understand-anything >/dev/null
sed -i.bak \
  -e 's/^  fixer: none$/  fixer: claude-action/' \
  -e 's/^  validation: pending$/  validation: configured/' \
  -e 's/^  validation_mode: review_only$/  validation_mode: enforced/' \
  -e 's/^  auto_merge: disabled$/  auto_merge: enabled/' \
  "${configured}/.agent/bootstrap.yml"
rm -f "${configured}/.agent/bootstrap.yml.bak"
"${repo_root}/scripts/set-governance-safe-mode.sh" --project "${configured}" >/dev/null
grep -q '^  fixer: none$' "${configured}/.agent/bootstrap.yml"
grep -q '^  validation_mode: shadow$' "${configured}/.agent/bootstrap.yml"
grep -q '^  auto_merge: disabled$' "${configured}/.agent/bootstrap.yml"

# Idempotent and pending projects remain review-only.
"${repo_root}/scripts/set-governance-safe-mode.sh" --project "${configured}" >/dev/null
pending="${test_root}/pending"
"${repo_root}/scripts/bootstrap.sh" \
  --target "${pending}" --workflow none --skip-skills --skip-understand-anything >/dev/null
"${repo_root}/scripts/set-governance-safe-mode.sh" --project "${pending}" >/dev/null
grep -q '^  validation_mode: review_only$' "${pending}/.agent/bootstrap.yml"

echo "governance rollback tests passed"
