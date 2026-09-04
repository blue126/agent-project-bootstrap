#!/usr/bin/env bash
set -euo pipefail

# Rebuild the local artifacts a bootstrapped project deliberately keeps out of
# Git: integration runtimes under .agent/runtime and the Skill links in
# .agents/skills. Run this after cloning a project onto a new machine.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="$(pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/rehydrate.sh [--target DIR]

Reinstall the integrations recorded in a project's .agent/bootstrap.yml.

  --target DIR   Project directory (default: current directory)
  -h, --help     Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "--target requires a directory" >&2; exit 2; }
      target_dir="$2"
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

[[ -d "${target_dir}" ]] || { echo "Target directory does not exist: ${target_dir}" >&2; exit 1; }
target_dir="$(cd "${target_dir}" && pwd)"
manifest="${target_dir}/.agent/bootstrap.yml"

[[ -f "${manifest}" ]] || {
  echo "No .agent/bootstrap.yml in ${target_dir}; nothing to rehydrate" >&2
  exit 1
}

# The nesting depth distinguishes the two "installation:" keys: four spaces is
# understand_anything, two is superpowers.
selection() {
  awk -F': ' -v pattern="$1" '$0 ~ pattern { print $2; exit }' "${manifest}"
}

workflow="$(selection '^workflow_id:')"
curated_skills="$(selection '^  curated_skills:')"
understand_anything="$(selection '^    installation:')"
superpowers="$(selection '^  installation:')"

echo "Project: ${target_dir}"
echo "Recorded workflow: ${workflow:-unknown}"

if [[ "${understand_anything}" == install ]]; then
  echo "Reinstalling project-scoped Understand Anything..."
  "${repo_root}/scripts/install-understand-anything.sh" --target "${target_dir}"
else
  echo "Understand Anything: not recorded as installed; skipping."
fi

# Skill installation is interactive by design: the user picks Skills and target
# agents. Rehydration prints the command instead of choosing for them.
if [[ "${curated_skills}" == install ]]; then
  echo
  echo "Curated Skills were installed in this project. Reinstall them with:"
  echo "  cd \"${target_dir}\" && npx skills@1.5.23 add \"${repo_root}\""
fi

if [[ "${superpowers}" == install ]]; then
  echo
  echo "The Superpowers workflow pack was installed in this project. Reinstall it with:"
  echo "  cd \"${target_dir}\" && npx skills@1.5.23 add https://github.com/obra/superpowers/tree/v6.3.0"
fi

echo
echo "Rehydration complete."
