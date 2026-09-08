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

# All restoration selections come from the same read-only metadata parser.
# Require the matching toolkit distribution; an older fallback could disagree.
for helper in onboarding-project.py merge-bootstrap-config.py; do
  [[ -f "${repo_root}/scripts/lib/${helper}" ]] || {
    echo "Missing shared metadata helper: ${helper}; restore the complete toolkit distribution" >&2
    exit 2
  }
done
restoration="$(python3 -B - "${repo_root}" "${target_dir}" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

repo, target = map(Path, sys.argv[1:])
result = subprocess.run([sys.executable, '-B', str(repo / 'scripts/lib/onboarding-project.py'),
                         '--project', str(target), 'metadata'], stdout=subprocess.PIPE, text=True)
if result.returncode:
    sys.exit(result.returncode)
data = json.loads(result.stdout)
# Emit only validated identifiers/known action tokens, never arbitrary scalar
# contents into the line-oriented shell transport. Unknown values stay on disk.
print(data['workflow'])
print(data['workflow_pack'] if data['workflow_pack'] in ('bmad', 'superpowers', 'github-workflow') else 'none')
for field in ('curated_skills', 'understand_anything', 'superpowers'):
    print('install' if data[field] == 'install' else 'skip')
print('\n'.join(data['selected']))
PY
)"
agents=()
ua_agent_flags=()
{
  IFS= read -r workflow
  IFS= read -r workflow_pack
  IFS= read -r curated_skills
  IFS= read -r understand_anything
  IFS= read -r superpowers
  while IFS= read -r agent; do
    [[ -n "${agent}" ]] || continue
    agents+=("${agent}")
    ua_agent_flags+=(--agent "${agent}")
  done
} <<< "${restoration}"
skills_agent_flags=()
if [[ ${#agents[@]} -gt 0 ]]; then
  skills_agent_flags=(--agent "${agents[@]}")
fi

echo "Project: ${target_dir}"
echo "Recorded workflow: ${workflow:-unknown}"

if [[ "${understand_anything}" == install ]]; then
  echo "Reinstalling project-scoped Understand Anything..."
  "${repo_root}/scripts/install-understand-anything.sh" --target "${target_dir}" ${ua_agent_flags[@]+"${ua_agent_flags[@]}"}
else
  echo "Understand Anything: not recorded as installed; skipping."
fi

# Never launch an interactive selector in an Agent-owned process. Quote every
# argument for copy/paste into a human terminal, including unusual project paths.
print_command() {
  python3 -B - "${target_dir}" "$@" <<'PY'
import shlex
import sys
print('  cd ' + shlex.quote(sys.argv[1]) + ' && ' + shlex.join(sys.argv[2:]))
PY
}
pending=false
if [[ "${curated_skills}" == install ]]; then
  pending=true
  echo
  echo "Curated Skills restore pending. Run in your own terminal:"
  print_command npx skills@1.5.23 add "${repo_root}" ${skills_agent_flags[@]+"${skills_agent_flags[@]}"}
fi

if [[ "${superpowers}" == install ]]; then
  pending=true
  echo
  echo "Superpowers workflow-pack restore pending. Run in your own terminal:"
  print_command npx skills@1.5.23 add https://github.com/obra/superpowers/tree/v6.3.0 ${skills_agent_flags[@]+"${skills_agent_flags[@]}"}
elif [[ "${workflow}" == superpowers || "${workflow_pack}" == superpowers ]]; then
  pending=true
  echo "Superpowers availability check pending: its local source/ref was not verified; inspect the selected clients before restoring."
fi
if [[ "${workflow}" == github-workflow && "${curated_skills}" != install ]]; then
  pending=true
  echo "github-workflow availability check pending: confirm its approved installation scope in the selected clients."
fi

if [[ "${workflow}" == bmad || "${workflow_pack}" == bmad || -e "${target_dir}/_bmad" || -L "${target_dir}/_bmad" ]]; then
  pending=true
  echo
  echo "BMAD manual restore pending: use the installbmad Skill to inspect the existing installation,"
  echo "plan the module/tool union and run the pinned installer in your own terminal."
  echo "BMAD files and session loading have not been verified; universal is not a BMAD tool."
fi

echo
if [[ "${pending}" == true ]]; then
  echo "Rehydration pending: complete the manual steps above and verify the selected clients in new sessions."
else
  echo "Rehydration complete."
fi
