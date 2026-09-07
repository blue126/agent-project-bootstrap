#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:?TMPDIR must be set}/understand-anything.XXXXXX")"
trap 'rm -rf "${test_root}"' EXIT

upstream="${test_root}/upstream"
mkdir -p "${upstream}/understand-anything-plugin/skills/understand"
mkdir -p "${upstream}/understand-anything-plugin/skills/understand-chat"

cat > "${upstream}/understand-anything-plugin/skills/understand/SKILL.md" <<'EOF'
---
name: understand
description: Test fixture
---
EOF
cat > "${upstream}/understand-anything-plugin/skills/understand-chat/SKILL.md" <<'EOF'
---
name: understand-chat
description: Test fixture
---
EOF

git -C "${upstream}" init --initial-branch=main >/dev/null
git -C "${upstream}" add -- understand-anything-plugin
GIT_AUTHOR_NAME="Bootstrap Test" \
GIT_AUTHOR_EMAIL="bootstrap-test@example.invalid" \
GIT_COMMITTER_NAME="Bootstrap Test" \
GIT_COMMITTER_EMAIL="bootstrap-test@example.invalid" \
  git -C "${upstream}" commit -m "Create fixture" >/dev/null
fixture_ref="$(git -C "${upstream}" rev-parse HEAD)"

target="${test_root}/project"
mkdir -p "${target}"
BOOTSTRAP_INTEGRATION_TESTING=1 \
UNDERSTAND_ANYTHING_TEST_UPSTREAM="${upstream}" \
UNDERSTAND_ANYTHING_TEST_REF="${fixture_ref}" \
UNDERSTAND_ANYTHING_TEST_PATCH="" \
  "${repo_root}/scripts/install-understand-anything.sh" --target "${target}"

test "$(git -C "${target}/.agent/runtime/understand-anything/repo" rev-parse HEAD)" = "${fixture_ref}"
test "$(readlink "${target}/.agents/skills/understand")" = "../../.agent/runtime/understand-anything/repo/understand-anything-plugin/skills/understand"
test "$(readlink "${target}/.agents/skills/understand-chat")" = "../../.agent/runtime/understand-anything/repo/understand-anything-plugin/skills/understand-chat"
test -f "${target}/.agents/skills/understand/SKILL.md"
# Direct installation before bootstrap must protect its runtime without claiming
# bootstrap's later broad policy or inventing a project Git repository/remote.
test ! -e "${target}/.git"
test ! -e "${target}/.agent/runtime/.gitignore"
test -f "${target}/.agent/runtime/understand-anything/.gitignore"
cp "${target}/.agent/runtime/understand-anything/.gitignore" "${test_root}/runtime-ignore-before"
git -C "${target}" init -q --initial-branch=main
git -C "${target}" check-ignore -q .agent/runtime/understand-anything/repo/README.md
git -C "${target}" check-ignore -q .agent/runtime/understand-anything/.install.example/repo/file
if git -C "${target}" check-ignore -q .agent/runtime/unrelated/file; then
  echo "installer unexpectedly ignored another integration's runtime" >&2; exit 1
fi
if git -C "${target}" remote get-url origin >/dev/null 2>&1; then
  echo "installer unexpectedly invented an origin" >&2; exit 1
fi

BOOTSTRAP_INTEGRATION_TESTING=1 \
UNDERSTAND_ANYTHING_TEST_UPSTREAM="${upstream}" \
UNDERSTAND_ANYTHING_TEST_REF="${fixture_ref}" \
UNDERSTAND_ANYTHING_TEST_PATCH="" \
  "${repo_root}/scripts/install-understand-anything.sh" --target "${target}" >/dev/null

cmp "${target}/.agent/runtime/understand-anything/.gitignore" "${test_root}/runtime-ignore-before"

# Existing broad policies, unrelated links and pinned checkouts remain intact.
cp "${repo_root}/templates/runtime.gitignore" "${target}/.agent/runtime/.gitignore"
cp "${repo_root}/templates/skills.gitignore" "${target}/.agents/skills/.gitignore"
ln -s "${upstream}" "${target}/.agents/skills/unrelated"
BOOTSTRAP_INTEGRATION_TESTING=1 \
UNDERSTAND_ANYTHING_TEST_UPSTREAM="${upstream}" \
UNDERSTAND_ANYTHING_TEST_REF="${fixture_ref}" \
UNDERSTAND_ANYTHING_TEST_PATCH="" \
  "${repo_root}/scripts/install-understand-anything.sh" --target "${target}" >/dev/null
cmp "${target}/.agent/runtime/.gitignore" "${repo_root}/templates/runtime.gitignore"
cmp "${target}/.agents/skills/.gitignore" "${repo_root}/templates/skills.gitignore"
test "$(readlink "${target}/.agents/skills/unrelated")" = "${upstream}"

# Installation directories/ignore files must not redirect writes outside target.
symlink_target="${test_root}/symlink-project"
mkdir -p "${symlink_target}" "${test_root}/outside"
ln -s "${test_root}/outside" "${symlink_target}/.agent"
if BOOTSTRAP_INTEGRATION_TESTING=1 \
  UNDERSTAND_ANYTHING_TEST_UPSTREAM="${upstream}" \
  UNDERSTAND_ANYTHING_TEST_REF="${fixture_ref}" \
  UNDERSTAND_ANYTHING_TEST_PATCH="" \
  "${repo_root}/scripts/install-understand-anything.sh" --target "${symlink_target}" >/dev/null 2>&1; then
  echo "installer unexpectedly wrote through a directory link" >&2
  exit 1
fi
test ! -e "${test_root}/outside/runtime"

bootstrap_target="${test_root}/bootstrap-project"
BOOTSTRAP_INTEGRATION_TESTING=1 \
UNDERSTAND_ANYTHING_TEST_UPSTREAM="${upstream}" \
UNDERSTAND_ANYTHING_TEST_REF="${fixture_ref}" \
UNDERSTAND_ANYTHING_TEST_PATCH="" \
  "${repo_root}/scripts/bootstrap.sh" \
    --target "${bootstrap_target}" \
    --workflow none \
    --skip-skills \
    --install-understand-anything
grep -q '^    installation: install$' "${bootstrap_target}/.agent/bootstrap.yml"
test -L "${bootstrap_target}/.agents/skills/understand"

collision_target="${test_root}/collision"
mkdir -p "${collision_target}/.agents/skills/understand"
if BOOTSTRAP_INTEGRATION_TESTING=1 \
  UNDERSTAND_ANYTHING_TEST_UPSTREAM="${upstream}" \
  UNDERSTAND_ANYTHING_TEST_REF="${fixture_ref}" \
  UNDERSTAND_ANYTHING_TEST_PATCH="" \
  "${repo_root}/scripts/install-understand-anything.sh" --target "${collision_target}" >/dev/null 2>&1; then
  echo "installer unexpectedly overwrote an existing project Skill" >&2
  exit 1
fi

grep -q 'PROJECT_SELF_RELATIVE' "${repo_root}/integrations/understand-anything/patches/project-scope-and-git-hardening.patch"
grep -q 'rev-parse.*--end-of-options' "${repo_root}/integrations/understand-anything/patches/project-scope-and-git-hardening.patch"

echo "Understand Anything integration tests passed"
