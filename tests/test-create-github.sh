#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:?TMPDIR must be set}/create-github.XXXXXX")"
trap 'rm -rf "${test_root}"' EXIT
trap 'printf "Test failed at line %s: %s\n" "${LINENO}" "${BASH_COMMAND}" >&2' ERR

mock_bin="${test_root}/bin"
export HOME="${test_root}/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="${test_root}/global-config"
mkdir -p "${mock_bin}" "${HOME}"
: > "${GIT_CONFIG_GLOBAL}"
# Even a broken test double must not contact a real remote. Only the push
# wrapper below translates the validated GitHub URL to a local bare fixture.
export GIT_ALLOW_PROTOCOL=file
REAL_GIT="$(command -v git)"
export REAL_GIT
export PUSH_LOG="${test_root}/push.log" GH_LOG="${test_root}/gh.log" BLOB_LOG="${test_root}/blob.log"
cat > "${mock_bin}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args=("$@")
source_dir=""
config_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -C) source_dir="$2"; shift 2 ;;
    -c) config_args+=(-c "$2"); shift 2 ;;
    *) break ;;
  esac
done
case "${1:-}" in
  cat-file)
    printf '%s\n' "$*" >> "${BLOB_LOG}"
    if [[ "${MOCK_BATCH_FAILURE:-}" != "" && "${2:-}" == --batch ]]; then
      exec python3 -c '
import os, sys
mode = os.environ["MOCK_BATCH_FAILURE"]
oid = sys.stdin.buffer.readline().strip()
if mode == "oversized":
    # No payload exists: checking the header must reject before reading it.
    sys.stdout.buffer.write(oid + b" blob 10485761\n")
elif mode == "truncated":
    sys.stdout.buffer.write(oid + b" blob 4\nab")
elif mode == "wrong-type":
    sys.stdout.buffer.write(oid + b" tree 0\n\n")
else:
    sys.stdout.buffer.write(oid + b" missing\n")
sys.stdout.buffer.flush()
'
    fi
    ;;
  commit)
    if [[ -n "${GIT_INDEX_FILE:-}" ]]; then
      [[ -f "${source_dir}/.git/index.lock" ]]
      case "${MOCK_COMMIT_MUTATION:-}" in
        tree)
          printf 'Unscanned replacement\n' > "${source_dir}/AGENTS.md"
          "${REAL_GIT}" -C "${source_dir}" add AGENTS.md ;;
        parent)
          empty_tree="$("${REAL_GIT}" -C "${source_dir}" mktree </dev/null)"
          parent_args=(commit-tree "${empty_tree}" -m 'Unscanned parent')
          if old="$("${REAL_GIT}" -C "${source_dir}" rev-parse --verify HEAD 2>/dev/null)"; then
            parent_args+=(-p "${old}")
          fi
          unscanned="$("${REAL_GIT}" -C "${source_dir}" "${parent_args[@]}")"
          "${REAL_GIT}" -C "${source_dir}" update-ref refs/heads/main "${unscanned}" ;;
      esac
      if [[ "${MOCK_COMMIT_MUTATION:-}" == after-commit ]]; then
        "${REAL_GIT}" "${args[@]}"
        committed="$("${REAL_GIT}" -C "${source_dir}" rev-parse HEAD)"
        unscanned="$("${REAL_GIT}" -C "${source_dir}" commit-tree "${committed}^{tree}" -p "${committed}" -m 'Unscanned followup')"
        "${REAL_GIT}" -C "${source_dir}" update-ref refs/heads/main "${unscanned}"
        exit 0
      fi
    fi
    ;;
  push)
    printf '%s\n' "$*" >> "${PUSH_LOG}"
    [[ $# == 4 && "$2" == --no-follow-tags && "$3" == origin ]]
    [[ "$4" =~ ^[0-9a-f]{40,64}:refs/heads/main$ ]]
    [[ -d "${source_dir}.git-remote" ]]
    # Use real send-pack/receive-pack, but only against our local bare fixture.
    exec "${REAL_GIT}" -C "${source_dir}" "${config_args[@]}" \
      -c "remote.origin.pushurl=${source_dir}.git-remote" \
      push --no-follow-tags origin "$4"
    ;;
esac
exec "${REAL_GIT}" "${args[@]}"
EOF
chmod +x "${mock_bin}/git"

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
[[ "${push}" == false ]]
printf '%s\n' "${source_dir}" >> "${GH_LOG}"
git init -q --bare "${source_dir}.git-remote"
git -C "${source_dir}" remote add origin "https://github.com/${repository}.git"
git -C "${source_dir}" rev-parse HEAD > "${source_dir}/.git/scanned-publish-sha"
# Deterministic delay boundary: perform a local edit/commit before gh returns,
# after the publisher finished scanning and capturing its intended commit.
case "${MOCK_GH_MUTATION:-}" in
  advance-main|switch-branch)
    git -C "${source_dir}" tag -a scanned-tag -m scanned
    if [[ "${MOCK_GH_MUTATION}" == switch-branch ]]; then
      git -C "${source_dir}" switch -qc concurrent-work
    fi
    printf 'Unscanned concurrent content\n' > "${source_dir}/unscanned.txt"
    git -C "${source_dir}" add unscanned.txt
    git -C "${source_dir}" commit -qm 'Concurrent unscanned commit'
    git -C "${source_dir}" tag -a unscanned-tag -m unscanned
    git -C "${source_dir}" config push.followTags true
    git -C "${source_dir}" config remote.origin.mirror true
    git -C "${source_dir}" config --add remote.origin.push refs/heads/concurrent-work
    ;;
  wrong-fetch) git -C "${source_dir}" remote set-url origin https://github.com/other/project.git ;;
  wrong-push) git -C "${source_dir}" remote set-url --push origin https://github.com/other/project.git ;;
  extra-push)
    git -C "${source_dir}" remote set-url --add --push origin https://github.com/acme/project.git
    git -C "${source_dir}" remote set-url --add --push origin https://github.com/other/project.git ;;
  rewrite) git -C "${source_dir}" config url.https://github.com/other/.pushInsteadOf https://github.com/acme/ ;;
