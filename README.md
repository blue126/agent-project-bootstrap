# Agent Project Bootstrap

**English** | [简体中文](README.zh-CN.md)

**Set up an agent coding environment that is ready to start work.**

Choose your agent clients, workflow, and Skills; establish project policies and local Git; then start your first task in your selected client. Works with both new and existing projects. Existing configuration is preserved, changes are explained before they happen, and **nothing is committed or pushed automatically**. GitHub, CI, and automated review are optional next steps—not prerequisites for working locally.

**First time here? Follow the full quick start below.** If you only want a few skills rather than project initialization, see [Skills-only installation](#only-want-to-install-skills).

## Quick start: initialize a project

Use a regular terminal on macOS or Linux. The basic wizard requires **Bash, Git, jq, and Python 3.9+**. Installing Skills or workflow components also requires the appropriate Node.js/npm/npx environment. An authenticated `gh` is needed only for the optional GitHub continuation. Missing dependencies are reported; the toolkit does not automatically install them into your global environment.

Run the commands yourself in Terminal.app, iTerm, or another regular terminal. Do not have an agent launch real interactive installers in a tool-owned PTY, or clear detection variables such as `AI_AGENT`, `CLAUDECODE`, or `CODEX_*` to bypass the guard.

### 1. Get the bootstrap toolkit

This example places the **toolkit repository** in your home directory. It only downloads the toolkit; it does not initialize your project:

```bash
git clone https://github.com/blue126/agent-project-bootstrap.git "$HOME/agent-project-bootstrap"
```

If that directory already exists, first check whether it is your existing toolkit checkout. Reuse it rather than overwriting or deleting it. If the toolkit is stored elsewhere, substitute its actual script path in the commands below.

### 2. Enter your own project directory

For a **new project**, create an empty directory. `my-agent-project` is an example name; replace it as needed. If the directory already exists, treat it as an existing project—do not empty it:

```bash
mkdir "$HOME/my-agent-project"
```

```bash
cd "$HOME/my-agent-project"
```

For an **existing project**, do not create another directory. Enter its project root instead, replacing the path below with your actual project path:

```bash
cd "/path/to/your/project"
```

> **The toolkit directory and your project directory are different.** Do not start project initialization inside the `agent-project-bootstrap` checkout just because you downloaded it there. Enter the project you intend to develop. For an existing Git project, use its Git root rather than a subdirectory.

### 3. Start the wizard in the current project

```bash
"$HOME/agent-project-bootstrap/scripts/bootstrap.sh"
```

**No directory argument is needed: the target defaults to the current working directory.** The opening screen displays the actual target path; check it before starting. Invoking the script from the toolkit does not change your working directory back to the toolkit checkout.

The wizard requires a human-operated interactive terminal. Use arrow keys, Space, and Enter for client selection; `q` cancels. The native Skills installer retains its search, multiselect, scope, and copy/symlink choices. Project-level `Project` scope is recommended. Do not use `--all`, `-y`, or `-g` to skip these decisions on the user's behalf.

### 4. Start working after setup

The summary shows your clients, workflow, actual Skill entries, project policies, and Git state, together with guidance for your first task.

Open the project in a **new session of your selected client**. Confirm that the agent has read the project policies and discovered the Skills before authorizing development. Installed files do not prove that the client has loaded them. Uncommitted assets are explicitly reported as local-only; the first commit still requires file-scope and sensitive-information review.

If you do not need GitHub, finish at the final prompt. To add clients, Skills, or collaboration capabilities later, rerun the same command from the project directory. Existing state is reinspected; the wizard does not resume a hidden “last completed question.”

## What the wizard does

| Stage | Your decision | What the project receives |
|---|---|---|
| 1. Agent clients | Claude Code, Codex, OpenCode, or Universal; multiple selections allowed | Explicit project installation targets; saved choices are preselected, not automatically confirmed |
| 2. Workflow | Keep your existing approach, or explicitly adopt github-workflow, Superpowers, or BMAD | A selected working method; detection or installation does not execute tasks |
| 3. Skills and optional tools | Install workflow components, add ordinary Skills, optionally install Understand Anything | Project entries discoverable by the selected clients; existing Skills do not prevent additions |
| 4. Project policies and local Git | Confirm configuration, ignore-rule changes, and local Git initialization | Shared agent policies, Git asset rules, and a local repository; no automatic commits or pushes |
| 5. Local summary | Check readiness and pending items; decide whether to continue with GitHub | First-task guidance; CI setup is not required to finish the basic flow |

At the opening prompt, `i` displays the full **Checks / Possible changes / Will not do** explanation. Reading this page does not launch installers or write project files. `NO_COLOR`, narrow terminals, and `TERM=dumb` have readable fallbacks, but do not turn an agent-owned process into a human terminal. The wizard currently displays Chinese guidance; changing the README language does not change the terminal UI language.

- **Client selection appears on every run.** Subsequent Skills calls reuse your selected `--agent` targets. Native scope, installation-method, and confirmation prompts may still appear for each installation. `skills@1.5.23 add` has no `--project` flag; do not hide prompts using `-y` or `--all`. Selecting Global does not establish project-local readiness.
- **Adopt one workflow.** `github-workflow` covers Git branches, review, and later GitHub collaboration; Superpowers covers feature design, implementation, and validation; BMAD covers requirements, architecture, and structured iteration. Keeping your existing approach does not disable unknown rules or require classifying an unknown framework.
- **Understand Anything is optional.** Existing codebases (brownfield) usually benefit more; empty projects (greenfield) can wait until there is code to analyze. It installs a pinned runtime and project links, not global plugins. It does not automatically analyze code; later analysis may incur model costs.
- **Local setup comes before collaboration.** GitHub is offered only after the local summary. Declining ends the flow without a CI/review/ruleset questionnaire. Even an existing GitHub origin is not contacted through `gh` before that opt-in.

Client paths and compatibility:

| Client or mode | Project Skill path | Notes |
|---|---|---|
| Claude Code | `.claude/skills/` | `CLAUDE.md` references the shared `AGENTS.md` |
| Codex | `.agents/skills/` | Uses the shared project Skill directory |
| OpenCode | `.agents/skills/` | BMAD also requires `.opencode/commands` pointers |
| Universal | `.agents/skills/` | Shared-directory mode, not a client application or “install all”; BMAD 6.12.0 does not support this tool ID |

See the [onboarding guide (Chinese)](examples/onboarding.md) for more interaction details and existing-project guidance.

## Only want to install Skills?

**This is a separate Skills-only entry point. It does not establish the complete project policies or Git environment.** To bootstrap a project, use the [quick start](#quick-start-initialize-a-project) instead.

Enter the project where you want to install Skills, then run:

```bash
npx skills add https://github.com/blue126/agent-project-bootstrap
```

You do not need to clone the toolkit first. The native installer handles Skill, client, scope, and installation-method choices; it may omit questions that do not apply to the detected environment. Completing Skill installation is not the same as completing project initialization.

<details>
<summary>Maintainers: install, list, or link Skills from a local checkout</summary>

These examples assume the toolkit was downloaded to your home directory as in the quick start. Run installation from the target project:

```bash
npx skills@1.5.23 add "$HOME/agent-project-bootstrap"
```

```bash
npx skills@1.5.23 add "$HOME/agent-project-bootstrap" --list
```

Use the following tool only when user-level links are explicitly wanted. It is not the default project bootstrap path:

```bash
"$HOME/agent-project-bootstrap/scripts/link-skills.sh"
```

```bash
"$HOME/agent-project-bootstrap/scripts/link-skills.sh" --agent claude
```

</details>

## Updating and restoring

### Update a bootstrapped project

First enter the target project directory. Refresh only managed files you have not modified:

```bash
"$HOME/agent-project-bootstrap/scripts/bootstrap.sh" --update
```

Bootstrap records managed-file hashes in the project's `.agent/bootstrap.yml`. Modified files are preserved and listed, as are client preferences, existing selections, and unknown metadata. `--update` does not rerun installers, start the wizard, or authorize Git or remote operations. If you need to replace your own edits, inspect the diff and explicitly decide whether to use `--force`; even that flag does not silently open a legacy Skills ignore boundary.

### Restore local artifacts on a new machine

Project-owned or customized Skills should be reviewed and committed. Third-party content may be committed where licensing permits, or reproduced through a pinned, verifiable process. Not every installed Skill is a disposable local artifact.

After obtaining the toolkit, cloning your project, and entering its directory:

```bash
"$HOME/agent-project-bootstrap/scripts/rehydrate.sh"
```

The tool uses recorded configuration to rebuild supported Understand Anything runtimes and client entries, prints Skills/Superpowers commands you must run in a regular terminal, and lists manual BMAD or other pending work honestly. Installation facts, version provenance, and new-session loading cannot be inferred from a single installation record.

## Version-control policies for downstream projects

`policies/git.md` is distributed as `.agent/policies/git.md` in the target project. The project's `AGENTS.md` requires agents to read it before initialization, staging, committing, changing ignore rules, or cleanup; no additional Skill is needed.

- **Put project capabilities in Git:** shared configuration, Skills, agents, commands, hooks, workflows, dependency lockfiles, and formal requirements, designs, research, or sanitized validation records. Review sensitive content, portability, and licensing before committing; review shared automation as code.
- **Keep personal state local:** credentials, personal overrides, sessions, caches, and nested worktrees. Runtime directories use local ignore rules; links confirmed to be reproducible receive exact-path exclusion proposals.
- **Preserve existing rules:** generate a minimal root `.gitignore` if it is absent, or append only confirmed changes to an existing file. Report overly broad rules that hide assets rather than deleting rules or untracking files automatically. `.gitignore` is not a secret scanner.
- **Migrate legacy Skills boundaries separately:** `--update`, including `--force`, preserves differing existing Skills ignore files. The wizard separately shows the legacy whole-directory-ignore migration and affected candidates, then requests confirmation. Custom rules are not migrated automatically.
- **Keep acceptance stages separate:** policy installation, rule application, client loading, first-commit validation, and remote publication are different states. See the complete [Git policy](policies/git.md).

<details>
<summary>Advanced: preview or apply ignore rules separately</summary>

```bash
python3 "$HOME/agent-project-bootstrap/scripts/configure-git-ignore.py" --project "$PWD"
```

After reviewing the exact diff, replace `TOKEN` with the reported snapshot token to apply it. Stale snapshots are rejected:

```bash
python3 "$HOME/agent-project-bootstrap/scripts/configure-git-ignore.py" --project "$PWD" --apply --expect TOKEN
```

Legacy Skills migration requires `--migrate-skills` in both the preview and application commands. This helper's required `--project` differs from the main wizard's optional `--target`.

</details>

## Optional GitHub collaboration

After the local summary, you can create or connect a GitHub repository, then prepare local validation, CI, automated review, and merge protection as needed. Missing remote branches or real evidence remain pending/blocked; a placeholder “success” cannot substitute for tests.

Claude Auto Review requires the user to run the official `/install-github-app` in the project's Claude Code session. Selecting guidance does not authorize an agent to install the App, configure authentication or secrets, enable auto-merge, or approve code. Governance-sensitive changes require human handling.

If review results already exist, enter an explicit PR number to verify bot feedback on its current revision. Successful verification continues to protection setup instead of repeatedly handing off installation. This verifies feedback availability only—not merge approval or the identity of a particular Claude App. Without a PR, you can view installation guidance or skip verification for now.

A structured handoff is created under `.agent/runtime/onboarding/` only when the user explicitly asks a project agent to help prepare validation. It is a task file, not resume state or execution authorization. After external work, rerun the main entry point to continue based on actual evidence.

### Create a GitHub repository

The default wizard creates or connects repositories without publishing code. When calling the underlying tools separately, specify both the project and repository:

```bash
"$HOME/agent-project-bootstrap/scripts/create-github.sh" --source "$PWD" --repo owner/repository --visibility private --create-only
```

```bash
"$HOME/agent-project-bootstrap/scripts/create-github.sh" --source "$PWD" --repo owner/existing-repository --attach-only
```

Neither mode stages, commits, pushes, or replaces a conflicting `origin`. Confirm the repository name, creation visibility, and operation explicitly. Publishing code later still requires separate authorization.

### Configure GitHub main protection

Once the remote project and branch exist, and this remote change has been authorized:

```bash
"$HOME/agent-project-bootstrap/scripts/configure-github.sh" --repo owner/repository
```

This idempotently configures the baseline Protect main ruleset: pull requests, resolved review threads, and squash merges, without requiring a positive approval count. Project CI gates use the downstream project's own evidence; this repository's self profile is not the downstream default. Governance starts with `validation: pending` and `auto_merge: disabled`; auto-merge is not enabled by default.

<details>
<summary>Advanced: explicit options, other target directories, and legacy publication</summary>

**Use the main entry point's `--target` only when operating on a project outside your current directory:**

```bash
"$HOME/agent-project-bootstrap/scripts/bootstrap.sh" --target "/path/to/another/project"
```

Use the bounded explicit-options entry point only when the user has already specified all choices. Agents should not request a configuration string just to bypass interaction:

```bash
"$HOME/agent-project-bootstrap/scripts/bootstrap.sh" --workflow github-workflow --skip-skills --skip-understand-anything --skip-claude-auto-review
```

`--install-skills` and `--install-superpowers` require a real interactive terminal. Superpowers installation verifies the pinned tag against its known-good commit first. When configuring a project adapter, use the project's own validation entry point. The public runtime bundles no technology-stack adapters and does not accept verbal claims as evidence:

```bash
"$HOME/agent-project-bootstrap/scripts/configure-validation.sh" --project "$PWD" --manifest .agent/validation/adapter.json --mode shadow
```

**Legacy publication creates a commit and uploads code; it is not the basic wizard.** Use it only after the user explicitly authorizes these actions, reviews the file scope, and completes pre-publication checks:

```bash
"$HOME/agent-project-bootstrap/scripts/bootstrap.sh" --workflow github-workflow --skip-skills --skip-understand-anything --skip-claude-auto-review --create-github --github-repo owner/repository --github-visibility private
```

It automatically stages only the bootstrap skeleton, including a reviewed root `.gitignore`, and rejects unrelated unreviewed changes or pre-existing staged content. A temporary index is used to check the candidate tree before publication. Unsafe links, nested repositories, current files over 10 MiB, and invalid JSON/YAML/TOML/Shell syntax are rejected. YAML checks require PyYAML; TOML requires Python 3.11+. Local Gitleaks 8.19+ must scan the candidate content and existing main history. A missing scanner, shallow history, or failed scan stops publication without automatically installing dependencies.

Project ignore/allow comments cannot silently narrow that scan. Projects with active hooks must use their normal publication workflow; hooks are not bypassed to publish. Failed checks leave the real index unchanged. Passing checks does not prove the absence of secrets or replace application-schema and functional validation.

</details>

## Project structure and maintenance

- `AGENTS.md` is the shared policy entry point; when Claude is selected, `CLAUDE.md` references it.
- `.agent/policies/` contains downstream project policies. `.agent/bootstrap.yml` records explicit preferences, managed-file hashes, and verifiable installation information—not wizard progress or authorization.
- Understand Anything uses a project runtime pinned to `v2.9.0` and an immutable ref, plus compatibility patches. Superpowers uses managed `v6.3.0` and an immutable ref. BMAD installation is separate from workflow execution.
- Other third-party provenance, licensing, and customization are recorded in `third-party-sources.yml`; managed integrations live in `integrations/`. `human-3-development-assessor` has no upstream license and is listed as `Visit upstream` only: it is not bundled, copied, patched, automatically downloaded, or installed with one click.

This repository distributes toolkit source; it does not mean components are installed or active in this checkout. Original project code is MIT-licensed; bundled third-party content retains its original licenses—see [third-party notices](THIRD_PARTY_NOTICES.md). See the [contribution guide (Chinese)](CONTRIBUTING.md) for maintenance, testing, and packaging. Do not commit credentials, personal state, or private transcripts. Preserve formal project reports after review, sanitization, and license checks.
