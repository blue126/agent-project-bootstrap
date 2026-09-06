#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repository=""
enforcement="active"
profile="baseline"
native_auto_merge="unchanged"
dry_run=false
ruleset_file="${repo_root}/github/rulesets/protect-main.json"
api_version="2022-11-28"

usage() {
  cat <<'EOF'
Usage: scripts/configure-github.sh --repo OWNER/REPOSITORY [--enforcement active|evaluate|disabled]
       [--profile baseline|self] [--native-auto-merge unchanged|enable|disable] [--dry-run]

The default baseline profile reconciles "Protect main" on the verified default
branch. The self profile manages separate "Self CI gates" only for
blue126/agent-project-bootstrap/main and never rewrites Protect main.
Native auto-merge changes require self; disable only switches off that capability.
Dry-run permits remote reads but no remote writes. It is not an offline mode.
Requires authenticated gh, jq, git, and permission to edit the selected settings.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || { echo "--repo requires OWNER/REPOSITORY" >&2; exit 2; }
      repository="$2"
      shift 2
      ;;
    --enforcement)
      [[ $# -ge 2 ]] || { echo "--enforcement requires active, evaluate, or disabled" >&2; exit 2; }
      enforcement="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || { echo "--profile requires baseline or self" >&2; exit 2; }
      profile="$2"
      shift 2
      ;;
    --native-auto-merge)
      [[ $# -ge 2 ]] || { echo "--native-auto-merge requires unchanged, enable, or disable" >&2; exit 2; }
      native_auto_merge="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
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
case "${enforcement}" in active|evaluate|disabled) ;; *) echo "Invalid --enforcement value" >&2; exit 2 ;; esac
case "${profile}" in baseline|self) ;; *) echo "Invalid --profile value" >&2; exit 2 ;; esac
case "${native_auto_merge}" in unchanged|enable|disable) ;; *) echo "Invalid --native-auto-merge value" >&2; exit 2 ;; esac
if [[ "${profile}" == self ]]; then
  [[ "${repository}" == blue126/agent-project-bootstrap && "${enforcement}" == active ]] || {
    echo "self requires --repo blue126/agent-project-bootstrap and active enforcement" >&2; exit 2;
  }
elif [[ "${native_auto_merge}" != unchanged ]]; then
  echo "Native auto-merge settings require --profile self" >&2; exit 2
fi

for command_name in gh jq git; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "${command_name} is required" >&2
    exit 1
  }
done

gh auth status >/dev/null

work_dir="$(mktemp -d)"
rendered_ruleset="${work_dir}/rendered.json"
current_file="${work_dir}/current.json"
desired_file="${work_dir}/desired.json"
cleanup() { rm -rf "${work_dir}"; }
trap cleanup EXIT

api() {
  if [[ "${dry_run}" == true ]]; then
    for argument in "$@"; do
      case "${argument}" in
        --method|-X|--input|-f|-F|--field|--raw-field|--method=*|--input=*)
          echo "Internal error: dry-run attempted a mutating API call" >&2; return 1 ;;
      esac
    done
  fi
  gh api \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: ${api_version}" \
    "$@"
}

find_self_ruleset() {
  local name="$1" ids count
  ids="$(api "repos/${repository}/rulesets" --paginate \
    --jq ".[] | select(.name == \"${name}\" and .source_type == \"Repository\") | .id")" || return 1
  count="$(printf '%s\n' "${ids}" | awk 'NF { count++ } END { print count + 0 }')"
  if [[ "${count}" -gt 1 || ( -n "${ids}" && ! "${ids}" =~ ^[1-9][0-9]*$ ) ]]; then
    echo "Ambiguous repository-level ${name} ruleset; refusing to choose one" >&2
    return 1
  fi
  printf '%s' "${ids}"
}

verify_self_baseline() {
  local baseline_id
  baseline_id="$(find_self_ruleset 'Protect main')"
  [[ -n "${baseline_id}" ]] || { echo "self requires an existing Protect main ruleset" >&2; return 1; }
  api "repos/${repository}/rulesets/${baseline_id}" > "${work_dir}/baseline.json"
  jq -e '
    .target == "branch" and .enforcement == "active" and
    has("bypass_actors") and .bypass_actors == [] and
    .conditions.ref_name.include == ["refs/heads/main"] and
    .conditions.ref_name.exclude == [] and
    any(.rules[]; .type == "deletion") and any(.rules[]; .type == "non_fast_forward") and
    any(.rules[]; .type == "pull_request" and
      .parameters.required_review_thread_resolution == true and
      .parameters.allowed_merge_methods == ["squash"])
  ' "${work_dir}/baseline.json" >/dev/null || {
    echo "Protect main protections are missing, bypassed, or ambiguous; refusing enablement" >&2; return 1;
  }
}

