#!/usr/bin/env bash
set -euo pipefail

# These assertions lock the wording of the Agent-facing guard rails, not
# behaviour. They exist because the guards are prose an Agent reads, so a
# well-meaning rewrite can quietly remove one. Behavioural coverage of the same
# guards lives in the bootstrap/onboarding tests, which assert exit codes and output.
#
# When you deliberately reword a guard, update the matching line here.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -q 'explicitly invokes github-workflow' "${repo_root}/skills/github-workflow/SKILL.md"
grep -q 'mutually_exclusive: true' "${repo_root}/bootstrap-manifest.yml"
grep -q 'fork: false' "${repo_root}/integrations/superpowers/integration.yml"
grep -q 'bulk_install_on_bootstrap: false' "${repo_root}/integrations/superpowers/integration.yml"
grep -q 'obra/superpowers/tree/v6.3.0' "${repo_root}/integrations/superpowers/integration.yml"
grep -q 'verify_superpowers_ref' "${repo_root}/scripts/bootstrap.sh"
grep -q 'do not ask the user to reply with a custom configuration string' "${repo_root}/AGENTS.md"
grep -Fq "Do not execute \`npx skills add\` in an Agent-owned process" "${repo_root}/AGENTS.md"
grep -q 'do not choose a workflow or create a chat questionnaire' "${repo_root}/scripts/bootstrap.sh"
grep -q 'Do not unset Agent or Codex detection variables' "${repo_root}/scripts/bootstrap.sh"
# Do not freeze the old prompt order or require installation to activate a workflow.
grep -q 'standard_installation_follows_active_workflow: false' "${repo_root}/bootstrap-manifest.yml"
grep -q 'installation_default: prompt' "${repo_root}/bootstrap-manifest.yml"
grep -q 'user_level_writes_allowed: false' "${repo_root}/integrations/understand-anything/integration.yml"
grep -q 'visibility_must_be_explicit: true' "${repo_root}/bootstrap-manifest.yml"
grep -q 'initial_validation: pending' "${repo_root}/bootstrap-manifest.yml"
grep -q 'auto_merge_when_pending: false' "${repo_root}/bootstrap-manifest.yml"
grep -q 'bundled_implementations: false' "${repo_root}/bootstrap-manifest.yml"
grep -q '"required_review_thread_resolution": true' "${repo_root}/github/rulesets/protect-main.json"
grep -q '"squash"' "${repo_root}/github/rulesets/protect-main.json"
grep -q '^schema_version: 5$' "${repo_root}/bootstrap-manifest.yml"
grep -q '^  claude_auto_review:$' "${repo_root}/bootstrap-manifest.yml"
grep -q 'eligible_workflow: github-workflow' "${repo_root}/bootstrap-manifest.yml"
grep -q 'post_bootstrap_command: /install-github-app' "${repo_root}/bootstrap-manifest.yml"
grep -q 'does not configure GitHub App, authentication, secrets, remotes, providers, or workflows' "${repo_root}/bootstrap-manifest.yml"
grep -q "does not authorize an Agent to run \`/install-github-app\`" "${repo_root}/AGENTS.md"
grep -q 'does not authorize GitHub App installation, authentication, secret configuration, remote mutation, or running /install-github-app' "${repo_root}/templates/AGENTS.md"
grep -q '/install-github-app' "${repo_root}/README.md"
grep -q 'Claude Auto Review guidance was selected' "${repo_root}/scripts/bootstrap.sh"

# Local-first onboarding keeps installation, explicit adoption and execution separate.
for guard in \
  'entrypoint: scripts/bootstrap.sh' \
  'default_target: current_working_directory' \
  'target_override: --target DIR' \
  'mode: stateless_reconcile' \
  'ordinary_skills_with_existing_installations: always_offer' \
  'client_selection: confirm_every_run' \
  'remote_inspection: after_collaboration_opt_in_only' \
  'existing_workflow: preserve_without_activation_or_overwrite' \
  'none_detected: install_one_or_skip' \
  'classify_unknown_workflows: false' \
  'skip_disables_existing_rules: false' \
  'activation_is_separate_from_installation: true' \
  'detection_is_activation: false' \
  'agent_owned_pty_allowed: false' \
  'update_preserves_metadata: true' \
  'update_rejects_installation_and_git_mutation_flags: true' \
  'create_mode: scripts/create-github.sh --create-only' \
  'attach_mode: scripts/create-github.sh --attach-only'; do
  grep -Fq -- "${guard}" "${repo_root}/bootstrap-manifest.yml"
done
grep -q '^    - bmad$' "${repo_root}/bootstrap-manifest.yml"
grep -Fq 'Skipping does not disable unknown rules' "${repo_root}/AGENTS.md"
grep -Fq 'do not activate multiple workflows for a task' "${repo_root}/AGENTS.md"
grep -Fq "do not unset \`AI_AGENT\` or \`CODEX_*\` variables" "${repo_root}/AGENTS.md"
grep -Fq "Do not add \`--all\`, \`-y\`, or \`-g\` unless explicitly requested" "${repo_root}/AGENTS.md"
grep -Fq 'selector running in an Agent tool PTY' "${repo_root}/AGENTS.md"
grep -Fq 'never use its upstream global installer' "${repo_root}/AGENTS.md"
grep -Fq 'It never stages, commits, or pushes' "${repo_root}/AGENTS.md"
grep -Fq 'Update never re-runs an installer and rejects installation or Git-mutation flags' "${repo_root}/AGENTS.md"
grep -Fq 'Installation records do not authorize workflow execution' "${repo_root}/templates/AGENTS.md"
grep -Fq 'Skipping does not disable unknown rules' "${repo_root}/templates/AGENTS.md"
grep -Fq 'Never run them in an Agent-owned PTY' "${repo_root}/templates/AGENTS.md"
grep -Fq "Known values are \`none\`, \`github-workflow\`, \`superpowers\`, and \`bmad\`" "${repo_root}/policies/workflow-selection.md"
grep -Fq 'Component inventory alone is not activation' "${repo_root}/policies/workflow-selection.md"
if rg -q -- '--resume|--status|--revisit|BOOTSTRAP_STATE_HOME' "${repo_root}/README.md" "${repo_root}/examples/onboarding.md" "${repo_root}/bootstrap-manifest.yml"; then
  echo 'obsolete onboarding state documentation remains' >&2
  exit 1
fi
grep -Fq 'brownfield' "${repo_root}/examples/onboarding.md"
grep -Fq 'greenfield' "${repo_root}/examples/onboarding.md"
grep -Fq "本仓库的 \`--profile self\` 只适用于 \`blue126/agent-project-bootstrap/main\`" "${repo_root}/examples/onboarding.md"
grep -Fq '治理敏感改动由人工处理' "${repo_root}/CONTRIBUTING.md"
grep -Fq '不应用于下游项目' "${repo_root}/CONTRIBUTING.md"

echo "policy text tests passed"
