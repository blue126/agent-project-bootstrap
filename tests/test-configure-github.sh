#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT
mock_bin="${test_root}/bin"
mkdir -p "${mock_bin}"

cat > "${mock_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${MOCK_GH_LOG}"

if [[ "$1" == auth && "$2" == status ]]; then
  exit 0
fi

arguments=" $* "
if [[ "${arguments}" == *" repos/acme/project --jq .permissions.admin // false "* ]]; then
  echo "configure-github must not require full repository admin permission" >&2
  exit 1
fi
if [[ "${arguments}" == *" repos/acme/project/git/ref/heads/main "* ]]; then
  [[ "${MOCK_SCENARIO}" != missing-main ]]
  exit $?
fi
if [[ "${arguments}" == *" repos/acme/project/rulesets --paginate "* ]]; then
  case "${MOCK_SCENARIO}" in
    create|missing-main) ;;
    same|update|param-drift|merge-method-drift) echo 42 ;;
  esac
  exit 0
fi
if [[ "${arguments}" == *" repos/acme/project/rulesets/42 "* && "${arguments}" != *" --method PUT "* ]]; then
  if [[ "${MOCK_SCENARIO}" == same ]]; then
    jq '. + {id: 42, source_type: "Repository"}' "${MOCK_RULESET_FILE}"
  elif [[ "${MOCK_SCENARIO}" == param-drift ]]; then
    jq '(.rules[] | select(.type == "non_fast_forward")) |= (. + {parameters: {tampered: true}}) | . + {id: 42, source_type: "Repository"}' "${MOCK_RULESET_FILE}"
  elif [[ "${MOCK_SCENARIO}" == merge-method-drift ]]; then
    jq '(.rules[] | select(.type == "pull_request").parameters.allowed_merge_methods) = ["merge", "squash", "rebase"] | . + {id: 42, source_type: "Repository"}' "${MOCK_RULESET_FILE}"
  else
    jq '.enforcement = "disabled" | . + {id: 42, source_type: "Repository"}' "${MOCK_RULESET_FILE}"
  fi
  exit 0
fi
if [[ "${arguments}" == *" --method POST "* || "${arguments}" == *" --method PUT "* ]]; then
  exit 0
fi

echo "Unexpected mock gh invocation: $*" >&2
exit 1
EOF
chmod +x "${mock_bin}/gh"

run_scenario() {
  scenario="$1"
  log_file="${test_root}/${scenario}.log"
  output_file="${test_root}/${scenario}.out"
  PATH="${mock_bin}:${PATH}" \
    MOCK_SCENARIO="${scenario}" \
    MOCK_GH_LOG="${log_file}" \
    MOCK_RULESET_FILE="${repo_root}/github/rulesets/protect-main.json" \
    "${repo_root}/scripts/configure-github.sh" --repo acme/project > "${output_file}"
}

run_scenario create
grep -q -- '--method POST' "${test_root}/create.log"
grep -q 'Created active Protect main' "${test_root}/create.out"

run_scenario same
if grep -q -- '--method PUT' "${test_root}/same.log"; then
  echo "unchanged ruleset unexpectedly triggered an update" >&2
  exit 1
fi
grep -q 'already configured' "${test_root}/same.out"

run_scenario update
grep -q -- '--method PUT' "${test_root}/update.log"
grep -q 'Updated active Protect main' "${test_root}/update.out"

# Rule types the normalizer does not model must still be reconciled: their
# parameters are compared verbatim, so tampering is detected rather than
# collapsed away.
run_scenario param-drift
grep -q -- '--method PUT' "${test_root}/param-drift.log"
grep -q 'Updated active Protect main' "${test_root}/param-drift.out"

run_scenario merge-method-drift
grep -q -- '--method PUT' "${test_root}/merge-method-drift.log"
grep -q 'Updated active Protect main' "${test_root}/merge-method-drift.out"

if PATH="${mock_bin}:${PATH}" \
  MOCK_SCENARIO=missing-main \
  MOCK_GH_LOG="${test_root}/missing-main.log" \
  MOCK_RULESET_FILE="${repo_root}/github/rulesets/protect-main.json" \
  "${repo_root}/scripts/configure-github.sh" --repo acme/project >/dev/null 2>&1; then
  echo "missing main unexpectedly succeeded" >&2
  exit 1
fi

echo "GitHub ruleset tests passed"
