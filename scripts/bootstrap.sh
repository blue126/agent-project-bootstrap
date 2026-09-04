#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skills_cli_version="1.5.23"
superpowers_upstream="https://github.com/obra/superpowers.git"
superpowers_tag="v6.3.0"
superpowers_ref="b36e0829c6d0140e93cfef2ca599b1b07d4a7797"
understand_anything_upstream="https://github.com/Egonex-AI/Understand-Anything"
understand_anything_tag="v2.9.0"
understand_anything_ref="f08763d11d0202a8a8f52b5dedda6d1b2e2ebac8"
target_dir="$(pwd)"
workflow=""
repository_skills_mode=""
superpowers_mode=""
understand_anything_mode=""
init_git=false
update_mode=false
force=false
create_github=false
configure_github=false
github_repository=""
github_visibility=""
running_under_agent=false

if [[ -n "${AI_AGENT:-}" || -n "${CODEX_SANDBOX:-}" || -n "${CODEX_CI:-}" || -n "${CODEX_THREAD_ID:-}" ]]; then
  running_under_agent=true
fi

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap.sh [--target DIR] [--workflow MODE]
                            [--update [--force]]
                            [--install-skills | --skip-skills] [--init-git]
                            [--install-understand-anything | --skip-understand-anything]
                            [--install-superpowers | --skip-superpowers]
                            [--create-github --github-repo OWNER/REPOSITORY
                             --github-visibility VISIBILITY]
                            [--configure-github --github-repo OWNER/REPOSITORY]

Initialize Agent project policy in an empty or existing directory without overwriting files.

  --target DIR          Project directory (default: current directory)
  --workflow MODE       Active mode: none, github-workflow, or superpowers
  --install-skills      Interactively choose Curated Skills and target agents
  --skip-skills         Do not install Curated Skills during bootstrap
  --install-understand-anything
                        Install pinned Understand Anything for this project only
  --skip-understand-anything
                        Do not install Understand Anything in this project
  --install-superpowers Advanced: install the inactive or active Superpowers pack
  --skip-superpowers    Do not install the Superpowers workflow pack
  --update              Refresh bootstrap-managed files that you have not edited
  --force               With --update, also overwrite files you have edited
  --init-git            Run git init when the target is not already a Git repository
  --create-github       Create the explicit repository, add origin, and push main
  --configure-github    Create or reconcile the Protect main GitHub ruleset
  --github-repo REPO    Explicit OWNER/REPOSITORY target for GitHub operations
  --github-visibility V Repository visibility: private, public, or internal
  -h, --help            Show this help
EOF
}

verify_superpowers_ref() {
  command -v git >/dev/null 2>&1 || {
    echo "git is required to verify the pinned Superpowers ref" >&2
    exit 1
  }

  remote_refs="$(
    git ls-remote "${superpowers_upstream}" \
      "refs/tags/${superpowers_tag}" "refs/tags/${superpowers_tag}^{}"
  )"
  resolved_ref="$(printf '%s\n' "${remote_refs}" | awk '/\^\{\}$/ { print $1; exit }')"
  if [[ -z "${resolved_ref}" ]]; then
    resolved_ref="$(printf '%s\n' "${remote_refs}" | awk 'NR == 1 { print $1 }')"
  fi

  if [[ "${resolved_ref}" != "${superpowers_ref}" ]]; then
    echo "Superpowers ${superpowers_tag} resolved to '${resolved_ref:-missing}', expected ${superpowers_ref}" >&2
    echo "Refusing installation until the managed integration pin is reviewed." >&2
    exit 1
  fi
}

