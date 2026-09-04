#!/usr/bin/env bash
set -euo pipefail

output_dir=""
source_ref="HEAD"

usage() {
  cat <<'EOF'
Usage: scripts/create-public-snapshot.sh --output NEW_DIRECTORY [--ref COMMIT_OR_TREE]

Export a tracked Git tree without history. The output path must not exist.
This command does not create a repository, commit, remote, or GitHub resource.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) [[ $# -ge 2 ]] || exit 2; output_dir="$2"; shift 2 ;;
    --ref) [[ $# -ge 2 ]] || exit 2; source_ref="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "${output_dir}" ]] || { echo "--output is required" >&2; exit 2; }
[[ ! -e "${output_dir}" ]] || { echo "Output path already exists; refusing to overwrite it" >&2; exit 1; }
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolved_tree="$(git -C "${repo_root}" rev-parse "${source_ref}^{tree}")" || { echo "Source ref does not resolve to a tree" >&2; exit 1; }

mkdir -p "${output_dir}"
git -C "${repo_root}" archive --format=tar "${resolved_tree}" | tar -xf - -C "${output_dir}"

if find "${output_dir}" -name .git -print -quit | grep -q .; then
  echo "Snapshot unexpectedly contains Git metadata" >&2
  exit 1
fi
if [[ -e "${output_dir}/skills/human-3-development-assessor" ]]; then
  echo "Snapshot unexpectedly contains Human 3.0 content" >&2
  exit 1
fi

echo "Created no-history public snapshot tree ${resolved_tree} at ${output_dir}"
