#!/usr/bin/env bash
set -euo pipefail

# These assertions lock the wording of the Agent-facing guard rails, not
# behaviour. They exist because the guards are prose an Agent reads, so a
# well-meaning rewrite can quietly remove one. Behavioural coverage of the same
# guards lives in test-bootstrap.sh, which asserts exit codes and output.
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
grep -q 'Open the Curated Skills selector now' "${repo_root}/scripts/bootstrap.sh"
grep -q 'standard_installation_follows_active_workflow: true' "${repo_root}/bootstrap-manifest.yml"
grep -q 'installation_default: prompt' "${repo_root}/bootstrap-manifest.yml"
grep -q 'user_level_writes_allowed: false' "${repo_root}/integrations/understand-anything/integration.yml"
grep -q 'visibility_must_be_explicit: true' "${repo_root}/bootstrap-manifest.yml"
grep -q 'github-workflow is active but Curated Skills installation was skipped' "${repo_root}/scripts/bootstrap.sh"
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

echo "policy text tests passed"
