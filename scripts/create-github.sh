#!/usr/bin/env bash
set -euo pipefail

repository=""
visibility=""
source_dir="$(pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/create-github.sh --repo OWNER/REPOSITORY --visibility VISIBILITY [--source DIR]

Create a GitHub repository from a bootstrapped project, add origin, and push main.

  --repo REPO              Explicit OWNER/REPOSITORY target
  --visibility VISIBILITY  private, public, or internal
  --source DIR             Local project directory (default: current directory)
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

if [[ ! "${repository}" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
  echo "--repo must be an explicit OWNER/REPOSITORY value" >&2
  exit 2
fi

case "${visibility}" in
  private|public|internal) ;;
  *)
    echo "--visibility must be private, public, or internal" >&2
    exit 2
    ;;
esac

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "gh is required" >&2; exit 1; }

[[ -d "${source_dir}" ]] || { echo "Source directory does not exist: ${source_dir}" >&2; exit 1; }
source_dir="$(cd "${source_dir}" && pwd)"

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
)
paths_to_stage=()
for path in "${bootstrap_paths[@]}"; do
  [[ -f "${source_dir}/${path}" ]] && paths_to_stage+=("${path}")
done

if [[ ${#paths_to_stage[@]} -gt 0 ]]; then
  git -C "${source_dir}" add -- "${paths_to_stage[@]}"
fi

if ! git -C "${source_dir}" diff --quiet; then
  echo "The worktree contains unstaged changes outside the generated bootstrap files; commit or stash them before publishing" >&2
  exit 1
fi

untracked_files="$(git -C "${source_dir}" ls-files --others --exclude-standard)"
if [[ -n "${untracked_files}" ]]; then
  echo "The worktree contains untracked files outside the generated bootstrap files; commit or remove them before publishing" >&2
  exit 1
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
