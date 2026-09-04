#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
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

BOOTSTRAP_INTEGRATION_TESTING=1 \
UNDERSTAND_ANYTHING_TEST_UPSTREAM="${upstream}" \
UNDERSTAND_ANYTHING_TEST_REF="${fixture_ref}" \
UNDERSTAND_ANYTHING_TEST_PATCH="" \
  "${repo_root}/scripts/install-understand-anything.sh" --target "${target}" >/dev/null

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
