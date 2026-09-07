# AGENTS.md

This file is the cross-agent policy source for this project. Agent-specific files may add harness instructions but must not duplicate or override it.

## Project policies

Read and follow:

- `.agent/policies/core.md`
- `.agent/policies/git.md`
- `.agent/policies/workflow-selection.md`

## Repository authority

When `origin/main` exists, it is the eventual code authority. Do not assume an `origin` remote exists in a newly initialized project.

Never develop, commit, or push directly on `main` or `master`. Use a purpose-specific branch and verify changes before publishing.

## Workflow mode

Read `.agent/bootstrap.yml` and preserve existing project instructions. Known workflow modes are `none`, `github-workflow`, `superpowers`, and `bmad`. Workflow execution is opt-in and mutually exclusive: never run more than one workflow for the same task.

Installing components, detecting existing installations, and activating a workflow are separate decisions. Installation records do not authorize workflow execution. Activate only through an explicit user request or an explicit active-workflow selection; if incompatible workflows are requested, stop and ask the user to choose one.

For generic bootstrap requests, guide the user to the resumable terminal wizard rather than choosing a workflow or creating a chat questionnaire. The wizard detects only `github-workflow`, `superpowers`, and `bmad`: keep a detected workflow without activating, reinstalling, or overwriting it; if none is detected, offer one installation or skip. Skipping does not disable existing unknown rules. Ordinary Skills are a separate optional installation, not another workflow mode. Superpowers remains the managed pack for `superpowers`, not a general third-party Skill category.

The user must run interactive installers in a regular human terminal. Never run them in an Agent-owned PTY, clear `AI_AGENT` or `CODEX_*` detection variables, or add unsolicited `--all`, `-y`, or `-g`. Understand Anything is project-scoped and optional; installing it does not imply analysis has run.

Onboarding may explicitly create or connect a GitHub repository, but does not stage, commit, or push. Local validation, CI, review, and branch protection require separate evidence; a completed prompt is not verified governance. Sensitive governance changes require human handling. `--update` preserves metadata and does not authorize installation or Git mutation.

## Project-specific instructions

- `components.claude_auto_review: selected` is a reminder only. It does not authorize GitHub App installation, authentication, secret configuration, remote mutation, or running /install-github-app; the user must run the official Claude Code installer themselves.

Add durable project-specific commands, architecture constraints, and validation requirements below this heading.
