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

# Explicit client preferences must reach the integration installer too.
claude_bootstrap_target="${test_root}/bootstrap-claude-project"
BOOTSTRAP_INTEGRATION_TESTING=1 \
UNDERSTAND_ANYTHING_TEST_UPSTREAM="${upstream}" \
UNDERSTAND_ANYTHING_TEST_REF="${fixture_ref}" \
UNDERSTAND_ANYTHING_TEST_PATCH="" \
  "${repo_root}/scripts/bootstrap.sh" --target "${claude_bootstrap_target}" \
    --workflow none --agent claude-code --skip-skills --install-understand-anything >/dev/null
test -L "${claude_bootstrap_target}/.agents/skills/understand"
test -L "${claude_bootstrap_target}/.claude/skills/understand"

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

# Client links are additive and never require another clone of a valid runtime.
fixture_install() {
  BOOTSTRAP_INTEGRATION_TESTING=1 \
  UNDERSTAND_ANYTHING_TEST_UPSTREAM="${upstream}" \
  UNDERSTAND_ANYTHING_TEST_REF="${fixture_ref}" \
  UNDERSTAND_ANYTHING_TEST_PATCH="" \
    "${repo_root}/scripts/install-understand-anything.sh" "$@"
}
test ! -e "${target}/.claude"
saved_upstream="${upstream}"
upstream="${test_root}/does-not-exist"
fixture_install --target "${target}" --agent claude-code --agent codex --agent opencode --agent universal --agent claude-code >/dev/null
fixture_install --target "${target}" --agent claude-code >/dev/null
upstream="${saved_upstream}"
for name in understand understand-chat; do
  test -f "${target}/.claude/skills/${name}/SKILL.md"
  test "$(readlink "${target}/.claude/skills/${name}")" = "$(readlink "${target}/.agents/skills/${name}")"
done
cmp "${target}/.agent/runtime/understand-anything/.gitignore" "${test_root}/runtime-ignore-before"

# The last canonical or client collision must not create any earlier links.
for root in .agents/skills .claude/skills; do
  for kind in directory file symlink; do
    collision="${test_root}/late-${root%%/*}-${kind}"
    mkdir -p "${collision}/${root}"
    case "${kind}" in
      directory) mkdir "${collision}/${root}/understand-chat" ;;
      file) printf 'Keep me\n' > "${collision}/${root}/understand-chat" ;;
      symlink) ln -s missing "${collision}/${root}/understand-chat" ;;
    esac
    if fixture_install --target "${collision}" --agent claude-code > /dev/null 2>&1; then
      echo "installer unexpectedly accepted ${root} ${kind} collision" >&2; exit 1
    fi
    test ! -e "${collision}/.agents/skills/understand"
    test ! -L "${collision}/.agents/skills/understand"
    test ! -e "${collision}/.claude/skills/understand"
    test ! -L "${collision}/.claude/skills/understand"
    if [[ "${root}" == .claude/skills ]]; then
      test ! -L "${collision}/.agents/skills/understand-chat"
    fi
  done
done

for directory in .claude .claude/skills .agents .agents/skills; do
  redirected="${test_root}/redirect-${directory//\//-}"
  mkdir -p "${redirected}/$(dirname "${directory}")"
  ln -s "${test_root}/outside" "${redirected}/${directory}"
  if fixture_install --target "${redirected}" --agent claude-code >/dev/null 2>&1; then
    echo "installer unexpectedly accepted ${directory} symlink directory" >&2; exit 1
  fi
  test ! -e "${redirected}/.agent"
done
test -z "$(ls -A "${test_root}/outside")"

for agent in codex opencode universal; do
  shared="${test_root}/only-${agent}"
  mkdir -p "${shared}"
  fixture_install --target "${shared}" --agent "${agent}" >/dev/null
  test -f "${shared}/.agents/skills/understand/SKILL.md"
  test ! -e "${shared}/.claude"
  test ! -e "${shared}/.git"
done
invalid="${test_root}/invalid-client"
mkdir -p "${invalid}"
for mode in invalid missing; do
  args=(--agent)
  [[ "${mode}" != invalid ]] || args+=(invalid)
  if fixture_install --target "${invalid}" "${args[@]}" >/dev/null 2>&1; then
    echo "installer unexpectedly accepted ${args[*]}" >&2; exit 1
  fi
done
test -z "$(ls -A "${invalid}")"

echo "Understand Anything integration tests passed"
