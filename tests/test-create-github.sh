#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

mock_bin="${test_root}/bin"
mkdir -p "${mock_bin}"

cat > "${mock_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == repo && "$2" == create ]] || exit 1
shift 2
repository="$1"
shift
source_dir=""
remote=""
visibility=""
push=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --private|--public|--internal) visibility="$1"; shift ;;
    --source) source_dir="$2"; shift 2 ;;
    --remote) remote="$2"; shift 2 ;;
    --push) push=true; shift ;;
    *) exit 2 ;;
  esac
done
[[ "${repository}" == acme/project ]]
[[ "${visibility}" == --private ]]
[[ "${remote}" == origin ]]
[[ "${push}" == true ]]
git -C "${source_dir}" remote add origin "https://github.com/${repository}.git"
EOF
chmod +x "${mock_bin}/gh"

target="${test_root}/project"
GIT_AUTHOR_NAME="Bootstrap Test" \
GIT_AUTHOR_EMAIL="bootstrap-test@example.invalid" \
GIT_COMMITTER_NAME="Bootstrap Test" \
GIT_COMMITTER_EMAIL="bootstrap-test@example.invalid" \
PATH="${mock_bin}:${PATH}" "${repo_root}/scripts/bootstrap.sh" \
  --target "${target}" \
  --workflow github-workflow \
  --skip-claude-auto-review \
  --skip-skills \
  --skip-understand-anything \
  --create-github \
  --github-repo acme/project \
  --github-visibility private

test "$(git -C "${target}" branch --show-current)" = main
test "$(git -C "${target}" log -1 --format=%s)" = "Initialize Agent project"
test "$(git -C "${target}" remote get-url origin)" = "https://github.com/acme/project.git"
git -C "${target}" diff --quiet
git -C "${target}" diff --cached --quiet

# Integration runtimes and installed Skills are local artifacts. They must be
# ignored rather than published: a committed link into the ignored runtime tree
# would dangle in every fresh clone.
integration_target="${test_root}/integration-project"
mkdir -p "${integration_target}/.agent/runtime" "${integration_target}/.agents/skills"
cp "${repo_root}/templates/runtime.gitignore" "${integration_target}/.agent/runtime/.gitignore"
cp "${repo_root}/templates/skills.gitignore" "${integration_target}/.agents/skills/.gitignore"
ln -s "../../.agent/runtime/understand-anything/repo/understand-anything-plugin/skills/understand" \
  "${integration_target}/.agents/skills/understand"
mkdir -p "${integration_target}/.agents/skills/curated-copy"
touch "${integration_target}/.agents/skills/curated-copy/SKILL.md"
GIT_AUTHOR_NAME="Bootstrap Test" \
GIT_AUTHOR_EMAIL="bootstrap-test@example.invalid" \
GIT_COMMITTER_NAME="Bootstrap Test" \
GIT_COMMITTER_EMAIL="bootstrap-test@example.invalid" \
PATH="${mock_bin}:${PATH}" "${repo_root}/scripts/create-github.sh" \
  --source "${integration_target}" \
  --repo acme/project \
  --visibility private
git -C "${integration_target}" ls-files --error-unmatch .agent/runtime/.gitignore >/dev/null
git -C "${integration_target}" ls-files --error-unmatch .agents/skills/.gitignore >/dev/null
if git -C "${integration_target}" ls-files --error-unmatch .agents/skills/understand >/dev/null 2>&1; then
  echo "create-github unexpectedly published a link into the ignored runtime tree" >&2
  exit 1
fi
if git -C "${integration_target}" ls-files --error-unmatch .agents/skills/curated-copy/SKILL.md >/dev/null 2>&1; then
  echo "create-github unexpectedly published a locally installed Skill" >&2
  exit 1
fi
git -C "${integration_target}" diff --quiet
git -C "${integration_target}" diff --cached --quiet

if PATH="${mock_bin}:${PATH}" "${repo_root}/scripts/create-github.sh" \
  --source "${target}" --repo acme/second --visibility private >/dev/null 2>&1; then
  echo "create-github unexpectedly replaced an existing origin" >&2
  exit 1
fi

if PATH="${mock_bin}:${PATH}" "${repo_root}/scripts/create-github.sh" \
  --source "${target}" --repo invalid --visibility private >/dev/null 2>&1; then
  echo "create-github unexpectedly accepted an implicit owner" >&2
  exit 1
fi

if PATH="${mock_bin}:${PATH}" "${repo_root}/scripts/create-github.sh" \
  --source "${target}" --repo acme/second --visibility secret >/dev/null 2>&1; then
  echo "create-github unexpectedly accepted an invalid visibility" >&2
  exit 1
fi

dirty_target="${test_root}/dirty"
mkdir -p "${dirty_target}"
cp "${repo_root}/templates/AGENTS.md" "${dirty_target}/AGENTS.md"
touch "${dirty_target}/user-file.txt"
if PATH="${mock_bin}:${PATH}" "${repo_root}/scripts/create-github.sh" \
  --source "${dirty_target}" --repo acme/project --visibility private >/dev/null 2>&1; then
  echo "create-github unexpectedly published unrelated untracked files" >&2
  exit 1
fi

echo "create-github tests passed"