esac
EOF
chmod +x "${mock_bin}/gh"

# Offline CLI contract double. Tests never install or call a real scanner.
export SCANNER_LOG="${test_root}/scanner.log"
export MOCK_SCAN_FAIL=""
cat > "${mock_bin}/gitleaks" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mode="$1"
source="$2"
shift 2
[[ "${mode}" == dir || "${mode}" == git ]]
printf '%s\n' "${mode}" >> "${SCANNER_LOG}"
config=false ignore=false inline=false redact=false unlimited=false history=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      grep -qx 'useDefault = true' "$2"
      config=true; shift 2 ;;
    --gitleaks-ignore-path) [[ -f "$2" && ! -s "$2" ]]; ignore=true; shift 2 ;;
    --ignore-gitleaks-allow) inline=true; shift ;;
    --redact) redact=true; shift ;;
    --no-banner) shift ;;
    --exit-code) [[ "$2" == 1 ]]; shift 2 ;;
    --max-target-megabytes) [[ "$2" == 0 ]]; unlimited=true; shift 2 ;;
    --log-opts=*)
      [[ "$1" == "--log-opts=--full-history -m $(git -C "${source}" rev-parse HEAD)" ]]
      history=true; shift ;;
    *) exit 2 ;;
  esac
done
[[ "${config}" == true && "${ignore}" == true && "${inline}" == true && "${redact}" == true && "${unlimited}" == true ]]
if [[ "${mode}" == git ]]; then [[ "${history}" == true ]]; fi
if [[ "${MOCK_SCAN_FAIL:-}" == "${mode}" ]]; then
  printf 'DO_NOT_ECHO_SCANNER_SECRET\n' >&2
  exit "${MOCK_SCAN_EXIT:-1}"
fi
if [[ "${MOCK_SCAN_SWITCH_BRANCH:-}" == true && "${mode}" == git ]]; then
  git -C "${source}" symbolic-ref HEAD refs/heads/other
