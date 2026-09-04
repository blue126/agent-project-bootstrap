#!/usr/bin/env bash
set -euo pipefail

project_dir=""
usage() {
  cat <<'EOF'
Usage: scripts/set-governance-safe-mode.sh --project DIR

Prepare a consumer rollback by setting fixer=none, auto_merge=disabled, and
reducing enforced validation to shadow. This does not alter GitHub settings,
delete secrets, revoke Apps, or rewrite runtime pins.
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

validation="$(awk '/^  validation:/ { print $2; exit }' "${config}")"
case "${validation}" in pending) safe_mode=review_only ;; configured) safe_mode=shadow ;; *) echo "Unknown validation state" >&2; exit 1 ;; esac
for required in fixer validation_mode auto_merge; do
  grep -q "^  ${required}:" "${config}" || { echo "Missing governance field: ${required}" >&2; exit 1; }
done

temporary="$(mktemp "${config}.tmp.XXXXXX")"
cleanup() { rm -f "${temporary}"; }
trap cleanup EXIT
awk -v safe_mode="${safe_mode}" '
  /^  fixer:/ { print "  fixer: none"; next }
  /^  validation_mode:/ { print "  validation_mode: " safe_mode; next }
  /^  auto_merge:/ { print "  auto_merge: disabled"; next }
  { print }
' "${config}" > "${temporary}"
mv "${temporary}" "${config}"
trap - EXIT
echo "Prepared governance safe mode: fixer=none validation_mode=${safe_mode} auto_merge=disabled"
