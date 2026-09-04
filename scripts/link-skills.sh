#!/bin/bash
set -euo pipefail

# Link this repository's Skills into the user-level directories of the agents
# used with it. Project-level installation goes through bootstrap.sh; this is
# the "available everywhere" path.
#
# Agent skill directories (user level):
#   Codex     ${CODEX_HOME:-~/.codex}/skills
#   OpenCode  ${XDG_CONFIG_HOME:-~/.config}/opencode/skills
#   Claude    ~/.claude/skills
#
# OpenCode also reads ~/.agents/skills and ~/.claude/skills, so linking into
# its own directory is enough to avoid duplicate registrations.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="${repo_root}/skills"

destinations=(
  "${CODEX_HOME:-${HOME}/.codex}/skills"
  "${XDG_CONFIG_HOME:-${HOME}/.config}/opencode/skills"
)

usage() {
  cat <<'EOF'
Usage: scripts/link-skills.sh [--agent AGENT]...

Link skills/* into user-level agent directories.

  --agent AGENT   codex, opencode, or claude (repeatable; default: codex opencode)
  -h, --help      Show this help
EOF
}

selected=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      [[ $# -ge 2 ]] || { echo "--agent requires codex, opencode, or claude" >&2; exit 2; }
      case "$2" in
        codex) selected+=("${CODEX_HOME:-${HOME}/.codex}/skills") ;;
        opencode) selected+=("${XDG_CONFIG_HOME:-${HOME}/.config}/opencode/skills") ;;
        claude) selected+=("${HOME}/.claude/skills") ;;
        *) echo "Unknown agent: $2" >&2; exit 2 ;;
      esac
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

if [[ ${#selected[@]} -gt 0 ]]; then
  destinations=("${selected[@]}")
fi

shopt -s nullglob
skill_dirs=("${source_root}"/*)

if [[ ${#skill_dirs[@]} -eq 0 ]]; then
  echo "No skills found in ${source_root}"
  exit 0
fi

for skills_root in "${destinations[@]}"; do
  mkdir -p "${skills_root}"
  for skill_dir in "${skill_dirs[@]}"; do
    [[ -d "${skill_dir}" && -f "${skill_dir}/SKILL.md" ]] || continue

    skill_name="$(basename "${skill_dir}")"
    destination="${skills_root}/${skill_name}"

    if [[ -L "${destination}" && "$(readlink "${destination}")" == "${skill_dir}" ]]; then
      echo "Already linked: ${destination}"
      continue
    fi

    if [[ -e "${destination}" || -L "${destination}" ]]; then
      echo "Refusing to overwrite existing path: ${destination}" >&2
      exit 1
    fi

    ln -s "${skill_dir}" "${destination}"
    echo "Linked ${skill_name} -> ${destination}"
  done
done