normalize_self_ruleset() {
  jq -S '{name, target, enforcement, bypass_actors, conditions,
    rules: [.rules[] |
      if .type == "required_status_checks" then
        .parameters.required_status_checks |= sort_by(.context, .integration_id) |
        .parameters.do_not_enforce_on_create = (.parameters.do_not_enforce_on_create // false)
      else . end] | sort_by(.type)}' "$@"
}

reconcile_native_auto_merge() {
  local desired current
  [[ "${native_auto_merge}" != unchanged ]] || return 0
  desired=false
  [[ "${native_auto_merge}" != enable ]] || desired=true
  current="$(api "repos/${repository}" --jq .allow_auto_merge)"
  [[ "${current}" == true || "${current}" == false ]] || {
    echo "Unable to read repository auto-merge setting" >&2; return 1;
  }
  if [[ "${current}" == "${desired}" ]]; then
    echo "Native auto-merge is already ${desired} for ${repository}"
    return 0
  fi
  if [[ "${dry_run}" == true ]]; then
    echo "Would PATCH repos/${repository}: allow_auto_merge=${desired} (enable requires verified gates)"
    return 0
  fi
  jq -n --argjson enabled "${desired}" '{allow_auto_merge: $enabled}' > "${work_dir}/settings.json"
  api --method PATCH "repos/${repository}" --input "${work_dir}/settings.json" >/dev/null
  [[ "$(api "repos/${repository}" --jq .allow_auto_merge)" == "${desired}" ]] || {
    echo "Native auto-merge readback did not match requested setting" >&2; return 1;
  }
  echo "Native auto-merge is ${desired} for ${repository}; no PR was enrolled or merged"
}

