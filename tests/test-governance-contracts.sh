#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

full_sha="0123456789abcdef0123456789abcdef01234567"
base_sha="89abcdef0123456789abcdef0123456789abcdef"

cat > "${test_root}/pass.json" <<EOF
{
  "repository": "acme/project",
  "pull_request": 12,
  "reviewed_sha": "${full_sha}",
  "status": "pass",
  "findings": []
}
EOF
"${repo_root}/scripts/validate-review-verdict.sh" \
  --file "${test_root}/pass.json" --repo acme/project --pr 12 --sha "${full_sha}" >/dev/null

if "${repo_root}/scripts/validate-review-verdict.sh" \
  --file "${test_root}/pass.json" --repo acme/project --pr 12 --sha "${base_sha}" >/dev/null 2>&1; then
  echo "wrong-SHA verdict unexpectedly passed" >&2
  exit 1
fi

jq '.status = "needs_fix" | .findings = [{
  fingerprint: "same", severity: "blocking", actionable: true,
  path: "src/file", summary: "fix it"
}, {
  fingerprint: "same", severity: "blocking", actionable: true,
  path: "src/other", summary: "same issue"
}]' "${test_root}/pass.json" > "${test_root}/duplicate.json"
if "${repo_root}/scripts/validate-review-verdict.sh" \
  --file "${test_root}/duplicate.json" --repo acme/project --pr 12 --sha "${full_sha}" >/dev/null 2>&1; then
  echo "duplicate finding fingerprints unexpectedly passed" >&2
  exit 1
fi

adapter_root="${test_root}/trusted-adapter"
workspace="${test_root}/pr-workspace"
mkdir -p "${adapter_root}" "${workspace}"
cat > "${adapter_root}/adapter.json" <<'EOF'
{
  "contract_version": 1,
  "id": "fixture",
  "version": "1.0.0",
  "license": "MIT",
  "entrypoint": "validate.sh",
  "supported_stacks": ["fixture"]
}
EOF
cat > "${adapter_root}/validate.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${AGENT_VALIDATION_WORKSPACE}" == */pr-workspace ]]
[[ "${AGENT_VALIDATION_REPOSITORY}" == acme/project ]]
[[ "${AGENT_VALIDATION_PULL_REQUEST}" == 12 ]]
[[ -z "${SHOULD_NOT_LEAK:-}" ]]
touch "${AGENT_VALIDATION_WORKSPACE}/validated"
printf '{"repository":"%s","pull_request":%s,"validated_sha":"%s","adapter":{"id":"%s","version":"%s","manifest_sha256":"%s"},"status":"pass","summary":"fixture passed"}\n' \
  "${AGENT_VALIDATION_REPOSITORY}" \
  "${AGENT_VALIDATION_PULL_REQUEST}" \
  "${AGENT_VALIDATION_HEAD_SHA}" \
  "${AGENT_VALIDATION_ADAPTER_ID}" \
  "${AGENT_VALIDATION_ADAPTER_VERSION}" \
  "${AGENT_VALIDATION_MANIFEST_SHA256}"
EOF
chmod +x "${adapter_root}/validate.sh"
if command -v sha256sum >/dev/null 2>&1; then
  manifest_sha="$(sha256sum "${adapter_root}/adapter.json" | cut -d' ' -f1)"
else
  manifest_sha="$(shasum -a 256 "${adapter_root}/adapter.json" | cut -d' ' -f1)"
fi

SHOULD_NOT_LEAK=secret "${repo_root}/scripts/run-validation-adapter.sh" \
  --adapter-root "${adapter_root}" \
  --manifest "${adapter_root}/adapter.json" \
  --workspace "${workspace}" \
  --repo acme/project --pr 12 \
  --base-sha "${base_sha}" --head-sha "${full_sha}" \
  --expected-manifest-sha "${manifest_sha}"
test -f "${workspace}/validated"

if "${repo_root}/scripts/run-validation-adapter.sh" \
  --adapter-root "${adapter_root}" --manifest "${adapter_root}/adapter.json" \
  --workspace "${workspace}" --repo acme/project --pr 12 \
  --base-sha "${base_sha}" --head-sha "${full_sha}" \
  --expected-manifest-sha "$(printf '0%.0s' {1..64})" >/dev/null 2>&1; then
  echo "adapter SHA mismatch unexpectedly passed" >&2
  exit 1
fi

"${repo_root}/scripts/classify-sensitive-paths.sh" \
  --policy "${repo_root}/templates/sensitive-paths.txt" \
  .github/workflows/pr.yml >/dev/null
if "${repo_root}/scripts/classify-sensitive-paths.sh" \
  --policy "${repo_root}/templates/sensitive-paths.txt" \
  src/application.c >/dev/null; then
  echo "ordinary path unexpectedly classified as sensitive" >&2
  exit 1
fi

pending_project="${test_root}/pending-project"
"${repo_root}/scripts/bootstrap.sh" \
  --target "${pending_project}" --workflow none --skip-skills --skip-understand-anything >/dev/null
if "${repo_root}/scripts/check-governance-readiness.sh" --project "${pending_project}" >/dev/null 2>&1; then
  echo "pending validation unexpectedly reported ready" >&2
  exit 1
fi

mkdir -p "${pending_project}/.agent/validation"
cp "${adapter_root}/adapter.json" "${pending_project}/.agent/validation/adapter.json"
"${repo_root}/scripts/configure-validation.sh" \
  --project "${pending_project}" \
  --manifest .agent/validation/adapter.json \
  --mode shadow >/dev/null
"${repo_root}/scripts/check-governance-readiness.sh" --project "${pending_project}" >/dev/null

echo "governance contract tests passed"
