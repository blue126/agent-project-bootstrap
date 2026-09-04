#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -q '^  validation: pending$' "${repo_root}/.agent/bootstrap.yml"
grep -q '^  validation_mode: review_only$' "${repo_root}/.agent/bootstrap.yml"
grep -q '^  auto_merge: disabled$' "${repo_root}/.agent/bootstrap.yml"
grep -q 'governance-observe.yml@20ae04d640f252201e660db977a43a41f4bfccb0' \
  "${repo_root}/.github/workflows/agent-governance-observe.yml"

if "${repo_root}/scripts/check-governance-readiness.sh" --project "${repo_root}" >/dev/null 2>&1; then
  echo "pending shadow pilot unexpectedly reported validation ready" >&2
  exit 1
fi

"${repo_root}/scripts/classify-sensitive-paths.sh" \
  --policy "${repo_root}/.agent/governance/sensitive-paths.txt" \
  .github/workflows/agent-governance-observe.yml >/dev/null

echo "shadow pilot tests passed"
