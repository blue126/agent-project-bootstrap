#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
inventory="${repo_root}/third-party-sources.yml"
notices="${repo_root}/THIRD_PARTY_NOTICES.md"
license_policy="${repo_root}/policies/third-party-license-policy.txt"

[[ -f "${inventory}" && -f "${notices}" && -f "${license_policy}" ]] || {
  echo "Missing third-party inventory, notices, or license policy" >&2
  exit 1
}
accepted_licenses="$(awk 'NF && $1 !~ /^#/ { print }' "${license_policy}")"

entries="$(awk '
  function emit() { if (name != "") print name "|" destination "|" license }
  /^skills:/ { in_skills = 1; next }
  /^external_catalog:/ { emit(); in_skills = 0; name = ""; next }
  in_skills && /^  - name:/ { emit(); name = $3; destination = ""; license = ""; next }
  in_skills && /^    destination:/ { destination = $2; next }
  in_skills && /^    license:/ { sub(/^    license: /, ""); license = $0; next }
  END { if (in_skills) emit() }
' "${inventory}")"

[[ -n "${entries}" ]] || { echo "No bundled third-party entries found" >&2; exit 1; }
while IFS='|' read -r name destination license; do
  [[ -n "${name}" && -n "${destination}" && -n "${license}" ]] || {
    echo "Incomplete bundled third-party inventory entry: ${name:-unknown}" >&2
    exit 1
  }
  [[ "${license}" != undeclared && "${license}" != "none declared upstream" ]] || {
    echo "Bundled content has no declared license: ${name}" >&2
    exit 1
  }
  grep -Fxq "${license}" <<<"${accepted_licenses}" || {
    echo "Bundled content has an unapproved license: ${name} (${license})" >&2
    exit 1
  }
  [[ -d "${repo_root}/${destination}" ]] || { echo "Missing bundled directory for ${name}" >&2; exit 1; }
  [[ -s "${repo_root}/${destination}/LICENSE" ]] || { echo "Missing bundled LICENSE for ${name}" >&2; exit 1; }
  grep -Fq "${name}" "${notices}" || { echo "Missing THIRD_PARTY_NOTICES entry for ${name}" >&2; exit 1; }
done <<<"${entries}"

grep -Fq 'maintainer_acceptance: explicit-2026-09-04' "${inventory}" || {
  echo "Restricted bundled license lacks explicit maintainer acceptance" >&2
  exit 1
}
grep -Fq '维护者已明确接受该销售限制' "${notices}" || {
  echo "Restricted bundled license lacks a prominent notice" >&2
  exit 1
}

echo "third-party inventory consistency passed"
