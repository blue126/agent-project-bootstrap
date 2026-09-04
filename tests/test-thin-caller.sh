#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT
distribution="${test_root}/distribution"
cp -R "${repo_root}" "${distribution}"
rm -rf "${distribution}/.git"

target="${test_root}/consumer"
"${distribution}/scripts/bootstrap.sh" \
  --target "${target}" --workflow none --skip-skills --skip-understand-anything \
  --install-governance-observe >/dev/null

caller="${target}/.github/workflows/agent-governance-observe.yml"
test -s "${caller}"
grep -q 'governance-observe.yml@20ae04d640f252201e660db977a43a41f4bfccb0' "${caller}"
grep -q '^  runtime_sha: 20ae04d640f252201e660db977a43a41f4bfccb0$' "${target}/.agent/bootstrap.yml"
grep -q '^  governance_observe: install$' "${target}/.agent/bootstrap.yml"
if grep -Eq '(secrets:|pull_request_target|write)' "${caller}"; then
  echo "thin caller unexpectedly contains secrets, a privileged trigger, or write access" >&2
  exit 1
fi
grep -q 'cancel-in-progress: true' "${caller}"
grep -q 'github.event.pull_request.number' "${caller}"

# Untouched managed callers upgrade; consumer-edited callers are preserved.
echo '# released update' >> "${distribution}/templates/github/governance-observe.yml"
"${distribution}/scripts/bootstrap.sh" --target "${target}" --update >/dev/null
grep -q 'released update' "${caller}"
echo '# consumer edit' >> "${caller}"
echo '# next release' >> "${distribution}/templates/github/governance-observe.yml"
output="$("${distribution}/scripts/bootstrap.sh" --target "${target}" --update)"
grep -q 'Left alone' <<<"${output}"
grep -q 'consumer edit' "${caller}"
if grep -q 'next release' "${caller}"; then
  echo "update overwrote a consumer-edited thin caller" >&2
  exit 1
fi

echo "thin caller tests passed"