hash_file() {
  # macOS ships shasum but not sha256sum.
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Hash recorded for a managed file the last time bootstrap wrote it. Empty when
# the project predates managed_files or the file was left alone as user-edited.
recorded_hash() {
  local manifest="$1" path="$2"
  [[ -f "${manifest}" ]] || return 0
  awk -v want="${path}:" '
    /^managed_files:/ { block = 1; next }
    /^[^[:space:]]/ { block = 0 }
    block && $1 == want { print $2; exit }
  ' "${manifest}"
}

# Selections recorded by a previous run. The nesting depth distinguishes the two
# "installation:" keys: four spaces is understand_anything, two is superpowers.
recorded_selection() {
  local manifest="$1" pattern="$2"
  [[ -f "${manifest}" ]] || return 0
  awk -F': ' -v pattern="${pattern}" '$0 ~ pattern { print $2; exit }' "${manifest}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "--target requires a directory" >&2; exit 2; }
      target_dir="$2"
      shift 2
      ;;
    --workflow)
      [[ $# -ge 2 ]] || { echo "--workflow requires a mode" >&2; exit 2; }
      workflow="$2"
      shift 2
      ;;
    --install-skills)
      [[ -z "${repository_skills_mode}" || "${repository_skills_mode}" == install ]] || {
        echo "--install-skills conflicts with --skip-skills" >&2
        exit 2
      }
      repository_skills_mode="install"
      shift
      ;;
    --skip-skills)
      [[ -z "${repository_skills_mode}" || "${repository_skills_mode}" == skip ]] || {
        echo "--skip-skills conflicts with --install-skills" >&2
        exit 2
      }
      repository_skills_mode="skip"
      shift
      ;;
    --install-understand-anything)
      [[ -z "${understand_anything_mode}" || "${understand_anything_mode}" == install ]] || {
        echo "--install-understand-anything conflicts with --skip-understand-anything" >&2
        exit 2
      }
      understand_anything_mode="install"
      shift
      ;;
    --skip-understand-anything)
      [[ -z "${understand_anything_mode}" || "${understand_anything_mode}" == skip ]] || {
        echo "--skip-understand-anything conflicts with --install-understand-anything" >&2
        exit 2
      }
      understand_anything_mode="skip"
      shift
      ;;
    --install-superpowers)
      [[ -z "${superpowers_mode}" || "${superpowers_mode}" == install ]] || {
        echo "--install-superpowers conflicts with --skip-superpowers" >&2
        exit 2
      }
      superpowers_mode="install"
      shift
      ;;
    --skip-superpowers)
      [[ -z "${superpowers_mode}" || "${superpowers_mode}" == skip ]] || {
        echo "--skip-superpowers conflicts with --install-superpowers" >&2
        exit 2
      }
      superpowers_mode="skip"
      shift
      ;;
    --init-git)
      init_git=true
      shift
      ;;
    --update)
      update_mode=true
      shift
      ;;
    --force)
      force=true
      shift
      ;;
    --create-github)
      create_github=true
      shift
      ;;
    --configure-github)
      configure_github=true
      shift
      ;;
    --github-repo)
      [[ $# -ge 2 ]] || { echo "--github-repo requires OWNER/REPOSITORY" >&2; exit 2; }
      github_repository="$2"
      shift 2
      ;;
    --github-visibility)
      [[ $# -ge 2 ]] || { echo "--github-visibility requires private, public, or internal" >&2; exit 2; }
      github_visibility="$2"
      shift 2
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

# Which modes came from the command line, before any default or prompt fills
# them in. --update replays recorded selections, so it must not mistake its own
# defaults for a user choice.
cli_skills_mode="${repository_skills_mode}"
cli_understand_anything_mode="${understand_anything_mode}"
cli_superpowers_mode="${superpowers_mode}"
record_skills=""
record_understand_anything=""
record_superpowers=""
record_reviewer="none"
record_fixer="none"
record_validation="pending"
record_validation_mode="review_only"
record_adapter_manifest="none"
record_adapter_sha="none"
record_auto_merge="disabled"

if [[ "${update_mode}" == true ]]; then
  [[ -d "${target_dir}" ]] || {
    echo "--update requires an existing project directory: ${target_dir}" >&2
    exit 1
  }
  existing_manifest="$(cd "${target_dir}" && pwd)/.agent/bootstrap.yml"
  [[ -f "${existing_manifest}" ]] || {
    echo "--update requires a project bootstrapped earlier; no .agent/bootstrap.yml in ${target_dir}" >&2
    exit 1
  }

  # Replay the recorded selections so an update needs no arguments, but do not
  # re-run installers: refreshing policy files must not relaunch a selector.
  [[ -n "${workflow}" ]] || workflow="$(recorded_selection "${existing_manifest}" '^workflow_id:')"
  record_skills="${cli_skills_mode:-$(recorded_selection "${existing_manifest}" '^  curated_skills:')}"
  record_understand_anything="${cli_understand_anything_mode:-$(recorded_selection "${existing_manifest}" '^    installation:')}"
  record_superpowers="${cli_superpowers_mode:-$(recorded_selection "${existing_manifest}" '^  installation:')}"
  record_reviewer="$(recorded_selection "${existing_manifest}" '^  reviewer:')"
  record_fixer="$(recorded_selection "${existing_manifest}" '^  fixer:')"
  record_validation="$(recorded_selection "${existing_manifest}" '^  validation:')"
  record_validation_mode="$(recorded_selection "${existing_manifest}" '^  validation_mode:')"
  record_adapter_manifest="$(recorded_selection "${existing_manifest}" '^  validation_adapter_manifest:')"
  record_adapter_sha="$(recorded_selection "${existing_manifest}" '^  validation_adapter_sha256:')"
  record_auto_merge="$(recorded_selection "${existing_manifest}" '^  auto_merge:')"
  : "${record_reviewer:=none}"
  : "${record_fixer:=none}"
  : "${record_validation:=pending}"
  : "${record_validation_mode:=review_only}"
  : "${record_adapter_manifest:=none}"
  : "${record_adapter_sha:=none}"
  : "${record_auto_merge:=disabled}"
  repository_skills_mode="${cli_skills_mode:-skip}"
  understand_anything_mode="${cli_understand_anything_mode:-skip}"
  superpowers_mode="${cli_superpowers_mode:-skip}"

  [[ -n "${workflow}" ]] || {
    echo "Could not read workflow_id from ${existing_manifest}; pass --workflow explicitly" >&2
    exit 1
  }
elif [[ "${force}" == true ]]; then
  echo "--force applies to --update only" >&2
  exit 2
fi

if [[ -n "${workflow}" && "${workflow}" != superpowers && -z "${superpowers_mode}" ]]; then
  superpowers_mode="skip"
fi

if [[ "${running_under_agent}" == true ]]; then
  if [[ "${repository_skills_mode}" == install || "${superpowers_mode}" == install ]]; then
    echo "Interactive Skill installation must be run by the user in a regular terminal, not by an Agent process." >&2
    echo "Do not unset Agent or Codex detection variables to bypass this guard." >&2
    exit 2
  fi
  if [[ -z "${workflow}" || -z "${repository_skills_mode}" || -z "${understand_anything_mode}" || ( "${workflow}" == superpowers && -z "${superpowers_mode}" ) ]]; then
    echo "An Agent process cannot host the interactive bootstrap selectors." >&2
    echo "Give the user the command to run in a regular terminal; do not claim a selector is waiting in an Agent PTY." >&2
    exit 2
  fi
fi

if [[ -z "${repository_skills_mode}" ]]; then
  if [[ -t 0 && -t 1 ]]; then
    read -r -p "Open the Curated Skills selector now? [y/N]: " skills_choice
    case "${skills_choice}" in
      y|Y|yes|YES) repository_skills_mode="install" ;;
      *) repository_skills_mode="skip" ;;
    esac
  else
    echo "Interactive Curated Skills choice is required." >&2
    echo "Guide the user to run this script in a terminal so npx can present the selector." >&2
    exit 2
  fi
fi

if [[ -z "${understand_anything_mode}" ]]; then
  if [[ -t 0 && -t 1 ]]; then
    echo "Understand Anything is an experimental, project-scoped codebase knowledge-graph integration."
    read -r -p "Install Understand Anything in this project? [y/N]: " understand_anything_choice
    case "${understand_anything_choice}" in
      y|Y|yes|YES) understand_anything_mode="install" ;;
      *) understand_anything_mode="skip" ;;
    esac
  else
    echo "Interactive Understand Anything choice is required." >&2
    echo "Guide the user to run this script in a terminal; do not choose on their behalf." >&2
    exit 2
  fi
