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
  [[ "${repository}" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$ && "${repository##*/}" != . && "${repository##*/}" != .. ]] || {
    echo "Invalid GitHub OWNER/REPOSITORY" >&2; exit 2;
  }
fi

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

# Only the generated policy skeleton is published. Installed Skills and
# integration runtimes are local artifacts kept out of the repository by
# .agent/runtime/.gitignore and .agents/skills/.gitignore; committing the
# links would publish paths that dangle in every fresh clone.
bootstrap_paths=(
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
paths_to_stage=()
for path in "${bootstrap_paths[@]}"; do
  [[ -f "${source_dir}/${path}" ]] && paths_to_stage+=("${path}")
done

# Preflight outside files before staging anything. Rejections must not leave
# generated files staged in a previously untouched index.
check_publish_path() {
  local allowed
  if [[ ${#paths_to_stage[@]} -gt 0 ]]; then
    for allowed in "${paths_to_stage[@]}"; do
      [[ "$1" != "${allowed}" ]] || return 0
    done
  fi
  echo "The worktree contains changes outside the generated bootstrap files: $1; commit or remove them before publishing" >&2
  exit 1
}
while IFS= read -r -d '' path; do
  check_publish_path "${path}"
done < <(git -C "${source_dir}" diff --name-only --no-renames -z)
while IFS= read -r -d '' path; do
  check_publish_path "${path}"
done < <(git -C "${source_dir}" ls-files --others --exclude-standard -z)

if [[ ${#paths_to_stage[@]} -gt 0 ]]; then
  git -C "${source_dir}" add -- "${paths_to_stage[@]}"
fi

if ! git -C "${source_dir}" diff --cached --quiet; then
  git -C "${source_dir}" commit -m "Initialize Agent project"
fi

if ! git -C "${source_dir}" rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "No commit is available to push; refusing to create an empty remote repository" >&2
  exit 1
fi

gh repo create "${repository}" "--${visibility}" --source "${source_dir}" --remote origin --push
echo "Created GitHub repository ${repository}, configured origin, and pushed main"
