#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

empty_target="${test_root}/empty"
"${repo_root}/scripts/bootstrap.sh" --target "${empty_target}" --workflow github-workflow --skip-skills --skip-understand-anything --skip-claude-auto-review --init-git

test -f "${empty_target}/AGENTS.md"
test -f "${empty_target}/CLAUDE.md"
test -f "${empty_target}/.agent/policies/workflow-selection.md"
grep -q '^schema_version: 5$' "${empty_target}/.agent/bootstrap.yml"
grep -q '^workflow_id: github-workflow$' "${empty_target}/.agent/bootstrap.yml"
grep -q '^  validation: pending$' "${empty_target}/.agent/bootstrap.yml"
grep -q '^  validation_mode: review_only$' "${empty_target}/.agent/bootstrap.yml"
grep -q '^  validation_adapter_manifest: none$' "${empty_target}/.agent/bootstrap.yml"
grep -q '^  auto_merge: disabled$' "${empty_target}/.agent/bootstrap.yml"
grep -q '^  runtime_sha: none$' "${empty_target}/.agent/bootstrap.yml"
grep -q '^  governance_observe: skip$' "${empty_target}/.agent/bootstrap.yml"
test ! -e "${empty_target}/.github/workflows/agent-governance-observe.yml"
test -f "${empty_target}/.agent/governance/sensitive-paths.txt"
if [[ -d "${empty_target}/.agent/validation" ]] &&
  find "${empty_target}/.agent/validation" -type f -perm -u+x | grep -q .; then
  echo "bootstrap unexpectedly created an executable validator" >&2
  exit 1
fi
grep -q '^  curated_skills: skip$' "${empty_target}/.agent/bootstrap.yml"
grep -q '^  workflow_pack: github-workflow$' "${empty_target}/.agent/bootstrap.yml"
grep -q '^  understand_anything:$' "${empty_target}/.agent/bootstrap.yml"
grep -q '^  installation: skip$' "${empty_target}/.agent/bootstrap.yml"
test -f "${empty_target}/.agent/runtime/.gitignore"
test -f "${empty_target}/.agents/skills/.gitignore"
git -C "${empty_target}" rev-parse --git-dir >/dev/null
if git -C "${empty_target}" remote get-url origin >/dev/null 2>&1; then
  echo "bootstrap unexpectedly created origin" >&2
  exit 1
fi

mock_bin="${test_root}/mock-bin"
mkdir -p "${mock_bin}"
cat > "${mock_bin}/gh" <<'EOF'
#!/usr/bin/env bash
echo "bootstrap unexpectedly invoked gh" >&2
exit 99
EOF
chmod +x "${mock_bin}/gh"

selected_target="${test_root}/selected-auto-review"
selected_output="$(PATH="${mock_bin}:${PATH}" "${repo_root}/scripts/bootstrap.sh" \
  --target "${selected_target}" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything \
  --select-claude-auto-review)"
grep -q '^schema_version: 5$' "${selected_target}/.agent/bootstrap.yml"
grep -q '^  claude_auto_review: selected$' "${selected_target}/.agent/bootstrap.yml"
grep -q '/install-github-app' <<<"${selected_output}"
grep -q '^  reviewer: none$' "${selected_target}/.agent/bootstrap.yml"
test ! -e "${selected_target}/.github/workflows"
if git -C "${selected_target}" remote get-url origin >/dev/null 2>&1; then
  echo "Claude Auto Review selection unexpectedly created origin" >&2
  exit 1
fi

skipped_target="${test_root}/skipped-auto-review"
skipped_output="$("${repo_root}/scripts/bootstrap.sh" \
  --target "${skipped_target}" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything \
  --skip-claude-auto-review)"
grep -q '^  claude_auto_review: skipped$' "${skipped_target}/.agent/bootstrap.yml"
if grep -q '/install-github-app' <<<"${skipped_output}"; then
  echo "skipped Claude Auto Review unexpectedly printed setup guidance" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" \
  --target "${test_root}/conflicting-auto-review" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything \
  --select-claude-auto-review \
  --skip-claude-auto-review >/dev/null 2>&1; then
  echo "bootstrap unexpectedly accepted conflicting Claude Auto Review choices" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" \
  --target "${test_root}/missing-auto-review" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything </dev/null >/dev/null 2>&1; then
  echo "non-interactive github-workflow bootstrap unexpectedly chose Claude Auto Review" >&2
  exit 1
fi

