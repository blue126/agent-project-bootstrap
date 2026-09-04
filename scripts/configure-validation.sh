#!/usr/bin/env bash
set -euo pipefail

project_dir=""
manifest_relative=""
mode="shadow"

usage() {
  cat <<'EOF'
Usage: scripts/configure-validation.sh --project DIR --manifest REPOSITORY_RELATIVE_PATH [--mode shadow|enforced]

Bind an existing project-local adapter manifest into .agent/bootstrap.yml.
This command does not install an adapter, enable auto-merge, or guess a stack.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) [[ $# -ge 2 ]] || exit 2; project_dir="$2"; shift 2 ;;
    --manifest) [[ $# -ge 2 ]] || exit 2; manifest_relative="$2"; shift 2 ;;
    --mode) [[ $# -ge 2 ]] || exit 2; mode="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[[ -d "${project_dir}" ]] || { echo "Project directory does not exist" >&2; exit 2; }
project_dir="$(cd "${project_dir}" && pwd)"
case "${mode}" in shadow|enforced) ;; *) echo "--mode must be shadow or enforced" >&2; exit 2 ;; esac
[[ -n "${manifest_relative}" && "${manifest_relative}" != /* && "${manifest_relative}" != *".."* ]] || {
  echo "--manifest must be a safe repository-relative path" >&2
  exit 2
}

config="${project_dir}/.agent/bootstrap.yml"
manifest_file="${project_dir}/${manifest_relative}"
[[ -f "${config}" ]] || { echo "Project has no bootstrap configuration" >&2; exit 1; }
[[ -f "${manifest_file}" ]] || { echo "Adapter manifest does not exist" >&2; exit 1; }

jq -e '
  type == "object" and
  ((keys - ["upstream"] | sort) == (["contract_version", "entrypoint", "id", "license", "supported_stacks", "version"] | sort)) and
  .contract_version == 1 and
  (.id | type == "string" and test("^[a-z0-9][a-z0-9-]*$")) and
  (.entrypoint | type == "string" and length > 0 and (startswith("/") | not) and
    (split("/") | all(. != ".." and . != "." and . != ""))) and
  (.supported_stacks | type == "array" and length > 0)
' "${manifest_file}" >/dev/null || { echo "Invalid validation adapter manifest" >&2; exit 1; }

if command -v sha256sum >/dev/null 2>&1; then
  manifest_sha="$(sha256sum "${manifest_file}" | cut -d' ' -f1)"
else
  manifest_sha="$(shasum -a 256 "${manifest_file}" | cut -d' ' -f1)"
fi

for required_line in \
  '  validation:' \
  '  validation_mode:' \
  '  validation_adapter_manifest:' \
  '  validation_adapter_sha256:'; do
  grep -q "^${required_line}" "${config}" || {
    echo "Bootstrap configuration predates governance schema v4; update it before configuring validation" >&2
    exit 1
  }
done

temporary="$(mktemp "${config}.tmp.XXXXXX")"
cleanup() { rm -f "${temporary}"; }
trap cleanup EXIT
awk \
  -v mode="${mode}" \
  -v manifest="${manifest_relative}" \
  -v sha="${manifest_sha}" '
  /^  validation:/ { print "  validation: configured"; next }
  /^  validation_mode:/ { print "  validation_mode: " mode; next }
  /^  validation_adapter_manifest:/ { print "  validation_adapter_manifest: " manifest; next }
  /^  validation_adapter_sha256:/ { print "  validation_adapter_sha256: " sha; next }
  { print }
' "${config}" > "${temporary}"
mv "${temporary}" "${config}"
trap - EXIT

"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-governance-readiness.sh" --project "${project_dir}"
