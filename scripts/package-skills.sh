#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root="${repo_root}/skills"
output_root="${repo_root}/dist"

if ! command -v zip >/dev/null 2>&1; then
  echo "zip is required to package skills" >&2
  exit 1
fi

mkdir -p "${output_root}"
shopt -s nullglob
skill_dirs=("${source_root}"/*)

if [[ ${#skill_dirs[@]} -eq 0 ]]; then
  echo "No personal skills found in ${source_root}"
  exit 0
fi

for skill_dir in "${skill_dirs[@]}"; do
  [[ -d "${skill_dir}" && -f "${skill_dir}/SKILL.md" ]] || continue

  skill_name="$(basename "${skill_dir}")"
  archive="${output_root}/${skill_name}.zip"
  rm -f "${archive}"
  (
    cd "${skill_dir}"
    zip -qr "${archive}" . -x '.DS_Store' '__pycache__/*' '*.pyc'
  )
  echo "Packaged ${archive}"
done