fi

if [[ -z "${workflow}" ]]; then
  if [[ -t 0 && -t 1 ]]; then
    echo "Select the one active workflow for this project:"
    echo "  1) none"
    echo "  2) github-workflow"
    echo "  3) superpowers"
    while [[ -z "${workflow}" ]]; do
      read -r -p "Workflow [1-3]: " workflow_choice
      case "${workflow_choice}" in
        1) workflow="none" ;;
        2) workflow="github-workflow" ;;
        3) workflow="superpowers" ;;
        *) echo "Choose 1, 2, or 3." >&2 ;;
      esac
    done
  else
    echo "Interactive bootstrap choices are required." >&2
    echo "Guide the user to run this script in a terminal; do not choose a workflow or create a chat questionnaire." >&2
    exit 2
  fi
fi

case "${workflow}" in
  none|github-workflow|superpowers) ;;
  *)
    echo "Invalid workflow '${workflow}'; choose none, github-workflow, or superpowers" >&2
    exit 2
    ;;
esac

if [[ -z "${superpowers_mode}" ]]; then
  if [[ "${workflow}" != superpowers ]]; then
    superpowers_mode="skip"
  elif [[ -t 0 && -t 1 ]]; then
    read -r -p "Install the pinned Superpowers workflow pack now? [Y/n]: " superpowers_choice
    case "${superpowers_choice}" in
      n|N|no|NO) superpowers_mode="skip" ;;
      *) superpowers_mode="install" ;;
    esac
  else
    echo "Interactive Superpowers workflow-pack choice is required." >&2
    echo "Guide the user to run this script in a terminal so npx can present the pinned selector." >&2
    exit 2
  fi
