#!/usr/bin/env bash
set -euo pipefail

repository=""
visibility=""
source_dir="$(pwd)"
source_explicit=false
mode=publish

usage() {
  cat <<'EOF'
Usage: scripts/create-github.sh --repo OWNER/REPOSITORY --visibility VISIBILITY [--source DIR]

Without a mode flag, publish the bootstrap commit and push main (legacy mode).

Connect-only modes never stage, commit, push, or change an existing origin:
  --create-only           Create an empty repository, or reconnect on retry
  --attach-only           Attach to an existing, verified writable repository
Both require explicit --repo and --source. --create-only also requires visibility.
GitHub.com metadata is verified before adding origin; no default branch is required.

  --repo REPO              Explicit OWNER/REPOSITORY target on GitHub.com
  --visibility VISIBILITY  private, public, or internal (optional for --attach-only)
  --source DIR             Local project directory (default only in legacy mode)
  -h, --help               Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "--repo requires OWNER/REPOSITORY" >&2; exit 2; }
      repository="$2"
      shift 2
      ;;
    --visibility)
      [[ $# -ge 2 ]] || { echo "--visibility requires private, public, or internal" >&2; exit 2; }
      visibility="$2"
      shift 2
      ;;
    --source)
      [[ $# -ge 2 ]] || { echo "--source requires a directory" >&2; exit 2; }
      source_dir="$2"
      source_explicit=true
      shift 2
      ;;
    --create-only|--attach-only)
      [[ "${mode}" == publish ]] || { echo "Choose only one connect-only mode" >&2; exit 2; }
      mode="${1#--}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "${repository}" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
  echo "--repo must be an explicit OWNER/REPOSITORY value" >&2
  exit 2
fi

if [[ "${mode}" != attach-only || -n "${visibility}" ]]; then
  case "${visibility}" in
    private|public|internal) ;;
    *)
      echo "--visibility must be private, public, or internal" >&2
      exit 2
      ;;
  esac
fi
if [[ "${mode}" != publish ]]; then
  [[ "${source_explicit}" == true && -n "${source_dir}" ]] || {
    echo "Connect-only modes require explicit --source DIR" >&2; exit 2;
  }
fi
[[ "${repository}" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$ && "${repository##*/}" != . && "${repository##*/}" != .. ]] || {
  echo "Invalid GitHub OWNER/REPOSITORY" >&2; exit 2;
}

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "gh is required" >&2; exit 1; }

[[ -d "${source_dir}" ]] || { echo "Source directory does not exist: ${source_dir}" >&2; exit 1; }
source_dir="$(cd "${source_dir}" && pwd -P)"

