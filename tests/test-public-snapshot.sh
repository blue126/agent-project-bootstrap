#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! git -C "${repo_root}" rev-parse --git-dir >/dev/null 2>&1; then
  echo "public snapshot self-test skipped: source tree intentionally has no Git metadata"
  exit 0
fi
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT
snapshot="${test_root}/snapshot"

"${repo_root}/scripts/create-public-snapshot.sh" --output "${snapshot}" --ref HEAD >/dev/null
[[ ! -e "${snapshot}/.git" ]]
[[ ! -e "${snapshot}/skills/human-3-development-assessor" ]]
test -s "${snapshot}/LICENSE"
test -s "${snapshot}/THIRD_PARTY_NOTICES.md"

if "${repo_root}/scripts/create-public-snapshot.sh" --output "${snapshot}" --ref HEAD >/dev/null 2>&1; then
  echo "snapshot creation unexpectedly overwrote an existing path" >&2
  exit 1
fi

echo "public snapshot tests passed"