fi

if [[ "${repository_skills_mode}" == install && ( ! -t 0 || ! -t 1 ) ]]; then
  echo "--install-skills requires an interactive terminal so npx can present Skill and agent choices." >&2
  echo "Run bootstrap in a TTY or guide the user to run the npx installer directly." >&2
  exit 2
fi

if [[ "${superpowers_mode}" == install && ( ! -t 0 || ! -t 1 ) ]]; then
  echo "--install-superpowers requires an interactive terminal so npx can present Skill and agent choices." >&2
  echo "Run bootstrap in a TTY or guide the user to run the pinned Superpowers npx installer directly." >&2
  exit 2
fi

if [[ "${superpowers_mode}" == install ]]; then
  verify_superpowers_ref
fi

if [[ ( "${create_github}" == true || "${configure_github}" == true ) && -z "${github_repository}" ]]; then
  echo "GitHub operations require explicit --github-repo OWNER/REPOSITORY" >&2
  exit 2
fi
if [[ "${create_github}" == false && "${configure_github}" == false && -n "${github_repository}" ]]; then
  echo "--github-repo requires --create-github or --configure-github" >&2
  exit 2
fi
if [[ "${create_github}" == true && -z "${github_visibility}" ]]; then
  echo "--create-github requires --github-visibility private, public, or internal" >&2
  exit 2
fi
if [[ "${create_github}" == false && -n "${github_visibility}" ]]; then
  echo "--github-visibility requires --create-github" >&2
  exit 2
fi

mkdir -p "${target_dir}"
target_dir="$(cd "${target_dir}" && pwd)"

files=(
  "templates/AGENTS.md:AGENTS.md"
  "templates/CLAUDE.md:CLAUDE.md"
  "policies/core.md:.agent/policies/core.md"
  "policies/git.md:.agent/policies/git.md"
  "policies/workflow-selection.md:.agent/policies/workflow-selection.md"
  "templates/runtime.gitignore:.agent/runtime/.gitignore"
  "templates/skills.gitignore:.agents/skills/.gitignore"
  "templates/sensitive-paths.txt:.agent/governance/sensitive-paths.txt"
)

manifest_path="${target_dir}/.agent/bootstrap.yml"
managed_records=""
updated_files=()
preserved_files=()

record_managed() {
  managed_records="${managed_records}  $1: $2
"
}

install_managed_file() {
  local source="$1" destination="$2"
  mkdir -p "$(dirname "${target_dir}/${destination}")"
  cp "${repo_root}/${source}" "${target_dir}/${destination}"
  record_managed "${destination}" "$(hash_file "${repo_root}/${source}")"
}

if [[ "${update_mode}" == true ]]; then
  # Reconcile per file. A file still matching the hash recorded when bootstrap
  # last wrote it is ours to replace; anything else is user work and is kept
  # unless --force overrides it.
  for mapping in "${files[@]}"; do
    source="${mapping%%:*}"
    destination="${mapping#*:}"
    destination_path="${target_dir}/${destination}"

    if [[ ! -e "${destination_path}" ]]; then
      install_managed_file "${source}" "${destination}"
      updated_files+=("${destination} (created)")
      continue
    fi

    desired="$(hash_file "${repo_root}/${source}")"
    current="$(hash_file "${destination_path}")"
    recorded="$(recorded_hash "${manifest_path}" "${destination}")"

    if [[ "${current}" == "${desired}" ]]; then
      record_managed "${destination}" "${desired}"
    elif [[ -n "${recorded}" && "${current}" == "${recorded}" ]] || [[ "${force}" == true ]]; then
      install_managed_file "${source}" "${destination}"
      updated_files+=("${destination}")
    else
      preserved_files+=("${destination}")
      # Keep the original recording so the file stays user-owned next time.
      [[ -z "${recorded}" ]] || record_managed "${destination}" "${recorded}"
    fi
  done
