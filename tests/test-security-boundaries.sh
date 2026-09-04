#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
observe="${repo_root}/.github/workflows/governance-observe.yml"
caller="${repo_root}/.github/workflows/agent-governance-observe.yml"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

# A PR cannot remove its own sensitive-path classification: runtime uses base.
"${repo_root}/scripts/classify-sensitive-paths.sh" \
  --policy "${repo_root}/tests/fixtures/security/base-sensitive-paths.txt" \
  .github/workflows/agent-governance-observe.yml >/dev/null
if "${repo_root}/scripts/classify-sensitive-paths.sh" \
  --policy "${repo_root}/tests/fixtures/security/head-sensitive-paths.txt" \
  .github/workflows/agent-governance-observe.yml >/dev/null; then
  echo "head policy fixture unexpectedly classified its own governance change" >&2
  exit 1
fi
grep -q 'check-governance-readiness.sh --project base' "${observe}"
grep -q 'base/.agent/governance/sensitive-paths.txt' "${observe}"

# Fork head repository comes from API-verified metadata, never caller text.
grep -q 'head.repo.full_name' "${observe}"
grep -q 'steps.metadata.outputs.head_repository' "${observe}"
grep -q 'actual_head.*EXPECTED_HEAD_SHA' "${observe}"

# Observe workflows are credential-free and cannot mutate repository state.
if rg -n '(pull_request_target|secrets: inherit|contents: write|pull-requests: write|id-token: write)' \
  "${observe}" "${caller}"; then
  echo "observe workflow violates the read-only credential boundary" >&2
  exit 1
fi
test "$(grep -c 'persist-credentials: false' "${observe}")" = 3
grep -q 'EXPECTED_RUNTIME_SHA.*github.workflow_sha' "${observe}"
grep -q 'git -C runtime rev-parse HEAD' "${observe}"

# Public and private consumers receive the same immutable, secret-free caller.
for visibility in public private; do
  consumer="${test_root}/${visibility}"
  "${repo_root}/scripts/bootstrap.sh" \
    --target "${consumer}" --workflow none --skip-skills --skip-understand-anything \
    --install-governance-observe >/dev/null
  cp "${consumer}/.github/workflows/agent-governance-observe.yml" "${test_root}/${visibility}.caller"
done
cmp "${test_root}/public.caller" "${test_root}/private.caller"
if grep -Eq '(secrets:|@main|@master|@v[0-9])' "${test_root}/public.caller"; then
  echo "consumer caller contains secret mapping or floating runtime ref" >&2
  exit 1
fi

# Provider config rejects implicit providers and documents explicit secret names.
jq -e '.properties.secret_mappings.items.pattern == "^[A-Z][A-Z0-9_]*$"' \
  "${repo_root}/schemas/provider-config.schema.json" >/dev/null
jq -e '.properties.fixer.enum == ["none", "claude-action", "codex-action"]' \
  "${repo_root}/schemas/provider-config.schema.json" >/dev/null

echo "security boundary fixtures passed"
