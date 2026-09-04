# AGENTS.md

## Repository purpose

This repository is the public source of truth for an Agent project bootstrap distribution. It contains distributable Skills, managed integration metadata, project policies, governance contracts, templates, and bootstrap tooling. Runtime installations, consumer secrets, and personal data live elsewhere.

## Installing Skills from this repository

When a user supplies this repository URL and asks to install its Skills, run the standard interactive installer from the target project:

```bash
npx skills add https://github.com/blue126/agent-project-bootstrap
```

Let the user choose Skills and target agent. Do not add `--all`, `-y`, or `-g` unless explicitly requested. Do not use Codex's private installer path.

Supported target agents are `codex`, `opencode`, and `claude-code`. Codex and OpenCode share the project-level `.agents/skills/`; Claude Code uses `.claude/skills/`. If the target agent is not one of these, explain that automatic installation cannot be guaranteed.

## Bootstrapping a project

When a user makes a generic bootstrap request without already specifying every choice, do not choose for them and do not recreate the installer as a chat questionnaire. In particular, do not ask the user to reply with a custom configuration string such as `workflow=..., repo-skills=...`.

Instead, give the user the interactive command and a brief explanation, then wait for its result:

```bash
/absolute/path/to/agent-project-bootstrap/scripts/bootstrap.sh --target "$PWD"
```

Explain only that the command first offers the Curated Skills selector, offers the project-scoped Understand Anything integration, and then selects one active workflow. `github-workflow` is part of the Curated Skills catalog. Only when the user selects the `superpowers` workflow should the command offer the pinned Superpowers workflow-pack selector.

The user must run the command themselves in a regular terminal session such as Terminal.app or iTerm. Do not execute `npx skills add` in an Agent-owned process, do not unset `AI_AGENT` or `CODEX_*` variables, and do not claim that a selector running in an Agent tool PTY is visible in the user's terminal. The `skills` CLI detects Agent environments and may switch to non-interactive installation even when a PTY exists.

If the user only wants Skills, guide them straight to the native interactive installer:

```bash
npx skills add https://github.com/blue126/agent-project-bootstrap
```

Use non-interactive bootstrap flags only when the user already supplied the choices in their own request. Never solicit a configuration string merely to make the flags available, and never work around the interactive selector with `--all`, `-y`, or an equivalent bulk-install option.

Do not present Superpowers as a peer category to all third-party Skills. Internally it remains a managed upstream integration; in the standard user flow it is the install source for the `superpowers` workflow pack. Installing both workflow packs is an advanced path used only when the user explicitly requests it.

Understand Anything is a separate optional managed integration in the standard flow. Install it only into the target project's `.agent/runtime/` and `.agents/skills/`; never use its upstream global installer or write to user-level Skill/plugin directories.

## Updating a bootstrapped project

Bootstrap records a hash of every file it writes in the target's `.agent/bootstrap.yml`. `scripts/bootstrap.sh --target DIR --update` refreshes only files still matching those hashes and reports the ones it left alone. It replays the recorded selections, so it needs no other arguments, and it never re-runs an installer.

Never pass `--force` to resolve a reported conflict on your own: it discards the user's edits to that file. Show them the diff and let them decide.

## Repository layout

- `skills/`: independently distributable Skills.
- `integrations/`: metadata and compatibility policy for upstream projects we do not own.
- `policies/`: cross-agent project policy copied by bootstrap.
- `templates/`: project-root instruction files copied by bootstrap.
- `bootstrap-manifest.yml`: versioned component and workflow contract.
- `scripts/bootstrap.sh`: project initialization and `--update` entry point.
- `scripts/rehydrate.sh`: rebuilds the local artifacts a project keeps out of Git.
- `github/rulesets/`: versioned GitHub repository governance payloads.

## Rules

- Store each Skill under `skills/<kebab-case-name>/SKILL.md`.
- Keep managed integrations pinned to immutable known-good refs; do not fork or vendor upstream source without an explicit decision.
- Keep workflow frameworks opt-in and mutually exclusive according to `policies/workflow-selection.md`.
- Treat template `AGENTS.md` as cross-agent policy; template `CLAUDE.md` may contain only Claude-specific additions and must reference `AGENTS.md`.
- Write Skill instructions and code comments in English unless the Skill intentionally targets Chinese interaction; keep user documentation in Chinese.
- Put reusable domain material in `references/`; keep deterministic operations in idempotent `scripts/`.
- Preserve `third-party-sources.yml` compatibility and record source, commit, license, and local modifications before vendoring or forking a Skill.
- Verify relative references, shell syntax, and bootstrap behavior after every change.
- Keep remote GitHub configuration explicit, idempotent, and scoped to a verified `OWNER/REPOSITORY`; never infer a mutation target from a missing remote.
- Never commit credentials, conversation transcripts, assessment records, generated reports, or persistent user memory.
- Do not bundle, copy, patch, download, or automate installation of catalog entries marked `bundled: false`; `Visit upstream` is not redistribution authorization.
- Treat restrictive third-party licenses explicitly. Maintainers have accepted the MIT + Commons Clause sales restriction for bundled `skills/pre-mortem`; preserve its license, inventory metadata, and prominent notice.
- Never create commits without explicit user authorization.