fi
EOF
chmod +x "${mock_bin}/gitleaks"
export GIT_AUTHOR_NAME="Bootstrap Test" GIT_AUTHOR_EMAIL="bootstrap-test@example.invalid"
export GIT_COMMITTER_NAME="Bootstrap Test" GIT_COMMITTER_EMAIL="bootstrap-test@example.invalid"

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

# A targeted root ignore may exclude a regenerable integration link. Shared
# Skills are not blanket-ignored or automatically added by the publisher.
integration_target="${test_root}/integration-project"
mkdir -p "${integration_target}/.agent/runtime" "${integration_target}/.agents/skills"
cp "${repo_root}/templates/runtime.gitignore" "${integration_target}/.agent/runtime/.gitignore"
printf '# Shared Skills need separate review and commit.\n' > "${integration_target}/.agents/skills/.gitignore"
printf '/.agents/skills/understand\n' > "${integration_target}/.gitignore"
ln -s "../../.agent/runtime/understand-anything/repo/understand-anything-plugin/skills/understand" \
  "${integration_target}/.agents/skills/understand"
GIT_AUTHOR_NAME="Bootstrap Test" \
GIT_AUTHOR_EMAIL="bootstrap-test@example.invalid" \
GIT_COMMITTER_NAME="Bootstrap Test" \
GIT_COMMITTER_EMAIL="bootstrap-test@example.invalid" \
PATH="${mock_bin}:${PATH}" "${repo_root}/scripts/create-github.sh" \
  --source "${integration_target}" \
  --repo acme/project \
  --visibility private
git -C "${integration_target}" ls-files --error-unmatch .gitignore >/dev/null
[[ "$(git -C "${integration_target}" show HEAD:.gitignore)" == '/.agents/skills/understand' ]]
git -C "${integration_target}" ls-files --error-unmatch .agent/runtime/.gitignore >/dev/null
git -C "${integration_target}" ls-files --error-unmatch .agents/skills/.gitignore >/dev/null
if git -C "${integration_target}" ls-files --error-unmatch .agents/skills/understand >/dev/null 2>&1; then
  echo "create-github unexpectedly published a link into the ignored runtime tree" >&2
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

git -C "${dirty_target}" diff --cached --quiet
[[ ! -e "${dirty_target}/.git/index" ]]

# An outside tracked edit must also be detected before staging generated files.
tracked_target="${test_root}/tracked"
git init -q --initial-branch=main "${tracked_target}"
printf 'original\n' > "${tracked_target}/user-file.txt"
git -C "${tracked_target}" add user-file.txt
GIT_AUTHOR_NAME="Bootstrap Test" GIT_AUTHOR_EMAIL="bootstrap-test@example.invalid" \
GIT_COMMITTER_NAME="Bootstrap Test" GIT_COMMITTER_EMAIL="bootstrap-test@example.invalid" \
  git -C "${tracked_target}" commit -qm fixture
printf 'modified\n' > "${tracked_target}/user-file.txt"
cp "${repo_root}/templates/AGENTS.md" "${tracked_target}/AGENTS.md"
cp "${tracked_target}/.git/index" "${test_root}/index-before"
if PATH="${mock_bin}:${PATH}" "${repo_root}/scripts/create-github.sh" \
  --source "${tracked_target}" --repo acme/project --visibility private >/dev/null 2>&1; then
  echo "create-github unexpectedly published unrelated tracked changes" >&2
  exit 1
fi
cmp "${tracked_target}/.git/index" "${test_root}/index-before"

