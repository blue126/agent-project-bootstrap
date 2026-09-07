#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:?TMPDIR must be set}/github-connect.XXXXXX")"
trap 'rm -rf "${test_root}"' EXIT
export HOME="${test_root}/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="${test_root}/global-config"
export GIT_AUTHOR_NAME="Bootstrap Test" GIT_AUTHOR_EMAIL="bootstrap-test@example.invalid"
export GIT_COMMITTER_NAME="${GIT_AUTHOR_NAME}" GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"
REAL_GIT="$(command -v git)"
export REAL_GIT
export MOCK_STATE="${test_root}/remote" GH_LOG="${test_root}/gh.log" GIT_LOG="${test_root}/git.log"
mkdir -p "${HOME}" "${test_root}/bin"
printf '# untouched global config\n' > "${GIT_CONFIG_GLOBAL}"
cp "${GIT_CONFIG_GLOBAL}" "${test_root}/global-before"

cat > "${test_root}/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${GH_LOG}"
if [[ "$*" == 'auth status --hostname github.com' ]]; then
  [[ "${MOCK_AUTH_FAIL:-0}" != 1 ]]
elif [[ "$1" == api && "$2" == --hostname && "$3" == github.com && "$4" == repos/acme/project && "$5" == --jq ]]; then
  if [[ "${MOCK_API_FAIL:-0}" == 1 ]]; then
    printf 'gh: Forbidden (HTTP 403)\n' >&2; exit 1
  fi
  if [[ ! -f "${MOCK_STATE}" || "${MOCK_VERIFY_FAIL:-0}" == 1 ]]; then
    printf 'gh: Not Found (HTTP 404)\n' >&2; exit 1
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${MOCK_REPO:-acme/project}" "${MOCK_URL:-https://github.com/acme/project.git}" \
    'git@github.com:acme/project.git' "${MOCK_PUSH:-true}" "${MOCK_ARCHIVED:-false}" \
    "${MOCK_DISABLED:-false}" "${MOCK_VISIBILITY:-private}"
elif [[ "$*" == 'repo create acme/project --private' ]]; then
  [[ "${GH_HOST:-}" == github.com ]]
  [[ ! -f "${MOCK_STATE}" ]] || { printf 'Duplicate remote creation attempted\n' >&2; exit 99; }
  touch "${MOCK_STATE}"
  [[ "${MOCK_CREATE_FAIL:-0}" != 1 ]]
else
  printf 'Unexpected gh call: %s\n' "$*" >&2; exit 99
fi
EOF
cat > "${test_root}/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${GIT_LOG}"
# Setup uses REAL_GIT. Every helper invocation must stay publish-free.
for argument in "$@"; do
  case "${argument}" in
    add|commit|push|reset|checkout|switch|stash)
      if [[ "${argument}" == add && " $* " == *' remote add '* ]]; then continue; fi
      printf 'Forbidden git mutation: %s\n' "$*" >&2; exit 98 ;;
  esac
done
if [[ "${MOCK_REMOTE_FAIL:-0}" == 1 && " $* " == *' remote add '* ]]; then exit 1; fi
exec "${REAL_GIT}" "$@"
EOF
chmod +x "${test_root}/bin/gh" "${test_root}/bin/git"
export PATH="${test_root}/bin:${PATH}"
helper="${repo_root}/scripts/create-github.sh"

fail() { printf '%s\n' "$*" >&2; exit 1; }
reject() {
  if "$@" > "${test_root}/output" 2>&1; then fail "Unexpected success: $*"; fi
}
reset_remote() {
  rm -f "${MOCK_STATE}"
  : > "${GH_LOG}"
  : > "${GIT_LOG}"
}
assert_no_publish() {
  if grep -Eq '(^| )(commit|push|reset|stash|checkout|switch)( |$)|(^| )add --' "${GIT_LOG}"; then
    fail 'Connect-only helper tried to change published/index state'
  fi
  cmp "${GIT_CONFIG_GLOBAL}" "${test_root}/global-before"
}
assert_no_local_git() { [[ ! -e "$1/.git" ]] || fail 'Failure initialized local Git'; }

