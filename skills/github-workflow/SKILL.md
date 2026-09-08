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
4. Preserve unrelated changes. Apply the asset classification and pre-commit review in `.agent/policies/git.md` before staging, including the first commit. Track by project purpose, not hidden/generated/output naming. If that policy is absent, report it and agree on the project's asset rules before staging; do not claim bootstrap checks ran.
5. Run relevant validation and the secret scan, checking scan coverage/configuration and changed configuration validity. Inspect files, symlinks/targets, nested repositories/worktrees, large files, and the final staged content. Stage only explicitly reviewed paths; never use broad staging such as `git add .` or `git add -A`.
6. Report track/exclude/reproduce decisions, validation evidence, and unresolved gaps. Commit, push, and create a pull request only with user authorization. Default new pull requests to Draft unless the user asks otherwise.
7. Report the branch, validation evidence, commit, and pull-request URL, marking actions not performed. Policy installation alone does not verify commit contents. A merged pull request does not authorize deleting uncommitted work during branch or worktree cleanup.

If there is no remote yet, complete only authorized safe local initialization and report the missing remote instead of inventing one. Standard stateless onboarding's create-or-connect flow never stages, commits, or pushes; publication is a separate authorized action.

