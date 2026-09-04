# Git and GitHub policy

- When `origin/main` exists, it is the eventual code authority. Fetch and compare before publishing work.
- Do not assume an `origin` remote, a GitHub repository, or even an initialized Git repository exists.
- Never develop, commit, or push directly on `main` or `master`. Create a purpose-specific branch first.
- Do not create commits, push branches, open pull requests, or mutate remote state without user authorization.
- Treat an explicit bootstrap `--create-github` invocation with repository and visibility as authorization only for its generated bootstrap commit, repository creation, `origin`, and initial `main` push.
- Inspect status and diffs before staging. Stage only files that belong to the requested change.
- Do not discard, overwrite, or rewrite user work unless the user explicitly authorizes the exact destructive action.
