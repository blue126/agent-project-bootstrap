#!/usr/bin/env bash
set -euo pipefail

policy_file=""

usage() {
  cat <<'EOF'
Usage: scripts/classify-sensitive-paths.sh --policy FILE [PATH...]

Print matching governance-sensitive paths. If no PATH arguments are supplied,
read one repository-relative path per line from standard input.
Exit 0 when at least one path is sensitive, 1 when none match, and 2 on invalid input.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy) [[ $# -ge 2 ]] || exit 2; policy_file="$2"; shift 2; break ;;
    -h|--help) usage; exit 0 ;;
    *) echo "--policy must be supplied before paths" >&2; exit 2 ;;
  esac
done

[[ -f "${policy_file}" ]] || { echo "Sensitive-path policy does not exist" >&2; exit 2; }

patterns=()
while IFS= read -r pattern; do
  [[ -n "${pattern}" && "${pattern}" != \#* ]] || continue
  [[ "${pattern}" != /* && "${pattern}" != *".."* ]] || { echo "Invalid policy pattern: ${pattern}" >&2; exit 2; }
  patterns+=("${pattern}")
done < "${policy_file}"
[[ ${#patterns[@]} -gt 0 ]] || { echo "Sensitive-path policy has no patterns" >&2; exit 2; }

paths=("$@")
if [[ ${#paths[@]} -eq 0 ]]; then
  while IFS= read -r path; do
    [[ -n "${path}" ]] && paths+=("${path}")
  done
fi

matched=false
for path in "${paths[@]}"; do
  [[ "${path}" != /* && "${path}" != *".."* ]] || { echo "Invalid repository-relative path: ${path}" >&2; exit 2; }
  for pattern in "${patterns[@]}"; do
    # Bash pattern matching treats '*' as spanning '/', which gives the desired
    # repository-wide semantics for the public '**' policy patterns.
    # shellcheck disable=SC2053 # The policy entry is intentionally a glob.
    if [[ "${path}" == ${pattern} ]]; then
      printf '%s\n' "${path}"
      matched=true
      break
    fi
  done
done

[[ "${matched}" == true ]]
