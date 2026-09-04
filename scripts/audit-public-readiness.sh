#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
include_history=false

usage() {
  cat <<'EOF'
Usage: scripts/audit-public-readiness.sh [--history]

Audit the tracked publication tree. --history also reports whether the private
Git history must be excluded. Suspected values are never printed, only paths or
aggregate metadata.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --history) include_history=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

cd "${repo_root}"
failed=false
has_git=false
if git rev-parse --git-dir >/dev/null 2>&1; then
  has_git=true
fi

report_paths() {
  local label="$1" pattern="$2" paths
  if [[ "${has_git}" == true ]]; then
    paths="$(git grep -Il -E "${pattern}" -- . ':(exclude)scripts/audit-public-readiness.sh' || true)"
  else
    paths="$(rg -l -uu -g '!.git/**' -g '!scripts/audit-public-readiness.sh' "${pattern}" . || true)"
  fi
  if [[ -n "${paths}" ]]; then
    echo "BLOCKED ${label}"
    printf '%s\n' "${paths}"
    failed=true
  else
    echo "PASS ${label}"
  fi
}

for required_file in LICENSE THIRD_PARTY_NOTICES.md CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md; do
  [[ -s "${required_file}" ]] || { echo "BLOCKED missing ${required_file}"; failed=true; }
done

report_paths secret_literals '(BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})'
report_paths personal_or_internal_literals '(/Users/[^ /]+|/home/[^ /]+|@gmail[.]com|@icloud[.]com|https?://[^ /]*(internal|private|corp|localhost)|git@[^ :]+:|ssh://|(^|[^0-9])(10[.][0-9]{1,3}[.]|192[.]168[.]|172[.](1[6-9]|2[0-9]|3[01])[.]))'

if { [[ "${has_git}" == true ]] && git ls-files --error-unmatch skills/human-3-development-assessor >/dev/null 2>&1; } ||
  [[ -e skills/human-3-development-assessor ]]; then
  echo "BLOCKED unlicensed Human 3.0 content is bundled"
  failed=true
else
  echo "PASS Human 3.0 is external-catalog only"
fi

if grep -El '(This repository is private|private repository|prefer the local path)' AGENTS.md README.md | grep -q .; then
  echo "BLOCKED stale private-distribution wording"
  grep -El '(This repository is private|private repository|prefer the local path)' AGENTS.md README.md
  failed=true
else
  echo "PASS public installation wording"
fi

"${repo_root}/scripts/check-third-party-inventory.sh" >/dev/null
echo "PASS third-party inventory consistency"

echo "PASS bundled license allowlist and explicit restriction acceptance"

if [[ "${include_history}" == true ]]; then
  [[ "${has_git}" == true ]] || { echo "--history requires the private source Git repository" >&2; exit 2; }
  history_secret_paths="$(for commit in $(git rev-list --all); do
    git grep -Il -E '(BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})' "${commit}" -- . 2>/dev/null || true
  done | sed -E 's/^[0-9a-f]{40}://' | sort -u)"
  if [[ -n "${history_secret_paths}" ]]; then
    echo "BLOCKED secret-like literals exist in private history paths"
    printf '%s\n' "${history_secret_paths}"
    failed=true
  else
    echo "PASS no high-confidence secret literal found in history"
  fi

  personal_domains="$(git log --all --format='%ae%n%ce' | awk -F@ 'NF == 2 { print $2 }' | sort -u)"
  if grep -Fxq gmail.com <<<"${personal_domains}"; then
    echo "NOTICE private history contains personal email metadata"
  fi
  if for commit in $(git rev-list --all); do
    git ls-tree -r --name-only "${commit}" -- skills/human-3-development-assessor
  done | grep -q .; then
    echo "NOTICE private history contains unlicensed Human 3.0 content"
  fi
  echo "REQUIRED publish a no-history snapshot; never expose the private Git object database"
fi

if [[ "${failed}" == true ]]; then
  exit 1
fi
echo "Public-readiness audit passed"