configure_self() {
  local gate_id gate_file self_template
  self_template="${repo_root}/github/rulesets/self-ci-gates.json"
  api "repos/${repository}" > "${work_dir}/repository.json"
  jq -e '.full_name == "blue126/agent-project-bootstrap" and .default_branch == "main"' \
    "${work_dir}/repository.json" >/dev/null || {
    echo "self requires the verified blue126/agent-project-bootstrap/main identity" >&2; return 1;
  }
  # Recovery must remain possible when branch rules or checks are broken.
  if [[ "${native_auto_merge}" == disable ]]; then
    reconcile_native_auto_merge
    return
  fi
  api "repos/${repository}/git/ref/heads/main" >/dev/null
  verify_self_baseline
  gate_id="$(find_self_ruleset 'Self CI gates')"
  gate_file="${work_dir}/gate.json"
  if [[ -n "${gate_id}" ]]; then
    api "repos/${repository}/rulesets/${gate_id}" > "${gate_file}"
    jq -e '
      .target == "branch" and has("bypass_actors") and .bypass_actors == [] and
      .conditions == {ref_name: {include: ["refs/heads/main"], exclude: []}} and
      (.rules | type == "array") and
      ([.rules[] | select(.type == "required_status_checks")] | length <= 1)
    ' "${gate_file}" >/dev/null || {
      echo "Self CI gates scope, bypass information, or rule cardinality is unsafe" >&2; return 1;
    }
    jq --slurpfile desired "${self_template}" '
      . as $current |
      $desired[0].rules[0] as $wanted |
      ([.rules[] | select(.type == "required_status_checks")][0] //
        {type: "required_status_checks", parameters: {required_status_checks: []}}) as $existing |
      $existing.parameters.required_status_checks as $checks |
      if ($checks | type) != "array" then error("Invalid required check list") else . end |
      if any($wanted.parameters.required_status_checks[]; . as $required |
        any($checks[]; .context == $required.context and .integration_id != $required.integration_id))
      then error("Conflicting required check producer; refusing to overwrite") else . end |
      {name: $desired[0].name, target: .target, enforcement: "active", bypass_actors, conditions,
       rules: ([.rules[] | select(.type != "required_status_checks")] + [
         $existing | .parameters += $wanted.parameters |
         .parameters.required_status_checks =
           (($checks + $wanted.parameters.required_status_checks) | unique_by(.context, .integration_id))
       ])}
    ' "${gate_file}" > "${rendered_ruleset}"
    normalize_self_ruleset "${gate_file}" > "${current_file}"
    normalize_self_ruleset "${rendered_ruleset}" > "${desired_file}"
    if cmp -s "${current_file}" "${desired_file}"; then
      echo "Self CI gates is already configured for ${repository}"
    elif [[ "${dry_run}" == true ]]; then
      echo "Would PUT repos/${repository}/rulesets/${gate_id} with:"
      jq . "${rendered_ruleset}"
    else
      api --method PUT "repos/${repository}/rulesets/${gate_id}" --input "${rendered_ruleset}" >/dev/null
      echo "Updated Self CI gates for ${repository}"
    fi
  else
    cp "${self_template}" "${rendered_ruleset}"
    if [[ "${dry_run}" == true ]]; then
      echo "Would POST repos/${repository}/rulesets with:"
      jq . "${rendered_ruleset}"
    else
      api --method POST "repos/${repository}/rulesets" --input "${rendered_ruleset}" >/dev/null
      echo "Created Self CI gates for ${repository}"
    fi
  fi
  if [[ "${dry_run}" == true ]]; then
    echo "Dry-run: would verify active, strict, producer-bound gates before enabling native auto-merge"
    reconcile_native_auto_merge
    return
  fi
  # Verify the server state, even after a create or an already-configured no-op.
  gate_id="$(find_self_ruleset 'Self CI gates')"
  [[ -n "${gate_id}" ]] || { echo "Self CI gates missing on readback" >&2; return 1; }
  api "repos/${repository}/rulesets/${gate_id}" > "${gate_file}"
  normalize_self_ruleset "${gate_file}" > "${current_file}"
  normalize_self_ruleset "${rendered_ruleset}" > "${desired_file}"
  cmp -s "${current_file}" "${desired_file}" || { echo "Self CI gates readback mismatch" >&2; return 1; }
  api "repos/${repository}/rules/branches/main" > "${work_dir}/effective.json"
  jq -e --argjson gate_id "${gate_id}" --slurpfile desired "${rendered_ruleset}" '
    any(.[]; .ruleset_id == $gate_id and .type == "required_status_checks" and
      .parameters.strict_required_status_checks_policy == true and
      (.parameters.do_not_enforce_on_create // false) == false and
      ((.parameters.required_status_checks | sort_by(.context, .integration_id)) ==
       ($desired[0].rules[] | select(.type == "required_status_checks") |
         .parameters.required_status_checks | sort_by(.context, .integration_id))))
  ' "${work_dir}/effective.json" >/dev/null || {
    echo "Required CI checks are not effective on main; refusing enablement" >&2; return 1;
  }
  verify_self_baseline
  echo "Verified active Self CI gates on ${repository}/main"
  reconcile_native_auto_merge
}

if [[ "${profile}" == self ]]; then
  configure_self
  exit 0
fi

default_branch="$(api "repos/${repository}" --jq .default_branch)"
[[ -n "${default_branch}" ]] || { echo "GitHub repository has no default branch" >&2; exit 1; }
git check-ref-format --branch "${default_branch}" >/dev/null 2>&1 || {
  echo "GitHub returned an invalid default branch name" >&2
  exit 1
}
if ! api "repos/${repository}/git/ref/heads/${default_branch}" >/dev/null 2>&1; then
  echo "Verified default branch refs/heads/${default_branch} does not exist" >&2
  exit 1
fi
jq \
  --arg enforcement "${enforcement}" \
  --arg default_ref "refs/heads/${default_branch}" \
  '.enforcement = $enforcement | .conditions.ref_name.include = [$default_ref]' \
  "${ruleset_file}" > "${rendered_ruleset}"

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
  if [[ "${dry_run}" == true ]]; then
    echo "Would POST repos/${repository}/rulesets with:"
    jq . "${rendered_ruleset}"
  else
    api --method POST "repos/${repository}/rulesets" --input "${rendered_ruleset}" >/dev/null
    echo "Created ${enforcement} Protect main ruleset for ${repository}"
  fi
  exit 0
fi

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
normalize_ruleset "${rendered_ruleset}" > "${desired_file}"

if cmp -s "${current_file}" "${desired_file}"; then
  echo "Protect main is already configured for ${repository}"
  exit 0
fi

if [[ "${dry_run}" == true ]]; then
  echo "Would PUT repos/${repository}/rulesets/${ruleset_ids} with:"
  jq . "${rendered_ruleset}"
else
  api --method PUT "repos/${repository}/rulesets/${ruleset_ids}" \
    --input "${rendered_ruleset}" >/dev/null
  echo "Updated ${enforcement} Protect main ruleset for ${repository}"
fi
