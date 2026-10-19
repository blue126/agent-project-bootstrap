#!/usr/bin/env bash
set -euo pipefail

# These assertions lock the wording of the Agent-facing guard rails, not
# behaviour. They exist because the guards are prose an Agent reads, so a
# well-meaning rewrite can quietly remove one. Behavioural coverage of the same
# guards lives in the bootstrap/onboarding tests, which assert exit codes and output.
#
# When you deliberately reword a guard, update the matching line here.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The negative assertion at the end of this file shells out to ripgrep. Without
# it the command returns 127 and the guard would silently pass, so require the
# tool up front instead of reporting a false pass.
command -v rg >/dev/null 2>&1 || { echo "ripgrep (rg) is required by the policy text assertions" >&2; exit 1; }

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
for readme in README.md README.zh-CN.md; do
  grep -q '/install-github-app' "${repo_root}/${readme}"
done
grep -Fq '[简体中文](README.zh-CN.md)' "${repo_root}/README.md"
grep -Fq '[English](README.md)' "${repo_root}/README.zh-CN.md"
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
if rg -q -- '--resume|--status|--revisit|BOOTSTRAP_STATE_HOME' "${repo_root}/README.md" "${repo_root}/README.zh-CN.md" "${repo_root}/examples/onboarding.md" "${repo_root}/bootstrap-manifest.yml"; then
  echo 'obsolete onboarding state documentation remains' >&2
  exit 1
fi
grep -Fq 'brownfield' "${repo_root}/examples/onboarding.md"
grep -Fq 'greenfield' "${repo_root}/examples/onboarding.md"
grep -Fq "本仓库的 \`--profile self\` 只适用于 \`blue126/agent-project-bootstrap/main\`" "${repo_root}/examples/onboarding.md"
grep -Fq '治理敏感改动由人工处理' "${repo_root}/CONTRIBUTING.md"
grep -Fq '不应用于下游项目' "${repo_root}/CONTRIBUTING.md"

# Every project receives the governance scaffold, but it stays inactive. Both
# halves must remain stated, or a project silently gets governance files that
# nobody was told about.
grep -Fq 'inactive by default' "${repo_root}/templates/AGENTS.md"
grep -Fq '.agent/governance/sensitive-paths.txt' "${repo_root}/templates/AGENTS.md"
grep -Fq 'must never be reported as verified' "${repo_root}/templates/AGENTS.md"
grep -Fq '治理框架骨架' "${repo_root}/examples/onboarding.md"
grep -Fq '治理框架 · 已写入，未激活' "${repo_root}/scripts/onboard.sh"
grep -Fq 'ui_install_briefing' "${repo_root}/scripts/onboard.sh"
grep -Fq 'ui_install_briefing' "${repo_root}/scripts/lib/onboarding-ui.sh"
grep -Fq 'governance_reviewer' "${repo_root}/scripts/lib/onboarding-project.py"

# Worktree cleanup is a prose contract, not an executable local cleanup tool.
python3 - "${repo_root}" <<'PY_POLICY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
policy = (root / "policies/git.md").read_text()
section = policy.split("## Task worktree lifecycle\n", 1)[1].split("\n## ", 1)[0]
guards = {
    "authorization": ["without asking for permission each time", "merge still requires explicit user authorization"],
    "ownership": ["created by an Agent for an identified task", "a branch name or directory name alone is not proof"],
    "exclusions": ["primary checkout", "user-created worktrees or branches", "another running session", "or remote branches", "runtime-managed lifecycle", ".claude/worktrees/"],
    "timing": ["At the start of each task", "clean up immediately after the checks pass", "from a surviving checkout"],
    "merged PR": ["Required checks (all must pass)", "gh pr view <PR> --repo <OWNER/REPOSITORY>", "state,headRefOid,headRefName", "`state` to be `MERGED`"],
    "contents": ["git status --porcelain --ignored", "no uncommitted tracked changes or untracked content", "git ls-files --others --ignored --exclude-standard", "every ignored artifact can be regenerated", "non-regenerable ignored content must be preserved and blocks cleanup"],
    "delivered HEAD": ["matches the worktree HEAD", "exact equality with the verified PR's `headRefOid`", "git merge-base --is-ancestor <HEAD> origin/<default-branch>", "fetch it successfully first"],
    "failure": ["If any required check fails or evidence is unavailable, preserve the worktree and branch", "Recheck HEAD, status, and session use immediately before removal"],
    "removal": ["`git worktree remove <path>` without `--force`", "then `git branch -d <branch>`", "If worktree removal fails, preserve the branch"],
    "squash exception": ["Only if exact equality with `headRefOid` passed", "refuses because squash merging", "`git branch -D <branch>`", "still has that exact HEAD", "not checked out in another worktree", "ancestry-only evidence do not authorize `-D`"],
    "prune": ["`git worktree prune` may run at any time", "stale administrative records, not worktree directories or branches"],
}
for label, phrases in guards.items():
    for phrase in phrases:
        assert phrase in section, f"Missing worktree {label} guard: {phrase}"

# Every consumer-facing reference must resolve to the one canonical section.
for file in ["templates/AGENTS.md", "CONTRIBUTING.md", "BACKLOG.md",
             "prompts/adopt-github-workflow.md",
             "_bmad-output/specs/spec-agent-project-bootstrap-governance/SPEC.md",
             "_bmad-output/specs/spec-agent-project-bootstrap-governance/rollout-and-rollback.md"]:
    source = root / file
    text = source.read_text()
    links = re.findall(r"\[Task worktree lifecycle\]\(([^)]+)#task-worktree-lifecycle\)", text)
    assert links, f"Missing lifecycle reference: {file}"
    for link in links:
        target = root / "policies/git.md" if file == "templates/AGENTS.md" else source.parent / link
        if file == "templates/AGENTS.md":
            assert link == ".agent/policies/git.md"
        assert target.resolve() == (root / "policies/git.md").resolve(), (file, link)

prompt = (root / "prompts/adopt-github-workflow.md").read_text()
for phrase in ["delete branches or worktrees", "单独展示原文和精确替换差异", "未确认时保留旧规则",
               "bmad:context", "不要只改块里的那一行", "生成源不明或无法更新时", "不留下悬空引用"]:
    assert phrase in prompt, f"Missing legacy migration guard: {phrase}"
for obsolete in ["Agent 不得 merge、force push、删除 branch/worktree", "不得 merge PR，不得删除 branch/worktree"]:
    assert obsolete not in prompt, f"Absolute cleanup ban returned: {obsolete}"
for file in ["SPEC.md", "rollout-and-rollback.md"]:
    text = (root / "_bmad-output/specs/spec-agent-project-bootstrap-governance" / file).read_text()
    assert "不提供" in text and "cleanup CLI" in text and "不冲突" in text
PY_POLICY

echo "policy text tests passed"
