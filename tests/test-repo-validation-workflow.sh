#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${repo_root}/.github/workflows/repo-validation.yml"

test -s "${workflow}"
grep -q '^  workflow_call:$' "${workflow}"
grep -q '^  repo-validation:$' "${workflow}"
grep -q '^    name: repo-validation$' "${workflow}"
grep -q 'check-governance-readiness.sh --project base' "${workflow}"
grep -q 'run-validation-adapter.sh' "${workflow}"
grep -q 'adapter-root base' "${workflow}"
grep -q 'workspace head' "${workflow}"
grep -q 'github.workflow_sha' "${workflow}"
grep -q 'steps.metadata.outputs.head_repository' "${workflow}"
test "$(grep -c 'persist-credentials: false' "${workflow}")" = 3

if grep -Eq '(pull_request_target|secrets: inherit|contents: write|pull-requests: write|id-token: write)' "${workflow}"; then
  echo "repo-validation workflow violates the no-secret read-only boundary" >&2
  exit 1
fi
if grep -Eq '(npm|node|python|terraform|ansible|jenkins)' "${workflow}"; then
  echo "repo-validation runtime contains a project-specific stack implementation" >&2
  exit 1
fi

echo "repo-validation workflow tests passed"
