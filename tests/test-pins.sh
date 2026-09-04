#!/usr/bin/env bash
set -euo pipefail

# Managed integration pins are duplicated between the integration manifests and
# the installer scripts. Nothing at runtime reconciles them, so a promotion that
# updates one copy and misses another would silently install an unreviewed ref.
# These assertions are the reconciliation.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

known_good() {
  local manifest="$1" key="$2" value
  value="$(
    awk -v key="${key}:" '
      /^known_good:/ { block = 1; next }
      /^[^[:space:]]/ { block = 0 }
      block && $1 == key { print $2; exit }
    ' "${manifest}"
  )"
  [[ -n "${value}" ]] || {
    echo "Could not read known_good.${key} from ${manifest}" >&2
    exit 1
  }
  printf '%s\n' "${value}"
}

assert_contains() {
  local file="$1" needle="$2"
  grep -Fq "${needle}" "${file}" || {
    echo "Pin drift: ${file} does not contain '${needle}'" >&2
    exit 1
  }
}

superpowers_manifest="${repo_root}/integrations/superpowers/integration.yml"
superpowers_tag="$(known_good "${superpowers_manifest}" tag)"
superpowers_ref="$(known_good "${superpowers_manifest}" ref)"

assert_contains "${repo_root}/scripts/bootstrap.sh" "superpowers_tag=\"${superpowers_tag}\""
assert_contains "${repo_root}/scripts/bootstrap.sh" "superpowers_ref=\"${superpowers_ref}\""
assert_contains "${superpowers_manifest}" "obra/superpowers/tree/${superpowers_tag}"

understand_manifest="${repo_root}/integrations/understand-anything/integration.yml"
understand_tag="$(known_good "${understand_manifest}" tag)"
understand_ref="$(known_good "${understand_manifest}" ref)"

assert_contains "${repo_root}/scripts/bootstrap.sh" "understand_anything_tag=\"${understand_tag}\""
assert_contains "${repo_root}/scripts/bootstrap.sh" "understand_anything_ref=\"${understand_ref}\""
assert_contains "${repo_root}/scripts/install-understand-anything.sh" "ref=\"${understand_ref}\""

for ref in "${superpowers_ref}" "${understand_ref}"; do
  [[ "${ref}" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Pin '${ref}' is not an immutable 40-character commit" >&2
    exit 1
  }
done

# The Skills CLI is fetched by npx at bootstrap time; an unpinned version can
# silently change installer behaviour (for example symlink versus copy).
cli_version="$(
  awk '/^skills:/ { block = 1; next }
       /^[^[:space:]]/ { block = 0 }
       block && $1 == "cli_version:" { print $2; exit }' "${repo_root}/bootstrap-manifest.yml"
)"
[[ -n "${cli_version}" ]] || { echo "bootstrap-manifest.yml declares no skills.cli_version" >&2; exit 1; }
assert_contains "${repo_root}/scripts/bootstrap.sh" "skills_cli_version=\"${cli_version}\""
assert_contains "${repo_root}/integrations/superpowers/integration.yml" "npx skills@${cli_version} add"
assert_contains "${repo_root}/scripts/rehydrate.sh" "npx skills@${cli_version} add"

# Curated Skills install from this checkout: the source repository is private,
# so the URL form would need credentials and could lag behind local edits.
# shellcheck disable=SC2016  # the single quotes are the point: match the literal source line
assert_contains "${repo_root}/scripts/bootstrap.sh" 'npx "skills@${skills_cli_version}" add "${repo_root}"'

observe_sha="$(awk '$1 == "observe_release_sha:" { print $2 }' "${repo_root}/bootstrap-manifest.yml")"
[[ "${observe_sha}" =~ ^[0-9a-f]{40}$ ]] || { echo "Observe runtime is not pinned to a full SHA" >&2; exit 1; }
assert_contains "${repo_root}/scripts/bootstrap.sh" "governance_observe_runtime_sha=\"${observe_sha}\""
assert_contains "${repo_root}/templates/github/governance-observe.yml" "governance-observe.yml@${observe_sha}"
assert_contains "${repo_root}/releases/governance-runtime.yml" "commit: ${observe_sha}"
assert_contains "${repo_root}/releases/governance-runtime.yml" 'required_gate: false'

validation_sha="$(awk '$1 == "commit:" { print $2; exit }' "${repo_root}/releases/repo-validation-runtime.yml")"
[[ "${validation_sha}" =~ ^[0-9a-f]{40}$ ]] || { echo "Validation runtime is not pinned to a full SHA" >&2; exit 1; }
assert_contains "${repo_root}/templates/github/repo-validation.yml" "repo-validation.yml@${validation_sha}"
assert_contains "${repo_root}/scripts/install-repo-validation-caller.sh" "runtime_sha=\"${validation_sha}\""

echo "pin consistency tests passed"