connect_only() {
  # Reject Git environment redirects rather than accidentally modifying another
  # repository/index. All writes below are init and remote-add in this project.
  for variable in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE; do
    [[ -z "${!variable:-}" ]] || { echo "Unset ${variable} before connecting a project" >&2; exit 1; }
  done
  local git_root="" has_git=false origin_exists=false origin_url="" push_url=""
  if git_root="$(git -C "${source_dir}" rev-parse --show-toplevel 2>/dev/null)"; then
    [[ "$(cd "${git_root}" && pwd -P)" == "${source_dir}" ]] || {
      echo "Source is nested inside another Git root; select the repository root" >&2; exit 1;
    }
    has_git=true
    local config_path
    config_path="$(git -C "${source_dir}" rev-parse --git-path config)"
    [[ "${config_path}" == /* ]] || config_path="${source_dir}/${config_path}"
    [[ ! -L "${config_path}" && -w "${config_path}" ]] || {
      echo "Local Git config must be writable and not a symbolic link" >&2; exit 1;
    }
    if git -C "${source_dir}" remote | grep -qx origin; then
      origin_exists=true
      origin_url="$(git -C "${source_dir}" remote get-url --all origin)" || {
        echo "origin exists but has no valid URL; refusing to change it" >&2; exit 1;
      }
      push_url="$(git -C "${source_dir}" remote get-url --push --all origin)" || exit 1
      # Both fetch and push URLs must resolve to this exact explicit target.
      # Multiple URLs, credentials, aliases and non-GitHub hosts fail closed.
      local candidate path
      for candidate in "${origin_url}" "${push_url}"; do
        case "${candidate}" in
          https://github.com/*) path="${candidate#https://github.com/}" ;;
          git@github.com:*) path="${candidate#git@github.com:}" ;;
          ssh://git@github.com/*) path="${candidate#ssh://git@github.com/}" ;;
          *) echo "origin is not a supported GitHub.com URL; refusing to change it" >&2; exit 1 ;;
        esac
        path="${path%.git}"
        [[ "$(printf '%s' "${path}" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "${repository}" | tr '[:upper:]' '[:lower:]')" ]] || {
          echo "origin does not match ${repository}; refusing to change it" >&2; exit 1;
        }
      done
    fi
  elif [[ -e "${source_dir}/.git" || -L "${source_dir}/.git" ]] || git -C "${source_dir}" rev-parse --git-dir >/dev/null 2>&1; then
    echo "Source has invalid or bare Git metadata; refusing to initialize it" >&2
    exit 1
  fi
  [[ -w "${source_dir}" ]] || { echo "Source directory is not writable" >&2; exit 1; }
  gh auth status --hostname github.com >/dev/null || { echo "GitHub authentication preflight failed" >&2; exit 1; }

  local metadata api_error actual_repo clone_url ssh_url writable archived disabled actual_visibility extra
  api_error="$(mktemp "${TMPDIR:?TMPDIR must be set}/create-github.XXXXXX")"
  trap 'rm -f -- "${api_error}"' EXIT
  # Read before creating, including on retries after a remote-only success.
  # Only an explicit HTTP 404 permits creation, not auth/network/other errors.
  read_metadata() {
    gh api --hostname github.com "repos/${repository}" --jq \
      '[.full_name, .clone_url, .ssh_url, .permissions.push, .archived, .disabled, .visibility] | @tsv' 2>"${api_error}"
  }
  if ! metadata="$(read_metadata)"; then
    if [[ "${mode}" != create-only || "${origin_exists}" == true ]] || ! grep -Eq '\(HTTP 404\)' "${api_error}"; then
      cat "${api_error}" >&2
      echo "Cannot verify ${repository}; no local connection was changed" >&2
      exit 1
    fi
    # No --source/--remote/--push: the GitHub repository is intentionally empty.
    if ! GH_HOST=github.com gh repo create "${repository}" "--${visibility}"; then
      echo "Creation failed or its result is uncertain. Retry this command to verify the actual repository before any new creation." >&2
      exit 1
    fi
    if ! metadata="$(read_metadata)"; then
      cat "${api_error}" >&2
      echo "Remote creation succeeded but verification failed. Retry --create-only or --attach-only; nothing was staged or pushed." >&2
      exit 1
    fi
  fi
  IFS=$'\t' read -r actual_repo clone_url ssh_url writable archived disabled actual_visibility extra <<< "${metadata}"
  [[ "${metadata}" != *$'\n'* && -z "${extra}" && \
     "$(printf '%s' "${actual_repo}" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "${repository}" | tr '[:upper:]' '[:lower:]')" && \
     "${clone_url}" == "https://github.com/${actual_repo}.git" && \
     "${ssh_url}" == "git@github.com:${actual_repo}.git" && \
     "${writable}" == true && "${archived}" == false && "${disabled}" == false ]] || {
    echo "Repository metadata is mismatched, incomplete, read-only, archived, or disabled; refusing to connect" >&2; exit 1;
  }
  [[ -z "${visibility}" || "${actual_visibility}" == "${visibility}" ]] || {
    echo "Verified repository visibility differs from --visibility; refusing to connect" >&2; exit 1;
  }
  if [[ "${origin_exists}" == true ]]; then
    echo "Already connected to verified GitHub repository ${actual_repo}; origin is unchanged"
  else
    if [[ "${has_git}" == false ]]; then
      git -C "${source_dir}" init --quiet
      git -C "${source_dir}" symbolic-ref HEAD refs/heads/main
    fi
    if ! git -C "${source_dir}" remote add origin "${clone_url}"; then
      echo "Verified remote exists but adding origin failed. Retry --attach-only after resolving the local error; no commit or push occurred." >&2
      exit 1
    fi
    echo "Connected verified GitHub repository ${actual_repo}; no files staged, committed, or pushed"
  fi
  rm -f -- "${api_error}"
  trap - EXIT
}

if [[ "${mode}" != publish ]]; then
  connect_only
  exit 0
fi

# Publication must inspect the selected repository, never an inherited Git index.
for variable in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE; do
  [[ -z "${!variable:-}" ]] || { echo "Unset ${variable} before publishing" >&2; exit 1; }
done
export GIT_NO_REPLACE_OBJECTS=1
export GIT_OPTIONAL_LOCKS=0
command -v python3 >/dev/null 2>&1 || { echo "python3 is required for publication validation" >&2; exit 1; }
command -v gitleaks >/dev/null 2>&1 || {
  echo "Secret scan unverified: local gitleaks is required; no scanner was installed. Publication stopped." >&2
  exit 1
}
git_root="$(git -C "${source_dir}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "${git_root}" ]]; then
  [[ "$(cd "${git_root}" && pwd -P)" == "${source_dir}" ]] || {
    echo "Source must be the Git repository root" >&2; exit 1;
  }
elif [[ -e "${source_dir}/.git" || -L "${source_dir}/.git" ]]; then
  echo "Source has invalid Git metadata; refusing to initialize it" >&2; exit 1
fi

if ! git -C "${source_dir}" rev-parse --git-dir >/dev/null 2>&1; then
  # Set the initial branch after init rather than probing for
  # --initial-branch: the probe exits non-zero, which pipefail turns into a
  # permanently false condition, and this form works on every git version.
  git -C "${source_dir}" init --quiet
  git -C "${source_dir}" symbolic-ref HEAD refs/heads/main
fi

if git -C "${source_dir}" remote get-url origin >/dev/null 2>&1; then
  echo "origin already exists; refusing to replace it" >&2
  exit 1
fi

current_branch="$(git -C "${source_dir}" symbolic-ref --quiet --short HEAD || true)"
if [[ "${current_branch}" != main ]]; then
  echo "GitHub repository creation requires the local branch to be main; found '${current_branch:-detached HEAD}'" >&2
  exit 1
fi

if ! git -C "${source_dir}" diff --cached --quiet; then
  echo "The Git index already contains staged changes; refusing to include them in the bootstrap commit" >&2
  exit 1
fi

# Only the generated policy skeleton is automatically staged. Shared Skills
# and other project assets are candidates for a separately authorized review
# and commit, not implicit additions to this allowlist (even if not ignored).
bootstrap_paths=(
  ".gitignore"
  "AGENTS.md"
  "CLAUDE.md"
  ".agent/bootstrap.yml"
  ".agent/policies/core.md"
  ".agent/policies/git.md"
  ".agent/policies/workflow-selection.md"
  ".agent/runtime/.gitignore"
  ".agents/skills/.gitignore"
  ".agent/governance/sensitive-paths.txt"
  ".github/workflows/agent-governance-observe.yml"
)
# Refuse links (including broken links and linked parent directories), special
# files and embedded repositories before Git can follow or stage them.
python3 - "${source_dir}" "${bootstrap_paths[@]}" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for relative in sys.argv[2:]:
    path = root
    for component in pathlib.PurePosixPath(relative).parts:
        path /= component
        if path.is_symlink():
            sys.exit(f"Publication refused: symbolic link at {str(path.relative_to(root))!r}")
        if path.is_dir() and ((path / '.git').exists() or (path / '.git').is_symlink()):
            sys.exit(f"Publication refused: nested repository at {str(path.relative_to(root))!r}")
    if path.exists() and not path.is_file():
        sys.exit(f"Publication refused: expected a regular skeleton file at {relative!r}")
PY
paths_to_stage=()
for path in "${bootstrap_paths[@]}"; do
  [[ -f "${source_dir}/${path}" ]] && paths_to_stage+=("${path}")
done
printf '%s\n' 'Skeleton-only publication: shared Skills and other assets require a separately authorized review and commit; they will not be staged automatically.'

# Preflight outside files before staging anything. Rejections must not leave
# generated files staged in a previously untouched index.
check_publish_path() {
  local allowed
  if [[ ${#paths_to_stage[@]} -gt 0 ]]; then
    for allowed in "${paths_to_stage[@]}"; do
      [[ "$1" != "${allowed}" ]] || return 0
    done
  fi
  printf 'Outside skeleton: %q; requires separately authorized review and commit before publishing. Nothing was staged.\n' "$1" >&2
  exit 1
}
while IFS= read -r -d '' path; do
  check_publish_path "${path}"
done < <(git -C "${source_dir}" diff --name-only --no-renames -z)
while IFS= read -r -d '' path; do
  check_publish_path "${path}"
done < <(git -C "${source_dir}" ls-files --others --exclude-standard -z)

[[ "$(git -C "${source_dir}" rev-parse --is-shallow-repository)" == false ]] || {
  echo "History scan unverified: shallow history must be completed before publication" >&2; exit 1;
}

# Stage and inspect exact candidate blobs in a private index. A rejected scan
# must not alter the real index, including a previously nonexistent index.
head_before="$(git -C "${source_dir}" rev-parse --verify HEAD 2>/dev/null || true)"
publish_tmp="$(mktemp -d "${TMPDIR:?TMPDIR must be set}/publish-check.XXXXXX")"
index_path="$(git -C "${source_dir}" rev-parse --git-path index)"
[[ "${index_path}" == /* ]] || index_path="${source_dir}/${index_path}"
index_locked=false
config_locked=false
cleanup_publish() {
  rm -rf -- "${publish_tmp}"
  if [[ "${index_locked}" == true ]]; then rm -f -- "${index_path}.lock"; fi
  if [[ "${config_locked}" == true ]]; then rm -f -- "${config_path}.lock"; fi
}
trap cleanup_publish EXIT
[[ ! -L "${index_path}" ]] || { echo "Refusing a symbolic-link Git index" >&2; exit 1; }
if [[ -f "${index_path}" ]]; then
  cp "${index_path}" "${publish_tmp}/index-before"
  cp "${index_path}" "${publish_tmp}/index"
fi
publish_git() { GIT_INDEX_FILE="${publish_tmp}/index" git -C "${source_dir}" "$@"; }
if [[ ${#paths_to_stage[@]} -gt 0 ]]; then
  publish_git add -- "${paths_to_stage[@]}"
fi
# Do not silently bypass user hooks or let them rewrite the scanned index.
# Projects with active hooks must use their normal reviewed publication flow.
if git -C "${source_dir}" config --get core.hooksPath >/dev/null; then
  echo "Custom Git hooks require the project's normal publication flow; no hooks were bypassed." >&2
  exit 1
fi
hooks_path="$(git -C "${source_dir}" rev-parse --git-path hooks)"
[[ "${hooks_path}" == /* ]] || hooks_path="${source_dir}/${hooks_path}"
for hook in pre-commit prepare-commit-msg commit-msg post-commit pre-push; do
  if [[ -x "${hooks_path}/${hook}" ]]; then
    echo "Active Git hook ${hook} requires the project's normal publication flow; no hooks were bypassed." >&2
    exit 1
  fi
done
scanned_tree="$(publish_git write-tree)"
mkdir "${publish_tmp}/snapshot"
GIT_INDEX_FILE="${publish_tmp}/index" python3 - "${source_dir}" "${publish_tmp}/snapshot" "${bootstrap_paths[@]}" <<'PY'
import json
import pathlib
import subprocess
import sys

root, snapshot = map(pathlib.Path, sys.argv[1:3])
allowed = set(sys.argv[3:])
def git(*args):
    return subprocess.check_output(['git', '-C', str(root), *args])

# Inspect staged paths, not just the intended add arguments.
for raw in git('diff', '--cached', '--name-only', '--no-renames', '-z').split(b'\0'):
    if raw:
        path = raw.decode('utf-8', 'surrogateescape')
        if path not in allowed:
            sys.exit(f"Publication refused: staged path outside skeleton {path!r}")
        print(f"Inspected staged skeleton path: {path!r}")

# The complete proposed tree is public, including previously committed assets.
# Do not follow symlinks, publish gitlinks, or silently skip large blobs. The
# 10 MiB bound is deliberately conservative for this skeleton publisher.
entries = git('ls-files', '--stage', '-z').split(b'\0')
# One persistent reader, with a bounded header and size check BEFORE reading or
# allocating the payload. Never communicate() here: it could buffer huge blobs.
batch = subprocess.Popen(['git', '-C', str(root), 'cat-file', '--batch'],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE)
try:
    for entry in entries:
        if not entry:
            continue
        metadata, raw_path = entry.split(b'\t', 1)
        mode, oid, stage = metadata.split()
        path = raw_path.decode('utf-8', 'surrogateescape')
        if mode not in (b'100644', b'100755') or stage != b'0':
            sys.exit(f"Publication refused: symlink, nested repository or unmerged path {path!r}")
        batch.stdin.write(oid + b'\n')
        batch.stdin.flush()
        header = batch.stdout.readline(256)
        fields = header.split()
        if (not header.endswith(b'\n') or len(fields) != 3 or
                fields[:2] != [oid, b'blob'] or not fields[2].isdigit()):
            sys.exit(f"Publication refused: invalid Git blob response for {path!r}")
        size = int(fields[2])
        if size > 10 * 1024 * 1024:
            sys.exit(f"Publication refused: tracked file exceeds 10 MiB: {path!r}")
        data = batch.stdout.read(size)
        if len(data) != size or batch.stdout.read(1) != b'\n':
            sys.exit(f"Publication refused: incomplete Git blob response for {path!r}")
        if path.lower().endswith('.json'):
            try:
                json.loads(data)
            except (ValueError, UnicodeError):
                sys.exit(f"Publication refused: invalid JSON in {path!r} (content withheld)")
        if path.lower().endswith(('.yaml', '.yml')):
            try:
                import yaml
            except ImportError:
                sys.exit('YAML validation unverified: install PyYAML in an approved local environment before publishing')
            try:
                yaml.safe_load(data)
            except (yaml.YAMLError, UnicodeError):
                sys.exit(f"Publication refused: invalid YAML in {path!r} (content withheld)")
        if path.lower().endswith('.toml'):
            try:
                import tomllib
            except ImportError:
                sys.exit('TOML validation unverified: Python 3.11+ is required for this publication')
            try:
                tomllib.loads(data.decode())
            except (ValueError, UnicodeError):
                sys.exit(f"Publication refused: invalid TOML in {path!r} (content withheld)")
        dest = snapshot / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        if path.endswith('.sh'):
            if subprocess.run(['bash', '-n', str(dest)], capture_output=True).returncode:
                sys.exit(f"Publication refused: invalid shell syntax in {path!r} (content withheld)")
    batch.stdin.close()
    if batch.wait() != 0:
        sys.exit('Publication refused: Git blob reader failed')
finally:
    # In particular, do not wait for an oversized payload to drain on failure.
    if batch.poll() is None:
        batch.terminate()
    batch.wait()
    batch.stdout.close()
    if not batch.stdin.closed:
        batch.stdin.close()
PY

# Gitleaks >= 8.19 uses `dir` and `git`. Explicit trusted config/ignore files
# avoid project/environment suppressions; scanner output is never echoed.
# Official CLI: https://github.com/gitleaks/gitleaks#usage
printf '[extend]\nuseDefault = true\n' > "${publish_tmp}/gitleaks.toml"
: > "${publish_tmp}/.gitleaksignore"
scan_args=(--config "${publish_tmp}/gitleaks.toml" --gitleaks-ignore-path "${publish_tmp}/.gitleaksignore"
  --ignore-gitleaks-allow --redact --no-banner --exit-code 1 --max-target-megabytes 0)
if ! gitleaks dir "${publish_tmp}/snapshot" "${scan_args[@]}" >/dev/null 2>&1; then
  echo "Secret scan failed or unverified for candidate files; publication stopped (scanner output withheld)." >&2
  exit 1
fi
if [[ -n "${head_before}" ]] && ! gitleaks git "${source_dir}" \
  "--log-opts=--full-history -m ${head_before}" "${scan_args[@]}" >/dev/null 2>&1; then
  echo "Secret scan failed or unverified for existing history; publication stopped (scanner output withheld)." >&2
  exit 1
fi
printf '%s\n' 'Local gitleaks scan passed for the candidate tree and all existing main history. This is heuristic detection, not proof of no secrets.'

guard_publish_head() {
  [[ "$(git -C "${source_dir}" symbolic-ref --quiet HEAD || true)" == refs/heads/main ]] || {
    echo "Branch changed during inspection; refusing to commit or publish" >&2; exit 1;
  }
  [[ "$(git -C "${source_dir}" rev-parse --verify HEAD 2>/dev/null || true)" == "${head_before}" ]] || {
    echo "HEAD changed during inspection; refusing to commit or publish" >&2; exit 1;
  }
}
guard_publish_head
publish_sha="${head_before}"
head_tree=""
if [[ -n "${head_before}" ]]; then
  head_tree="$(git -C "${source_dir}" rev-parse "${head_before}^{tree}")"
elif publish_git diff --cached --quiet; then
  echo "No commit is available to push; refusing to create an empty remote repository" >&2
  exit 1
fi
# Compare immutable trees, never a diff against a concurrently moving HEAD.
if [[ "${scanned_tree}" != "${head_tree}" ]]; then
  # Hold the real index lock through commit and verification. Keep both the
  # HEAD and symbolic-branch guards: another branch can point at the same SHA.
  (set -o noclobber; : > "${index_path}.lock") 2>/dev/null || {
    echo "Git index is locked; refusing to commit" >&2; exit 1;
  }
  index_locked=true
  if [[ -f "${publish_tmp}/index-before" ]]; then
    cmp -s "${index_path}" "${publish_tmp}/index-before" || {
      echo "Git index changed during inspection; refusing to commit" >&2; exit 1;
    }
  elif [[ -e "${index_path}" ]]; then
    echo "Git index appeared during inspection; refusing to commit" >&2; exit 1
  fi
  guard_publish_head
  publish_git commit -m "Initialize Agent project"
  publish_sha="$(git -C "${source_dir}" rev-parse --verify HEAD)"
  # Hooks run normally. If a hook or concurrent writer changes the tree or
  # introduces unscanned ancestry, fail before any network operation. Do not
  # reset the user's branch/index to repair a failed publication.
  [[ "$(git -C "${source_dir}" symbolic-ref --quiet HEAD || true)" == refs/heads/main &&
     "$(git -C "${source_dir}" show -s --format=%P "${publish_sha}")" == "${head_before}" &&
     "$(git -C "${source_dir}" rev-parse "${publish_sha}^{tree}")" == "${scanned_tree}" &&
     "$(publish_git write-tree)" == "${scanned_tree}" ]] || {
    echo "Commit no longer matches the scanned tree and expected parent; publication stopped" >&2; exit 1;
  }
  cp "${publish_tmp}/index" "${index_path}.lock"
  mv "${index_path}.lock" "${index_path}"
  index_locked=false
fi

# gh may take time (or local work may continue). It must never push mutable HEAD.
GH_HOST=github.com gh repo create "${repository}" "--${visibility}" --source "${source_dir}" --remote origin
# Refuse a changed/misdirected origin, including pushurl and URL rewrites. Hold
# the local config lock through the push so normal concurrent git-config writes
# cannot redirect it after this check. Global config and Git executables remain
# part of the trusted local environment, as do hooks (none are bypassed).
config_path="$(git -C "${source_dir}" rev-parse --git-path config)"
[[ "${config_path}" == /* ]] || config_path="${source_dir}/${config_path}"
[[ ! -L "${config_path}" ]] || { echo "Refusing a symbolic-link Git config" >&2; exit 1; }
(set -o noclobber; : > "${config_path}.lock") 2>/dev/null || {
  echo "Git config is locked; refusing to push" >&2; exit 1;
}
config_locked=true
for candidate in "$(git -C "${source_dir}" remote get-url --all origin)" \
                 "$(git -C "${source_dir}" remote get-url --push --all origin)"; do
  case "${candidate}" in
    https://github.com/*) remote_repo="${candidate#https://github.com/}" ;;
    git@github.com:*) remote_repo="${candidate#git@github.com:}" ;;
    ssh://git@github.com/*) remote_repo="${candidate#ssh://git@github.com/}" ;;
    *) echo "origin is not the requested GitHub repository; refusing to push" >&2; exit 1 ;;
  esac
  remote_repo="${remote_repo%.git}"
  [[ "$(printf '%s' "${remote_repo}" | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "${repository}" | tr '[:upper:]' '[:lower:]')" ]] || {
    echo "origin does not match ${repository}; refusing to push" >&2; exit 1;
  }
done
# Explicit refspec and no-follow-tags prevent push.default, remote push refspecs
# and push.followTags from widening publication. Never recurse into other repos.
git -C "${source_dir}" -c remote.origin.mirror=false -c push.recurseSubmodules=no \
  push --no-follow-tags origin "${publish_sha}:refs/heads/main"
echo "Created GitHub repository ${repository}, configured origin, and pushed scanned commit ${publish_sha} to main"