if AI_AGENT=codex "${repo_root}/scripts/bootstrap.sh" \
  --target "${test_root}/agent-missing-auto-review" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything >/dev/null 2>&1; then
  echo "Agent bootstrap unexpectedly chose Claude Auto Review" >&2
  exit 1
fi

for workflow in none superpowers; do
  if "${repo_root}/scripts/bootstrap.sh" \
    --target "${test_root}/inapplicable-${workflow}" \
    --workflow "${workflow}" \
    --skip-skills \
    --skip-understand-anything \
    --skip-superpowers \
    --select-claude-auto-review >/dev/null 2>&1; then
    echo "${workflow} unexpectedly accepted Claude Auto Review selection" >&2
    exit 1
  fi
done

if overwrite_output="$("${repo_root}/scripts/bootstrap.sh" --target "${empty_target}" --workflow none --skip-skills --skip-understand-anything 2>&1)"; then
  echo "bootstrap unexpectedly overwrote existing files" >&2
  exit 1
fi
grep -q 'Run again with --update' <<<"${overwrite_output}"

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/conflicting-skills" --workflow none --install-skills --skip-skills --skip-understand-anything >/dev/null 2>&1; then
  echo "bootstrap unexpectedly accepted conflicting Skills choices" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/conflicting-superpowers" --workflow none --skip-skills --skip-understand-anything --install-superpowers --skip-superpowers >/dev/null 2>&1; then
  echo "bootstrap unexpectedly accepted conflicting Superpowers choices" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/invalid" --workflow both --skip-skills --skip-understand-anything >/dev/null 2>&1; then
  echo "bootstrap unexpectedly accepted an invalid workflow" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/missing-workflow" --skip-skills --skip-understand-anything --skip-superpowers </dev/null >/dev/null 2>&1; then
  echo "non-interactive bootstrap unexpectedly chose a workflow" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/missing-skills" --workflow none --skip-understand-anything --skip-superpowers </dev/null >/dev/null 2>&1; then
  echo "non-interactive bootstrap unexpectedly chose a Skills mode" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/missing-superpowers" --workflow superpowers --skip-skills --skip-understand-anything </dev/null >/dev/null 2>&1; then
  echo "non-interactive bootstrap unexpectedly chose a Superpowers mode" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/noninteractive-install" --workflow none --install-skills --skip-understand-anything --skip-superpowers </dev/null >/dev/null 2>&1; then
  echo "non-interactive bootstrap unexpectedly launched the interactive Skills installer" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/noninteractive-superpowers" --workflow none --skip-skills --skip-understand-anything --install-superpowers </dev/null >/dev/null 2>&1; then
  echo "non-interactive bootstrap unexpectedly launched the interactive Superpowers installer" >&2
  exit 1
fi

if agent_install_output="$(AI_AGENT=codex "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/agent-install" --workflow none --install-skills --skip-understand-anything --skip-superpowers 2>&1)"; then
  echo "Agent environment unexpectedly launched interactive Skill installation" >&2
  exit 1
fi
grep -q 'must be run by the user in a regular terminal' <<<"${agent_install_output}"

if agent_prompt_output="$(CODEX_THREAD_ID=test-thread "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/agent-prompt" 2>&1)"; then
  echo "Agent environment unexpectedly hosted bootstrap selectors" >&2
  exit 1
fi
grep -q 'cannot host the interactive bootstrap selectors' <<<"${agent_prompt_output}"

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/missing-repo" --workflow none --skip-skills --skip-understand-anything --configure-github >/dev/null 2>&1; then
  echo "GitHub configuration unexpectedly accepted a missing repository" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/unused-repo" --workflow none --skip-skills --skip-understand-anything --github-repo acme/project >/dev/null 2>&1; then
  echo "GitHub repository unexpectedly accepted without explicit configuration" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/missing-understand-anything" --workflow none --skip-skills </dev/null >/dev/null 2>&1; then
  echo "non-interactive bootstrap unexpectedly chose an Understand Anything mode" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/conflicting-understand-anything" --workflow none --skip-skills --install-understand-anything --skip-understand-anything >/dev/null 2>&1; then
  echo "bootstrap unexpectedly accepted conflicting Understand Anything choices" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/missing-visibility" --workflow none --skip-skills --skip-understand-anything --create-github --github-repo acme/project >/dev/null 2>&1; then
  echo "GitHub repository creation unexpectedly accepted missing visibility" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" --target "${test_root}/unused-visibility" --workflow none --skip-skills --skip-understand-anything --github-visibility private >/dev/null 2>&1; then
  echo "GitHub visibility unexpectedly accepted without repository creation" >&2
  exit 1
fi

echo "bootstrap tests passed"