publish() {
  PATH="${mock_bin}:${PATH}" "${repo_root}/scripts/create-github.sh" \
    --source "$1" --repo acme/project --visibility private
}
expect_blocked() {
  local project="$1"
  local before_head
  before_head="$(git -C "${project}" rev-parse --verify HEAD 2>/dev/null || true)"
  if [[ -f "${project}/.git/index" ]]; then
    cp "${project}/.git/index" "${test_root}/blocked-index"
  else
    rm -f "${test_root}/blocked-index"
  fi
  if publish "${project}" > "${test_root}/blocked-output" 2>&1; then
    echo "Unexpected publication success for ${project}" >&2; exit 1
  fi
  [[ "$(git -C "${project}" rev-parse --verify HEAD 2>/dev/null || true)" == "${before_head}" ]]
  [[ -z "$(git -C "${project}" remote)" ]]
  if [[ -f "${test_root}/blocked-index" ]]; then
    cmp "${project}/.git/index" "${test_root}/blocked-index"
  else
    [[ ! -e "${project}/.git/index" ]]
  fi
  if grep -q DO_NOT_ECHO_SCANNER_SECRET "${test_root}/blocked-output"; then
    echo "Scanner output was exposed" >&2; exit 1
  fi
}
new_project() {
  git init -q --initial-branch=main "$1"
  printf 'Project policy\n' > "$1/AGENTS.md"
}

# A missing scanner is unverified even on a host with gitleaks installed.
missing_bin="${test_root}/missing-bin"
mkdir "${missing_bin}"
for tool in bash git python3; do ln -s "$(command -v "${tool}")" "${missing_bin}/${tool}"; done
ln -s "${mock_bin}/gh" "${missing_bin}/gh"
missing_target="${test_root}/missing-scanner"
new_project "${missing_target}"
if PATH="${missing_bin}" "${repo_root}/scripts/create-github.sh" \
  --source "${missing_target}" --repo acme/project --visibility private > "${test_root}/missing-output" 2>&1; then
  echo "Publication succeeded without a scanner" >&2; exit 1
fi
grep -q 'Secret scan unverified' "${test_root}/missing-output"
[[ ! -e "${missing_target}/.git/index" ]]
[[ -z "$(git -C "${missing_target}" remote)" ]]
if git -C "${missing_target}" rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "Publication created a commit without a scanner" >&2; exit 1
fi

# Both a finding and a scanner operational error fail closed, without staging.
scan_target="${test_root}/scan-failure"
new_project "${scan_target}"
export MOCK_SCAN_FAIL=dir
expect_blocked "${scan_target}"
grep -q 'candidate files' "${test_root}/blocked-output"
export MOCK_SCAN_EXIT=2
expect_blocked "${scan_target}"
unset MOCK_SCAN_EXIT

# Preserve an existing byte-for-byte index too, not just the unborn case.
git -C "${scan_target}" add AGENTS.md
git -C "${scan_target}" commit -qm fixture
printf 'Updated policy\n' >> "${scan_target}/AGENTS.md"
expect_blocked "${scan_target}"

# Scan all history that main will publish, including content later deleted.
history_target="${test_root}/history"
new_project "${history_target}"
printf 'historical fixture\n' > "${history_target}/deleted.txt"
git -C "${history_target}" add AGENTS.md deleted.txt
git -C "${history_target}" commit -qm fixture
git -C "${history_target}" rm -q deleted.txt
git -C "${history_target}" commit -qm removal
export MOCK_SCAN_FAIL=git
: > "${SCANNER_LOG}"
expect_blocked "${history_target}"
grep -qx dir "${SCANNER_LOG}"
grep -qx git "${SCANNER_LOG}"
grep -q 'existing history' "${test_root}/blocked-output"
export MOCK_SCAN_FAIL=""
: > "${SCANNER_LOG}"
publish "${history_target}" > /dev/null
[[ "$(git -C "${history_target}" rev-list --count HEAD)" == 2 ]]
[[ "$(printf 'dir\ngit')" == "$(< "${SCANNER_LOG}")" ]]

# No user staging can be included or disturbed, even for allowlisted paths.
staged_target="${test_root}/staged"
new_project "${staged_target}"
printf 'user data\n' > "${staged_target}/user.txt"
git -C "${staged_target}" add user.txt
expect_blocked "${staged_target}"

# Shared Skill sources are review candidates, not automatic skeleton files.
skill_target="${test_root}/shared-skills"
new_project "${skill_target}"
mkdir -p "${skill_target}/.agents/skills/custom"
printf 'Shared Skill\n' > "${skill_target}/.agents/skills/custom/SKILL.md"
expect_blocked "${skill_target}"
grep -q 'separately authorized review and commit' "${test_root}/blocked-output"

