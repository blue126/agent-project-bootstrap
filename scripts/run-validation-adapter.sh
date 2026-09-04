#!/usr/bin/env bash
set -euo pipefail

adapter_root=""
manifest_file=""
workspace=""
repository=""
pull_request=""
base_sha=""
head_sha=""
expected_manifest_sha=""

usage() {
  cat <<'EOF'
Usage: scripts/run-validation-adapter.sh --adapter-root DIR --manifest FILE --workspace DIR \
  --repo OWNER/REPOSITORY --pr NUMBER --base-sha FULL_SHA --head-sha FULL_SHA \
  --expected-manifest-sha SHA256

Run a trusted repository validation adapter against a PR workspace. The adapter
control plane is outside the PR workspace and receives no inherited secrets.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --adapter-root) [[ $# -ge 2 ]] || exit 2; adapter_root="$2"; shift 2 ;;
    --manifest) [[ $# -ge 2 ]] || exit 2; manifest_file="$2"; shift 2 ;;
    --workspace) [[ $# -ge 2 ]] || exit 2; workspace="$2"; shift 2 ;;
    --repo) [[ $# -ge 2 ]] || exit 2; repository="$2"; shift 2 ;;
    --pr) [[ $# -ge 2 ]] || exit 2; pull_request="$2"; shift 2 ;;
    --base-sha) [[ $# -ge 2 ]] || exit 2; base_sha="$2"; shift 2 ;;
    --head-sha) [[ $# -ge 2 ]] || exit 2; head_sha="$2"; shift 2 ;;
    --expected-manifest-sha) [[ $# -ge 2 ]] || exit 2; expected_manifest_sha="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[[ -d "${adapter_root}" && -d "${workspace}" ]] || { echo "Adapter root and workspace must exist" >&2; exit 2; }
adapter_root="$(cd "${adapter_root}" && pwd)"
workspace="$(cd "${workspace}" && pwd)"
[[ -f "${manifest_file}" ]] || { echo "Adapter manifest does not exist" >&2; exit 2; }
manifest_file="$(cd "$(dirname "${manifest_file}")" && pwd)/$(basename "${manifest_file}")"
[[ "${manifest_file}" == "${adapter_root}/"* ]] || { echo "Manifest must be inside the trusted adapter root" >&2; exit 1; }
[[ "${repository}" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] || { echo "Invalid repository" >&2; exit 2; }
[[ "${pull_request}" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid pull request number" >&2; exit 2; }
[[ "${base_sha}" =~ ^[0-9a-f]{40}$ && "${head_sha}" =~ ^[0-9a-f]{40}$ ]] || { echo "Full lowercase base/head SHAs are required" >&2; exit 2; }
[[ "${expected_manifest_sha}" =~ ^[0-9a-f]{64}$ ]] || { echo "Expected manifest SHA-256 is required" >&2; exit 2; }

if command -v sha256sum >/dev/null 2>&1; then
  actual_manifest_sha="$(sha256sum "${manifest_file}" | cut -d' ' -f1)"
else
  actual_manifest_sha="$(shasum -a 256 "${manifest_file}" | cut -d' ' -f1)"
fi
[[ "${actual_manifest_sha}" == "${expected_manifest_sha}" ]] || { echo "Adapter manifest SHA mismatch" >&2; exit 1; }

jq -e '
  type == "object" and
  ((keys - ["upstream"] | sort) == (["contract_version", "entrypoint", "id", "license", "supported_stacks", "version"] | sort)) and
  (.contract_version == 1) and
  (.id | type == "string" and test("^[a-z0-9][a-z0-9-]*$")) and
  (.version | type == "string" and length > 0) and
  (.license | type == "string" and length > 0) and
  (.entrypoint | type == "string" and length > 0 and (startswith("/") | not) and
    (split("/") | all(. != ".." and . != "." and . != ""))) and
  (.supported_stacks | type == "array" and length > 0 and all(.[]; type == "string" and length > 0)) and
  (.upstream == null or (.upstream | type == "string" and test("^https://")))
' "${manifest_file}" >/dev/null || { echo "Invalid validation adapter manifest" >&2; exit 1; }

entrypoint="$(jq -r '.entrypoint' "${manifest_file}")"
adapter_id="$(jq -r '.id' "${manifest_file}")"
adapter_version="$(jq -r '.version' "${manifest_file}")"
adapter_entrypoint="${adapter_root}/${entrypoint}"
[[ -f "${adapter_entrypoint}" && -x "${adapter_entrypoint}" ]] || { echo "Adapter entrypoint is missing or not executable" >&2; exit 1; }

clean_home="$(mktemp -d)"
result_file="$(mktemp)"
cleanup() { rm -rf "${clean_home}"; rm -f "${result_file}"; }
trap cleanup EXIT

if ! env -i \
  HOME="${clean_home}" \
  PATH="${PATH}" \
  AGENT_VALIDATION_WORKSPACE="${workspace}" \
  AGENT_VALIDATION_REPOSITORY="${repository}" \
  AGENT_VALIDATION_PULL_REQUEST="${pull_request}" \
  AGENT_VALIDATION_BASE_SHA="${base_sha}" \
  AGENT_VALIDATION_HEAD_SHA="${head_sha}" \
  AGENT_VALIDATION_ADAPTER_ID="${adapter_id}" \
  AGENT_VALIDATION_ADAPTER_VERSION="${adapter_version}" \
  AGENT_VALIDATION_MANIFEST_SHA256="${actual_manifest_sha}" \
  "${adapter_entrypoint}" > "${result_file}"; then
  echo "Validation adapter execution failed" >&2
  exit 1
fi

jq -e \
  --arg repository "${repository}" \
  --argjson pull_request "${pull_request}" \
  --arg validated_sha "${head_sha}" \
  --arg adapter_id "${adapter_id}" \
  --arg adapter_version "${adapter_version}" \
  --arg manifest_sha "${actual_manifest_sha}" '
  type == "object" and
  ((keys | sort) == (["adapter", "pull_request", "repository", "status", "summary", "validated_sha"] | sort)) and
  .repository == $repository and
  .pull_request == $pull_request and
  .validated_sha == $validated_sha and
  .adapter == {
    id: $adapter_id,
    version: $adapter_version,
    manifest_sha256: $manifest_sha
  } and
  (.status == "pass" or .status == "fail") and
  (.summary | type == "string" and length > 0 and length <= 2000)
' "${result_file}" >/dev/null || { echo "Invalid or stale validation result" >&2; exit 1; }

if [[ "$(jq -r '.status' "${result_file}")" != pass ]]; then
  echo "Repository validation reported failure" >&2
  exit 1
fi

cat "${result_file}"
