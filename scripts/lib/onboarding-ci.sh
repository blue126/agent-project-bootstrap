#!/usr/bin/env bash
# shellcheck disable=SC2154
# Safe, bounded CI skeleton inspection and writing for optional onboarding.

ci_require_safe_path() {
  local path="${1:?path required}" current=""
  case "${path}" in
    "${target_dir}"/*) ;;
    *) echo "CI path escapes target" >&2; return 1 ;;
  esac
  current="${target_dir}"
  local suffix="${path#"${target_dir}"/}" segment
  IFS=/ read -r -a segments <<< "${suffix}"
  for segment in "${segments[@]}"; do
    current="${current}/${segment}"
    [[ ! -L "${current}" ]] || { echo "Refusing CI symlink path: ${current}" >&2; return 1; }
  done
}

ci_workflow_dir() { printf '%s\n' "${target_dir}/.github/workflows"; }
ci_skeleton_path() { printf '%s/ci.yml\n' "$(ci_workflow_dir)"; }

ci_skeleton_state() {
  local workflow_dir skeleton candidate
  workflow_dir="$(ci_workflow_dir)"
  skeleton="$(ci_skeleton_path)"
  if [[ -L "${target_dir}/.github" || -L "${workflow_dir}" || -L "${skeleton}" ]]; then
    printf '%s\n' unsafe
    return
  fi
  if [[ -f "${skeleton}" ]] && cmp -s "${repo_root}/templates/github/ci.yml" "${skeleton}"; then
    printf '%s\n' scaffold_pending
    return
  fi
  shopt -s nullglob
  for candidate in "${workflow_dir}"/*.yml "${workflow_dir}"/*.yaml; do
    [[ -e "${candidate}" || -L "${candidate}" ]] || continue
    printf '%s\n' configured_unverified
    shopt -u nullglob
    return
  done
  shopt -u nullglob
  printf '%s\n' missing
}

ci_write_skeleton() {
  local workflow_dir skeleton temporary
  workflow_dir="$(ci_workflow_dir)"
  skeleton="$(ci_skeleton_path)"
  ci_require_safe_path "${target_dir}/.github" || return 1
  ci_require_safe_path "${workflow_dir}" || return 1
  ci_require_safe_path "${skeleton}" || return 1
  [[ ! -e "${skeleton}" && ! -L "${skeleton}" ]] || {
    echo "CI skeleton destination already exists: ${skeleton}" >&2
    return 1
  }
  mkdir -p "${workflow_dir}"
  ci_require_safe_path "${workflow_dir}" || return 1
  ci_require_safe_path "${skeleton}" || return 1
  [[ ! -e "${skeleton}" && ! -L "${skeleton}" ]] || {
    echo "CI skeleton destination changed during setup: ${skeleton}" >&2
    return 1
  }
  temporary="$(mktemp "${workflow_dir}/.ci.yml.XXXXXX")"
  cp "${repo_root}/templates/github/ci.yml" "${temporary}"
  if [[ -e "${skeleton}" || -L "${skeleton}" ]]; then
    rm -f "${temporary}"
    echo "CI skeleton destination changed during write: ${skeleton}" >&2
    return 1
  fi
  mv "${temporary}" "${skeleton}"
  printf '%s\n' "${skeleton}"
}