# Exact allowlisted links and linked parent directories must never be followed.
for kind in regular broken parent nested; do
  link_target="${test_root}/link-${kind}"
  new_project "${link_target}"
  case "${kind}" in
    regular) ln -s AGENTS.md "${link_target}/CLAUDE.md" ;;
    broken) ln -s absent "${link_target}/.gitignore" ;;
    parent)
      mkdir -p "${test_root}/external-policies/policies"
      printf 'External\n' > "${test_root}/external-policies/policies/git.md"
      ln -s "${test_root}/external-policies" "${link_target}/.agent" ;;
    nested)
      git init -q "${link_target}/.agent"
      mkdir -p "${link_target}/.agent/policies"
      printf 'Nested\n' > "${link_target}/.agent/policies/git.md" ;;
  esac
  expect_blocked "${link_target}"
  grep -Eq 'symbolic link|nested repository' "${test_root}/blocked-output"
done

large_target="${test_root}/oversized"
new_project "${large_target}"
python3 - "${large_target}/AGENTS.md" <<'PY'
import sys
with open(sys.argv[1], 'wb') as stream:
    stream.truncate(10 * 1024 * 1024 + 1)
PY
expect_blocked "${large_target}"
grep -q 'exceeds 10 MiB' "${test_root}/blocked-output"

# Relevant JSON validation uses tracked blobs, not unrelated ignored data.
json_target="${test_root}/invalid-json"
new_project "${json_target}"
printf '{invalid json\n' > "${json_target}/package.json"
git -C "${json_target}" add AGENTS.md package.json
git -C "${json_target}" commit -qm fixture
expect_blocked "${json_target}"
grep -q 'invalid JSON' "${test_root}/blocked-output"

# Configuration and shell syntax failures stop before scanning or staging.
for extension in yaml toml sh; do
  config_target="${test_root}/invalid-${extension}"
  new_project "${config_target}"
  case "${extension}" in
    yaml) printf 'value: [unterminated\n' > "${config_target}/config.yaml" ;;
    toml) printf 'value = [unterminated\n' > "${config_target}/config.toml" ;;
    sh) printf 'if true; then\n' > "${config_target}/config.sh" ;;
  esac
  git -C "${config_target}" add AGENTS.md "config.${extension}"
  git -C "${config_target}" commit -qm fixture
  expect_blocked "${config_target}"
  grep -Eq 'invalid YAML|invalid TOML|TOML validation unverified|invalid shell syntax' "${test_root}/blocked-output"
done

# Existing tracked symlinks/gitlinks cannot slip past the skeleton allowlist.
tracked_link="${test_root}/tracked-link"
new_project "${tracked_link}"
ln -s AGENTS.md "${tracked_link}/other-link"
git -C "${tracked_link}" add AGENTS.md other-link
git -C "${tracked_link}" commit -qm fixture
expect_blocked "${tracked_link}"
grep -q 'symlink, nested repository' "${test_root}/blocked-output"

# User hooks are never bypassed to publish a scanned snapshot.
for kind in active configured; do
  hook_target="${test_root}/hook-${kind}"
  new_project "${hook_target}"
  if [[ "${kind}" == active ]]; then
    printf '#!/usr/bin/env bash\nexit 0\n' > "${hook_target}/.git/hooks/pre-commit"
    chmod +x "${hook_target}/.git/hooks/pre-commit"
  else
    git -C "${hook_target}" config core.hooksPath custom-hooks
  fi
  expect_blocked "${hook_target}"
  grep -q 'no hooks were bypassed' "${test_root}/blocked-output"
done

# Successful scanning commits the snapshot and leaves the real index clean.
: > "${SCANNER_LOG}"
publish "${scan_target}" > /dev/null
git -C "${scan_target}" diff --quiet
git -C "${scan_target}" diff --cached --quiet
[[ "$(git -C "${scan_target}" rev-list --count HEAD)" == 2 ]]
grep -qx dir "${SCANNER_LOG}"
grep -qx git "${SCANNER_LOG}"