# CLI opt-in is explicit and mutually exclusive; invalid arguments do no IO.
reset_remote
empty="${test_root}/empty"
mkdir -p "${empty}"
reject "${helper}" --create-only --repo acme/project --source "${empty}"
reject "${helper}" --attach-only --repo acme/project
reject "${helper}" --attach-only --source "${empty}"
reject "${helper}" --create-only --attach-only --repo acme/project --source "${empty}" --visibility private
reject "${helper}" --attach-only --repo acme/../project --source "${empty}"
reject "${helper}" --attach-only --repo acme/project --source "${empty}" --visibility bogus
[[ ! -s "${GH_LOG}" ]]
assert_no_local_git "${empty}"

# Empty remote creation never publishes, even with an unrelated untracked file.
printf 'keep me\n' > "${empty}/user.txt"
"${helper}" --create-only --repo acme/project --source "${empty}" --visibility private
[[ "$("${REAL_GIT}" -C "${empty}" remote get-url origin)" == https://github.com/acme/project.git ]]
[[ ! -e "${empty}/.git/index" ]]
if "${REAL_GIT}" -C "${empty}" rev-parse --verify HEAD >/dev/null 2>&1; then fail 'Connect-only created a commit'; fi
[[ "$(grep -c '^repo create ' "${GH_LOG}")" == 1 ]]
cp "${empty}/.git/config" "${test_root}/config-before"
"${helper}" --create-only --repo acme/project --source "${empty}" --visibility private > "${test_root}/output"
grep -q 'Already connected' "${test_root}/output"
cmp "${empty}/.git/config" "${test_root}/config-before"
[[ "$(grep -c '^repo create ' "${GH_LOG}")" == 1 ]]
assert_no_publish

# Existing arbitrary branches, commits, index and dirty/untracked content survive.
dirty="${test_root}/dirty"
mkdir -p "${dirty}"
"${REAL_GIT}" -C "${dirty}" init -q --initial-branch=topic
printf 'base\n' > "${dirty}/tracked"
"${REAL_GIT}" -C "${dirty}" add tracked
"${REAL_GIT}" -C "${dirty}" commit -qm fixture
printf 'staged\n' > "${dirty}/tracked"
"${REAL_GIT}" -C "${dirty}" add tracked
printf 'unstaged\n' >> "${dirty}/tracked"
printf 'untracked\n' > "${dirty}/untracked"
cp "${dirty}/.git/index" "${test_root}/index-before"
cp "${dirty}/tracked" "${test_root}/tracked-before"
before_head="$("${REAL_GIT}" -C "${dirty}" rev-parse HEAD)"
"${helper}" --attach-only --repo acme/project --source "${dirty}"
cmp "${dirty}/.git/index" "${test_root}/index-before"
cmp "${dirty}/tracked" "${test_root}/tracked-before"
[[ "$("${REAL_GIT}" -C "${dirty}" rev-parse HEAD)" == "${before_head}" ]]
[[ "$("${REAL_GIT}" -C "${dirty}" branch --show-current)" == topic ]]
assert_no_publish

# Same SSH origin is idempotent; no guessing, rewriting, or replacing URLs.
"${REAL_GIT}" -C "${dirty}" remote set-url origin git@github.com:acme/project.git
cp "${dirty}/.git/config" "${test_root}/config-before"
"${helper}" --attach-only --repo acme/project --source "${dirty}"
cmp "${dirty}/.git/config" "${test_root}/config-before"
for url in https://github.com/acme/other.git https://example.invalid/acme/project.git invalid ''; do
  "${REAL_GIT}" -C "${dirty}" config remote.origin.url "${url}"
  cp "${dirty}/.git/config" "${test_root}/config-before"
  reject "${helper}" --create-only --repo acme/project --source "${dirty}" --visibility private
  cmp "${dirty}/.git/config" "${test_root}/config-before"
  cmp "${dirty}/.git/index" "${test_root}/index-before"
done
"${REAL_GIT}" -C "${dirty}" config --unset-all remote.origin.url
reject "${helper}" --attach-only --repo acme/project --source "${dirty}"
"${REAL_GIT}" -C "${dirty}" config remote.origin.url https://github.com/acme/project.git
"${REAL_GIT}" -C "${dirty}" config remote.origin.pushurl https://github.com/acme/other.git
reject "${helper}" --attach-only --repo acme/project --source "${dirty}"
"${REAL_GIT}" -C "${dirty}" config --unset-all remote.origin.pushurl
"${REAL_GIT}" -C "${dirty}" config --add remote.origin.url https://github.com/acme/project.git
reject "${helper}" --attach-only --repo acme/project --source "${dirty}"

# Authentication/read failures, unavailable permission, and invalid metadata fail
# before local initialization; create-only never treats a 403 as an absent repo.
for condition in MOCK_AUTH_FAIL=1 MOCK_API_FAIL=1 MOCK_PUSH=false MOCK_PUSH=null MOCK_ARCHIVED=true MOCK_DISABLED=true MOCK_REPO=acme/other MOCK_URL=https://evil.invalid/acme/project.git MOCK_VISIBILITY=public; do
  candidate="${test_root}/${condition}"
  mkdir -p "${candidate}"
  reject env "${condition}" "${helper}" --create-only --repo acme/project --source "${candidate}" --visibility private
  assert_no_local_git "${candidate}"
done
reset_remote
absent="${test_root}/absent"
mkdir -p "${absent}"
reject "${helper}" --attach-only --repo acme/project --source "${absent}"
assert_no_local_git "${absent}"
if grep -q '^repo create ' "${GH_LOG}"; then fail 'Attach-only attempted creation'; fi

# Invalid local Git state and nested worktrees must not touch their parent or gh.
reset_remote
mkdir -p "${dirty}/nested" "${test_root}/invalid/.git"
reject "${helper}" --create-only --repo acme/project --source "${dirty}/nested" --visibility private
reject "${helper}" --attach-only --repo acme/project --source "${test_root}/invalid"
"${REAL_GIT}" init -q --bare "${test_root}/bare"
reject "${helper}" --attach-only --repo acme/project --source "${test_root}/bare"
reject env GIT_INDEX_FILE="${test_root}/redirect-index" "${helper}" --attach-only --repo acme/project --source "${absent}"
[[ ! -s "${GH_LOG}" ]]
[[ ! -e "${test_root}/redirect-index" ]]

# Server success followed by a local failure is recovered by checking actual
# metadata, not by blindly issuing a second repository creation request.
reset_remote
partial="${test_root}/partial"
mkdir -p "${partial}"
reject env MOCK_REMOTE_FAIL=1 "${helper}" --create-only --repo acme/project --source "${partial}" --visibility private
[[ -f "${MOCK_STATE}" && ! -e "${partial}/.git/index" ]]
"${helper}" --create-only --repo acme/project --source "${partial}" --visibility private
[[ "$(grep -c '^repo create ' "${GH_LOG}")" == 1 ]]
assert_no_publish
reset_remote
uncertain="${test_root}/uncertain"
mkdir -p "${uncertain}"
reject env MOCK_CREATE_FAIL=1 "${helper}" --create-only --repo acme/project --source "${uncertain}" --visibility private
assert_no_local_git "${uncertain}"
"${helper}" --create-only --repo acme/project --source "${uncertain}" --visibility private
[[ "$(grep -c '^repo create ' "${GH_LOG}")" == 1 ]]
assert_no_publish
reset_remote
unverified="${test_root}/unverified"
mkdir -p "${unverified}"
reject env MOCK_VERIFY_FAIL=1 "${helper}" --create-only --repo acme/project --source "${unverified}" --visibility private
assert_no_local_git "${unverified}"
"${helper}" --attach-only --repo acme/project --source "${unverified}"
[[ "$(grep -c '^repo create ' "${GH_LOG}")" == 1 ]]
assert_no_publish

printf 'create-github connect-only tests passed\n'