else
  conflicts=()
  for mapping in "${files[@]}"; do
    destination="${mapping#*:}"
    [[ ! -e "${target_dir}/${destination}" ]] || conflicts+=("${destination}")
  done
  [[ ! -e "${manifest_path}" ]] || conflicts+=(".agent/bootstrap.yml")

  if [[ ${#conflicts[@]} -gt 0 ]]; then
    echo "Refusing to overwrite existing project files:" >&2
    printf '  %s\n' "${conflicts[@]}" >&2
    echo "Run again with --update to refresh the files bootstrap manages." >&2
    exit 1
  fi

  for mapping in "${files[@]}"; do
    install_managed_file "${mapping%%:*}" "${mapping#*:}"
  done
fi

: "${record_skills:=${repository_skills_mode}}"
: "${record_understand_anything:=${understand_anything_mode}}"
: "${record_superpowers:=${superpowers_mode}}"

mkdir -p "$(dirname "${manifest_path}")"
cat > "${manifest_path}" <<EOF
schema_version: 4
source: blue126/agent-project-bootstrap
workflow_id: ${workflow}
governance:
  reviewer: ${record_reviewer}
  fixer: ${record_fixer}
  validation: ${record_validation}
  validation_mode: ${record_validation_mode}
  validation_adapter_manifest: ${record_adapter_manifest}
  validation_adapter_sha256: ${record_adapter_sha}
  auto_merge: ${record_auto_merge}
  sensitive_paths: .agent/governance/sensitive-paths.txt
components:
  curated_skills: ${record_skills}
  workflow_pack: ${workflow}
integrations:
  understand_anything:
    installation: ${record_understand_anything}
    scope: project
    upstream: ${understand_anything_upstream}
    tag: ${understand_anything_tag}
    ref: ${understand_anything_ref}
superpowers:
  installation: ${record_superpowers}
  upstream: ${superpowers_upstream%.git}
  tag: ${superpowers_tag}
  ref: ${superpowers_ref}
managed_files:
EOF
printf '%s' "${managed_records}" >> "${manifest_path}"

if [[ "${init_git}" == true ]] && ! git -C "${target_dir}" rev-parse --git-dir >/dev/null 2>&1; then
  # Match what --create-github requires, rather than whatever the user's
  # init.defaultBranch happens to be.
  git -C "${target_dir}" init --quiet
  git -C "${target_dir}" symbolic-ref HEAD refs/heads/main
fi

if [[ "${create_github}" == true ]]; then
  "${repo_root}/scripts/create-github.sh" \
    --source "${target_dir}" \
    --repo "${github_repository}" \
    --visibility "${github_visibility}"
fi

if [[ "${configure_github}" == true ]]; then
  "${repo_root}/scripts/configure-github.sh" --repo "${github_repository}"
fi

if [[ "${repository_skills_mode}" == install ]]; then
  if [[ "${workflow}" == github-workflow ]]; then
    echo "github-workflow is active; select it in the Curated Skills selector unless it is already available in another approved scope."
  fi
  # Install from this checkout. The source repository is private, so the URL
  # form needs gh/SSH credentials and can also lag behind local edits.
  (
    cd "${target_dir}"
    npx "skills@${skills_cli_version}" add "${repo_root}"
  )
fi

if [[ "${superpowers_mode}" == install ]]; then
  (
    cd "${target_dir}"
    npx "skills@${skills_cli_version}" add "${superpowers_upstream%.git}/tree/${superpowers_tag}"
  )
fi

if [[ "${understand_anything_mode}" == install ]]; then
  "${repo_root}/scripts/install-understand-anything.sh" --target "${target_dir}"
fi

if [[ "${update_mode}" == true ]]; then
  if [[ ${#updated_files[@]} -gt 0 ]]; then
    echo "Refreshed bootstrap-managed files:"
    printf '  %s\n' "${updated_files[@]}"
  else
    echo "All bootstrap-managed files are already current."
  fi
  if [[ ${#preserved_files[@]} -gt 0 ]]; then
    echo "Left alone (changed since bootstrap wrote them, or written before this project recorded hashes):"
    printf '  %s\n' "${preserved_files[@]}"
    echo "Compare with: diff ${target_dir}/<file> ${repo_root}/<template>"
    echo "Re-run with --force to replace them."
  fi
fi

echo "Initialized Agent project policy in ${target_dir}"
echo "Selected workflow: ${workflow}"
if [[ "${create_github}" == false ]] && ! git -C "${target_dir}" remote get-url origin >/dev/null 2>&1; then
  echo "No origin remote configured; bootstrap did not create one."
fi
if [[ "${workflow}" == superpowers && "${superpowers_mode}" == skip ]]; then
  echo "Superpowers is active but project installation was skipped by explicit choice."
  echo "Confirm that pinned v6.3.0 is available through another approved scope before using the workflow."
fi
if [[ "${workflow}" == github-workflow && "${repository_skills_mode}" == skip ]]; then
  echo "github-workflow is active but Curated Skills installation was skipped by explicit choice."
  echo "Confirm that github-workflow is available through another approved scope before using it."
fi