# Delayed gh must publish exactly the scanned commit, whether or not the
# publisher needed to create a commit and whether local main advanced/switched.
for initial in unborn changed unchanged; do
  for mutation in advance-main switch-branch; do
    concurrent="${test_root}/concurrent-${initial}-${mutation}"
    new_project "${concurrent}"
    if [[ "${initial}" != unborn ]]; then
      git -C "${concurrent}" add AGENTS.md
      git -C "${concurrent}" commit -qm fixture
      before="$(git -C "${concurrent}" rev-parse HEAD)"
      if [[ "${initial}" == changed ]]; then
        printf 'Reviewed update\n' >> "${concurrent}/AGENTS.md"
      fi
    fi
    export MOCK_GH_MUTATION="${mutation}"
    : > "${PUSH_LOG}"
    publish "${concurrent}" > /dev/null
    unset MOCK_GH_MUTATION
    scanned="$(< "${concurrent}/.git/scanned-publish-sha")"
    [[ "$(< "${PUSH_LOG}")" == "push --no-follow-tags origin ${scanned}:refs/heads/main" ]]
    [[ "$(git --git-dir="${concurrent}.git-remote" rev-parse refs/heads/main)" == "${scanned}" ]]
    [[ "$(git --git-dir="${concurrent}.git-remote" for-each-ref --format='%(refname)')" == refs/heads/main ]]
    if git --git-dir="${concurrent}.git-remote" cat-file -e "${scanned}:unscanned.txt" 2>/dev/null; then
      echo 'Unscanned file reached origin' >&2; exit 1
    fi
    # The concurrent commit itself must not be sent, even as an unreachable object.
    local_head="$(git -C "${concurrent}" rev-parse HEAD)"
    [[ "${local_head}" != "${scanned}" ]]
    if git --git-dir="${concurrent}.git-remote" cat-file -e "${local_head}" 2>/dev/null; then
      echo 'Unscanned commit reached origin' >&2; exit 1
    fi
    case "${initial}" in
      unborn) [[ -z "$(git -C "${concurrent}" show -s --format=%P "${scanned}")" ]] ;;
      changed) [[ "$(git -C "${concurrent}" show -s --format=%P "${scanned}")" == "${before}" ]] ;;
      unchanged) [[ "${scanned}" == "${before}" ]] ;;
    esac
    [[ -f "${concurrent}/unscanned.txt" ]]
    git -C "${concurrent}" diff --cached --quiet
    git -C "${concurrent}" diff --quiet
    if [[ "${mutation}" == switch-branch ]]; then
      [[ "$(git -C "${concurrent}" branch --show-current)" == concurrent-work ]]
    else
      [[ "$(git -C "${concurrent}" rev-parse main)" == "${local_head}" ]]
    fi
    [[ ! -e "${concurrent}/.git/config.lock" ]]
  done
done

# A same-SHA branch switch during inspection must not receive the bootstrap
# commit. Unlike a HEAD-SHA comparison alone, the symbolic-branch guard catches it.
branch_target="${test_root}/same-sha-branch"
new_project "${branch_target}"
git -C "${branch_target}" add AGENTS.md
git -C "${branch_target}" commit -qm fixture
git -C "${branch_target}" branch other
printf 'Reviewed update\n' >> "${branch_target}/AGENTS.md"
export MOCK_SCAN_SWITCH_BRANCH=true
: > "${GH_LOG}"
expect_blocked "${branch_target}"
unset MOCK_SCAN_SWITCH_BRANCH
grep -q 'Branch changed during inspection' "${test_root}/blocked-output"
[[ ! -s "${GH_LOG}" ]]
[[ "$(git -C "${branch_target}" rev-parse main)" == "$(git -C "${branch_target}" rev-parse other)" ]]
[[ ! -e "${branch_target}/.git/index.lock" ]]

