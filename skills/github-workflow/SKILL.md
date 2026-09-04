---
name: github-workflow
description: Run the project's branch, validation, commit, push, and pull-request workflow. Use only when the user explicitly invokes github-workflow or the project selects workflow_id github-workflow in .agent/bootstrap.yml; never auto-activate from a generic GitHub request.
---

# GitHub workflow

This is an opt-in workflow. Before using it, read `AGENTS.md`, `.agent/policies/git.md`, `.agent/policies/workflow-selection.md`, and `.agent/bootstrap.yml` when present.

## Activation gate

Proceed only when `github-workflow` is explicitly selected. Refuse to combine this workflow with `superpowers`; ask the user to choose one when both are selected.

## Workflow

1. Inspect Git state. Do not assume the directory is a repository or that `origin` exists.
2. If a repository exists, inspect the current branch, worktree status, remotes, and the default upstream branch.
3. Never work directly on `main` or `master`; create or switch to a purpose-specific branch before editing or committing.
4. Preserve unrelated changes. Stage only confirmed paths from the requested work.
5. Run relevant validation and inspect the final diff.
6. Commit, push, and create a pull request only with user authorization. Default new pull requests to Draft unless the user asks otherwise.
7. Report the branch, validation evidence, commit, and pull-request URL.

If there is no remote yet, complete safe local initialization and report the missing remote instead of inventing one.

