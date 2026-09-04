#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for required_file in LICENSE THIRD_PARTY_NOTICES.md CONTRIBUTING.md SECURITY.md CODE_OF_CONDUCT.md; do
  test -s "${repo_root}/${required_file}" || {
    echo "Missing public project file: ${required_file}" >&2
    exit 1
  }
done
grep -q '^MIT License$' "${repo_root}/LICENSE"

if [[ -d "${repo_root}/skills/human-3-development-assessor" ]] &&
  find "${repo_root}/skills/human-3-development-assessor" -type f | grep -q .; then
  echo "Human 3.0 content must not be bundled in the public tree" >&2
  exit 1
fi
grep -q '^  - id: human-3-development-assessor$' "${repo_root}/third-party-sources.yml"
grep -q '^    license: undeclared$' "${repo_root}/third-party-sources.yml"
grep -q '^    bundled: false$' "${repo_root}/third-party-sources.yml"
grep -q '^    automated: false$' "${repo_root}/third-party-sources.yml"
grep -q '^    action: Visit upstream$' "${repo_root}/third-party-sources.yml"

"${repo_root}/scripts/check-third-party-inventory.sh" >/dev/null

if rg -n 'uses: [^ ]+@(main|master|v[0-9]+([.][0-9]+)*)($|[[:space:]])' "${repo_root}/.github/workflows"; then
  echo "GitHub Actions must use immutable commit SHAs" >&2
  exit 1
fi
while IFS= read -r action_ref; do
  [[ "${action_ref}" =~ @[0-9a-f]{40}$ ]] || {
    echo "Non-immutable GitHub Action reference: ${action_ref}" >&2
    exit 1
  }
done < <(awk '/^[[:space:]]*uses:/ { print $2 }' "${repo_root}"/.github/workflows/*.yml)

while IFS='|' read -r destination license_file notice_pattern; do
  test -d "${repo_root}/${destination}" || { echo "Missing bundled third-party directory: ${destination}" >&2; exit 1; }
  test -s "${repo_root}/${license_file}" || { echo "Missing bundled third-party license: ${license_file}" >&2; exit 1; }
  grep -Fq "${notice_pattern}" "${repo_root}/THIRD_PARTY_NOTICES.md" || {
    echo "Missing third-party notice for: ${notice_pattern}" >&2
    exit 1
  }
done <<'EOF'
skills/rf-first-principles|skills/rf-first-principles/LICENSE|rf-first-principles
skills/rf-adversarial-review|skills/rf-adversarial-review/LICENSE|rf-adversarial-review
skills/pre-mortem|skills/pre-mortem/LICENSE|pre-mortem
skills/thinking-toolkit|skills/thinking-toolkit/LICENSE|thinking-toolkit
EOF

if rg -l --hidden --glob '!/.git/**' --glob '!_bmad-output/**' \
  '(BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})' \
  "${repo_root}" | grep -q .; then
  echo "High-risk credential literal found in tracked project content" >&2
  exit 1
fi

echo "public readiness tests passed"
