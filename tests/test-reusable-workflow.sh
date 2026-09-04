#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${repo_root}/.github/workflows/governance-observe.yml"

test -s "${workflow}"
grep -q '^  workflow_call:$' "${workflow}"
grep -q '^  contents: read$' "${workflow}"
grep -q '^  pull-requests: read$' "${workflow}"
grep -q 'observe-only (not a merge gate)' "${workflow}"
grep -q 'github.workflow_sha' "${workflow}"
grep -q 'steps.metadata.outputs.head_repository' "${workflow}"
grep -q 'base.repo.full_name' "${workflow}"
grep -q 'persist-credentials: false' "${workflow}"
grep -q 'check-governance-readiness.sh --project base' "${workflow}"
grep -q 'classify-sensitive-paths.sh --policy' "${workflow}"

if grep -Eq '(pull_request_target|secrets: inherit|contents: write|pull-requests: write|repo-validation|ai-review-gate)' "${workflow}"; then
  echo "observe workflow contains a privileged trigger, secret inheritance, write permission, or gate name" >&2
  exit 1
fi

checkout_count="$(grep -c 'uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1' "${workflow}")"
test "${checkout_count}" = 3

echo "reusable observe workflow tests passed"
