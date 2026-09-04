#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT
distribution="${test_root}/distribution"
cp -R "${repo_root}" "${distribution}"
rm -rf "${distribution}/.git"
project="${test_root}/consumer"

"${distribution}/scripts/bootstrap.sh" \
  --target "${project}" --workflow none --skip-skills --skip-understand-anything >/dev/null
mkdir -p "${project}/.agent/validation"
cat > "${project}/.agent/validation/adapter.json" <<'EOF'
{
  "contract_version": 1,
  "id": "consumer-fixture",
  "version": "1.0.0",
  "license": "MIT",
  "entrypoint": "validate.sh",
  "supported_stacks": ["fixture"]
}
EOF
"${distribution}/scripts/configure-validation.sh" \
  --project "${project}" --manifest .agent/validation/adapter.json --mode shadow >/dev/null
"${distribution}/scripts/install-repo-validation-caller.sh" --project "${project}" >/dev/null

caller="${project}/.github/workflows/repo-validation.yml"
test -s "${caller}"
grep -q 'repo-validation.yml@cb1dc39d68ba7475afaa6272882b48b0f87269a9' "${caller}"
grep -q 'cancel-in-progress: true' "${caller}"
grep -q 'github.event.pull_request.number' "${caller}"
grep -q '^  repo_validation_runtime_sha: cb1dc39d68ba7475afaa6272882b48b0f87269a9$' "${project}/.agent/bootstrap.yml"
grep -q '^  repo_validation: install$' "${project}/.agent/bootstrap.yml"
grep -q '^  .github/workflows/repo-validation.yml: [0-9a-f]\{64\}$' "${project}/.agent/bootstrap.yml"

# Untouched caller may update from a future distribution build.
echo '# distribution update' >> "${distribution}/templates/github/repo-validation.yml"
"${distribution}/scripts/install-repo-validation-caller.sh" --project "${project}" >/dev/null
grep -q 'distribution update' "${caller}"

# Consumer edits are never overwritten and there is no force option.
echo '# consumer edit' >> "${caller}"
if "${distribution}/scripts/install-repo-validation-caller.sh" --project "${project}" >/dev/null 2>&1; then
  echo "installer unexpectedly overwrote a consumer-edited caller" >&2
  exit 1
fi
grep -q 'consumer edit' "${caller}"
if "${distribution}/scripts/install-repo-validation-caller.sh" --help | grep -q -- '--force'; then
  echo "repo-validation caller installer unexpectedly exposes --force" >&2
  exit 1
fi

echo "repo-validation caller tests passed"
