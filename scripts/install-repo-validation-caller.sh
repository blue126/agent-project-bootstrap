#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_dir=""
runtime_sha="cb1dc39d68ba7475afaa6272882b48b0f87269a9"
source_file="${repo_root}/templates/github/repo-validation.yml"
destination_relative=".github/workflows/repo-validation.yml"

usage() {
  cat <<'EOF'
Usage: scripts/install-repo-validation-caller.sh --project DIR

Install or safely update the managed repo-validation caller only after a real
adapter is configured. Consumer-edited callers are preserved and cause failure.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) [[ $# -ge 2 ]] || exit 2; project_dir="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -d "${project_dir}" ]] || { echo "Project directory does not exist" >&2; exit 2; }
project_dir="$(cd "${project_dir}" && pwd)"
config="${project_dir}/.agent/bootstrap.yml"
destination="${project_dir}/${destination_relative}"
[[ -f "${config}" ]] || { echo "Project has no bootstrap configuration" >&2; exit 1; }
"${repo_root}/scripts/check-governance-readiness.sh" --project "${project_dir}" >/dev/null

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

desired_hash="$(hash_file "${source_file}")"
recorded_hash="$(awk -v want="${destination_relative}:" '
  /^managed_files:/ { block = 1; next }
  /^[^[:space:]]/ { block = 0 }
  block && $1 == want { print $2; exit }
' "${config}")"

if [[ -e "${destination}" ]]; then
  current_hash="$(hash_file "${destination}")"
  if [[ "${current_hash}" != "${desired_hash}" && ( -z "${recorded_hash}" || "${current_hash}" != "${recorded_hash}" ) ]]; then
    echo "Refusing to overwrite consumer-edited repo-validation caller: ${destination}" >&2
    exit 1
  fi
fi

mkdir -p "$(dirname "${destination}")"
cp "${source_file}" "${destination}"

grep -q '^managed_files:$' "${config}" || { echo "Bootstrap configuration has no managed_files block" >&2; exit 1; }
has_runtime=false
has_component=false
has_managed=false
grep -q '^  repo_validation_runtime_sha:' "${config}" && has_runtime=true
grep -q '^  repo_validation:' "${config}" && has_component=true
grep -q "^  ${destination_relative}:" "${config}" && has_managed=true

temporary="$(mktemp "${config}.tmp.XXXXXX")"
cleanup() { rm -f "${temporary}"; }
trap cleanup EXIT
awk \
  -v runtime_sha="${runtime_sha}" \
  -v destination="${destination_relative}" \
  -v desired_hash="${desired_hash}" \
  -v has_runtime="${has_runtime}" \
  -v has_component="${has_component}" \
  -v has_managed="${has_managed}" '
  /^  repo_validation_runtime_sha:/ { print "  repo_validation_runtime_sha: " runtime_sha; next }
  /^  runtime_sha:/ && has_runtime == "false" { print; print "  repo_validation_runtime_sha: " runtime_sha; next }
  /^  repo_validation:/ { print "  repo_validation: install"; next }
  /^  governance_observe:/ && has_component == "false" { print; print "  repo_validation: install"; next }
  $1 == destination ":" { print "  " destination ": " desired_hash; next }
  /^managed_files:/ && has_managed == "false" { print; print "  " destination ": " desired_hash; next }
  { print }
' "${config}" > "${temporary}"
mv "${temporary}" "${config}"
trap - EXIT

echo "Installed repo-validation caller pinned to ${runtime_sha}"
