#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository=""
ruleset_file="${repo_root}/github/rulesets/protect-main.json"
api_version="2022-11-28"

usage() {
  cat <<'EOF'
Usage: scripts/configure-github.sh --repo OWNER/REPOSITORY

Create or reconcile the repository-level "Protect main" ruleset.
Requires authenticated gh, jq, an existing main branch, and permission to edit repository rules.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "--repo requires OWNER/REPOSITORY" >&2; exit 2; }
      repository="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "${repository}" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
  echo "--repo must be an explicit OWNER/REPOSITORY value" >&2
  exit 2
fi

for command_name in gh jq; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "${command_name} is required" >&2
    exit 1
  }
done

gh auth status >/dev/null

api() {
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: ${api_version}" \
    "$@"
}

if ! api "repos/${repository}/git/ref/heads/main" >/dev/null 2>&1; then
  echo "refs/heads/main must exist before enabling Protect main" >&2
  exit 1
fi

ruleset_ids="$(
  api "repos/${repository}/rulesets" --paginate \
    --jq '.[] | select(.name == "Protect main" and .source_type == "Repository") | .id'
)"
ruleset_count="$(printf '%s\n' "${ruleset_ids}" | awk 'NF { count++ } END { print count + 0 }')"

if [[ "${ruleset_count}" -gt 1 ]]; then
  echo "Multiple repository-level rulesets named Protect main exist; refusing to choose one" >&2
  exit 1
fi

if [[ "${ruleset_count}" -eq 0 ]]; then
  api --method POST "repos/${repository}/rulesets" --input "${ruleset_file}" >/dev/null
  echo "Created active Protect main ruleset for ${repository}"
  exit 0
fi

current_file="$(mktemp)"
desired_file="$(mktemp)"
cleanup() {
  rm -f "${current_file}" "${desired_file}"
}
trap cleanup EXIT

normalize_ruleset() {
  jq -S '
    {
      name,
      target,
      enforcement,
      bypass_actors: [
        (.bypass_actors // [])[] |
        {actor_id, actor_type, bypass_mode}
      ] | sort_by(.actor_type, .actor_id, .bypass_mode),
      conditions: {
        ref_name: {
          include: (.conditions.ref_name.include | sort),
          exclude: (.conditions.ref_name.exclude | sort)
        }
      },
      rules: [
        .rules[] |
        if .type == "pull_request" then
          {
            type,
            parameters: {
              dismiss_stale_reviews_on_push: .parameters.dismiss_stale_reviews_on_push,
              require_code_owner_review: .parameters.require_code_owner_review,
              require_last_push_approval: .parameters.require_last_push_approval,
              required_approving_review_count: .parameters.required_approving_review_count,
              required_review_thread_resolution: .parameters.required_review_thread_resolution,
              allowed_merge_methods: (.parameters.allowed_merge_methods | sort)
            }
          }
        else
          # Any other rule type keeps its parameters verbatim, so adding a
          # parameterised rule to the payload cannot silently stop being
          # reconciled.
          {type, parameters: (.parameters // null)}
        end
      ] | sort_by(.type)
    }
  ' "$@"
}

api "repos/${repository}/rulesets/${ruleset_ids}" |
  normalize_ruleset > "${current_file}"
normalize_ruleset "${ruleset_file}" > "${desired_file}"

if cmp -s "${current_file}" "${desired_file}"; then
  echo "Protect main is already configured for ${repository}"
  exit 0
fi

api --method PUT "repos/${repository}/rulesets/${ruleset_ids}" \
  --input "${ruleset_file}" >/dev/null
echo "Updated active Protect main ruleset for ${repository}"
