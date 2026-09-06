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

Read `.agent/bootstrap.yml`. Workflow modes are opt-in and mutually exclusive. Never run `github-workflow` and `superpowers` together for the same task.

Installing components and activating a workflow are separate decisions. Repository Skills and Superpowers may coexist only when the user explicitly requests both. If the user has not chosen installed components and one active workflow, stop and ask; never infer either choice from a generic bootstrap request.

Treat Superpowers as the managed pack for the `superpowers` workflow, not as a general third-party Skill category. In the standard flow, offer its installation only when that workflow is selected.

## Project-specific instructions

- `components.claude_auto_review: selected` is a reminder only. It does not authorize GitHub App installation, authentication, secret configuration, remote mutation, or running /install-github-app; the user must run the official Claude Code installer themselves.

Add durable project-specific commands, architecture constraints, and validation requirements below this heading.
