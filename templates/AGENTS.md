# AGENTS.md

This file is the cross-agent policy source for this project. Agent-specific files may add harness instructions but must not duplicate or override it.

## Project policies

Read and follow:

- `.agent/policies/core.md`
- `.agent/policies/git.md`
- `.agent/policies/workflow-selection.md`

Use `.agent/policies/git.md` for purpose-based asset tracking, exclusions, and pre-commit review, including shared hidden/generated assets. Installing the policy does not mean first-commit contents are verified; report what will be tracked, excluded, or reproduced and the review evidence separately.

## Repository authority

When `origin/main` exists, it is the eventual code authority. Do not assume an `origin` remote exists in a newly initialized project.

Never develop, commit, or push directly on `main` or `master`. Use a purpose-specific branch and verify changes before publishing.

## Workflow mode

Read `.agent/bootstrap.yml` and preserve existing project instructions. Known workflow modes are `none`, `github-workflow`, `superpowers`, and `bmad`. Workflow execution is opt-in and mutually exclusive: never run more than one workflow for the same task.

Installing components, detecting existing installations, and activating a workflow are separate decisions. Installation records do not authorize workflow execution. Activate only through an explicit user request or an explicit active-workflow selection; if incompatible workflows are requested, stop and ask the user to choose one.

For generic bootstrap requests, guide the user to the README quick start: acquire or reuse the toolkit, enter their own project root, and run the toolkit's bootstrap.sh without --target (defaults to the current directory). Do not mistake the toolkit checkout for the target project or route this request to Skills-only installation. Use the local-first stateless terminal wizard rather than choosing for them or creating a chat questionnaire. It confirms project clients, preserves or explicitly selects a workflow, offers Skills, prepares policy and local Git, then reports readiness and first-task instructions. Re-running rechecks actual state, not a saved position. The wizard detects only `github-workflow`, `superpowers`, and `bmad`; detection alone never activates or reinstalls them. Explicit adoption may set the active preference after configuration confirmation, but does not run tasks. Ordinary Skills remain independently available even with existing installations. Skipping does not disable unknown rules; Superpowers remains a managed workflow pack, not a generic third-party Skill category.

`project_agents` is a portable project preference, not installation evidence or authorization. The user confirms clients every run; native installers reuse those targets while retaining scope/method choices. Universal denotes a shared directory, not every client. Local files do not prove a client session has loaded them. GitHub/CI/review/protection are an optional continuation after local setup; do not contact even an existing remote before that opt-in.

The user must run interactive installers in a regular human terminal. Never run them in an Agent-owned PTY, clear `AI_AGENT` or `CODEX_*` detection variables, or add unsolicited `--all`, `-y`, or `-g`. Understand Anything is project-scoped and optional; installing it does not imply analysis has run.

Onboarding may explicitly create or connect a GitHub repository, but does not stage, commit, or push. Local validation, CI, review, and branch protection require separate evidence; a completed prompt is not verified governance. Sensitive governance changes require human handling. `--update` preserves metadata and does not authorize installation or Git mutation.

## Project-specific instructions

- `components.claude_auto_review: selected` is a reminder only. It does not authorize GitHub App installation, authentication, secret configuration, remote mutation, or running /install-github-app; the user must run the official Claude Code installer themselves.

Add durable project-specific commands, architecture constraints, and validation requirements below this heading.