# Simulate writers/hooks at the last pre-commit boundary and just after commit.
# No publication is allowed if the resulting commit has a different tree or
# parent, including an unexpected parent for what should have been a root commit.
for initial in unborn changed; do
  for mutation in tree parent after-commit; do
    commit_target="${test_root}/commit-${initial}-${mutation}"
    new_project "${commit_target}"
    if [[ "${initial}" == changed ]]; then
      git -C "${commit_target}" add AGENTS.md
      git -C "${commit_target}" commit -qm fixture
      cp "${commit_target}/.git/index" "${test_root}/commit-index-before"
      printf 'Reviewed update\n' >> "${commit_target}/AGENTS.md"
    fi
    export MOCK_COMMIT_MUTATION="${mutation}"
    : > "${GH_LOG}"
    : > "${PUSH_LOG}"
    if publish "${commit_target}" > "${test_root}/commit-output" 2>&1; then
      echo "Published a mismatched ${mutation} commit" >&2; exit 1
    fi
    unset MOCK_COMMIT_MUTATION
    if ! grep -q 'Commit no longer matches the scanned tree and expected parent' "${test_root}/commit-output"; then
      printf 'Unexpected failure for %s/%s\n' "${initial}" "${mutation}" >&2
      cat "${test_root}/commit-output" >&2
      exit 1
    fi
    [[ ! -s "${GH_LOG}" && ! -s "${PUSH_LOG}" ]]
    [[ -z "$(git -C "${commit_target}" remote)" ]]
    [[ ! -e "${commit_target}/.git/index.lock" ]]
    if [[ "${initial}" == changed ]]; then
      cmp "${commit_target}/.git/index" "${test_root}/commit-index-before"
    else
      [[ ! -e "${commit_target}/.git/index" ]]
    fi
  done
done

# Creation must not redirect the explicit requested repository, even through
# push-only URLs, extra destinations or Git URL-rewrite configuration.
for mutation in wrong-fetch wrong-push extra-push rewrite; do
  remote_target="${test_root}/remote-${mutation}"
  new_project "${remote_target}"
  export MOCK_GH_MUTATION="${mutation}"
  : > "${PUSH_LOG}"
  if publish "${remote_target}" > "${test_root}/remote-output" 2>&1; then
    echo "Published to a changed origin: ${mutation}" >&2; exit 1
  fi
  unset MOCK_GH_MUTATION
  grep -q 'origin.*refusing to push' "${test_root}/remote-output"
  [[ ! -s "${PUSH_LOG}" ]]
  [[ -z "$(git --git-dir="${remote_target}.git-remote" for-each-ref)" ]]
  [[ ! -e "${remote_target}/.git/config.lock" ]]
done

# Multiple blobs (binary/empty/executable and awkward paths included) use one
# persistent batch process. The resulting objects must still match the source.
batch_target="${test_root}/batch"
new_project "${batch_target}"
mkdir "${batch_target}/assets"
python3 - "${batch_target}" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
(root / 'assets/empty').touch()
(root / 'assets/binary').write_bytes(b'\0\xff\n\0payload\n')
(root / 'assets/tab\tline\nbreak').write_bytes(b'awkward path\n')
(root / 'script.sh').write_text('#!/usr/bin/env bash\ntrue\n')
(root / 'script.sh').chmod(0o755)
PY
git -C "${batch_target}" add .
git -C "${batch_target}" commit -qm fixture
: > "${BLOB_LOG}"
publish "${batch_target}" > /dev/null
[[ "$(< "${BLOB_LOG}")" == 'cat-file --batch' ]]
[[ "$(git --git-dir="${batch_target}.git-remote" rev-parse 'main^{tree}')" == "$(git -C "${batch_target}" rev-parse 'HEAD^{tree}')" ]]
for failure in oversized truncated wrong-type missing; do
  batch_failure="${test_root}/batch-${failure}"
  new_project "${batch_failure}"
  export MOCK_BATCH_FAILURE="${failure}"
  : > "${GH_LOG}"
  expect_blocked "${batch_failure}"
  unset MOCK_BATCH_FAILURE
  if [[ "${failure}" == oversized ]]; then
    grep -q 'exceeds 10 MiB' "${test_root}/blocked-output"
  else
    grep -Eq 'invalid Git blob response|incomplete Git blob response' "${test_root}/blocked-output"
  fi
  [[ ! -s "${GH_LOG}" ]]
done

echo "create-github tests passed"
