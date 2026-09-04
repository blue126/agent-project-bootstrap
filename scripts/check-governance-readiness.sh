#!/usr/bin/env bash
set -euo pipefail

project_dir=""

usage() {
  cat <<'EOF'
Usage: scripts/check-governance-readiness.sh --project DIR

Fail closed unless the project has configured validation backed by a local
adapter manifest whose SHA-256 matches the bootstrap configuration.
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
[[ -f "${config}" ]] || { echo "Project has no bootstrap configuration" >&2; exit 1; }

governance_value() {
  local key="$1"
  awk -v want="${key}:" '
    /^governance:/ { block = 1; next }
    /^[^[:space:]]/ { block = 0 }
    block && $1 == want { print $2; exit }
  ' "${config}"
}

validation="$(governance_value validation)"
mode="$(governance_value validation_mode)"
manifest="$(governance_value validation_adapter_manifest)"
expected_sha="$(governance_value validation_adapter_sha256)"
auto_merge="$(governance_value auto_merge)"

case "${validation}" in
  pending)
    [[ "${mode}" == review_only && "${auto_merge}" == disabled ]] || {
      echo "Pending validation must remain review_only with auto_merge disabled" >&2
      exit 1
    }
    echo "Validation is pending; deterministic gates and auto-merge are not ready" >&2
    exit 1
    ;;
  configured) ;;
  *) echo "Unknown or missing validation state" >&2; exit 1 ;;
esac

case "${mode}" in
  shadow|enforced) ;;
  *) echo "Configured validation must be shadow or enforced" >&2; exit 1 ;;
esac
[[ "${manifest}" != none && "${manifest}" != /* && "${manifest}" != *".."* ]] || {
  echo "Configured validation requires a safe repository-relative adapter manifest" >&2
  exit 1
}
[[ "${expected_sha}" =~ ^[0-9a-f]{64}$ ]] || { echo "Configured validation requires an adapter manifest SHA-256" >&2; exit 1; }
manifest_file="${project_dir}/${manifest}"
[[ -f "${manifest_file}" ]] || { echo "Configured adapter manifest is missing" >&2; exit 1; }

if command -v sha256sum >/dev/null 2>&1; then
  actual_sha="$(sha256sum "${manifest_file}" | cut -d' ' -f1)"
else
  actual_sha="$(shasum -a 256 "${manifest_file}" | cut -d' ' -f1)"
fi
[[ "${actual_sha}" == "${expected_sha}" ]] || { echo "Configured adapter manifest is stale or changed" >&2; exit 1; }

if [[ "${mode}" != enforced && "${auto_merge}" != disabled ]]; then
  echo "Auto-merge requires enforced validation" >&2
  exit 1
fi

echo "Validation adapter is configured for ${mode} mode (${manifest}@${actual_sha})"
