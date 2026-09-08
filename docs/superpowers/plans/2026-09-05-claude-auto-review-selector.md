# Claude Auto Review Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a schema-v5, `github-workflow`-only interactive bootstrap choice that records Claude Auto Review setup guidance and tells selected users to run the official `/install-github-app` command themselves.

**Architecture:** `scripts/bootstrap.sh` owns the selector, its explicit flags, safe update replay, and a one-time plain-text next-step message. The target manifest persists only `components.claude_auto_review: selected|skipped`; it never represents provider activation or GitHub configuration. Source-contract, policy, README, and behavioral tests make the boundary durable across bootstrap and `--update`.

**Tech Stack:** Bash, YAML, Markdown, existing shell-test suite, ShellCheck.

**Spec:** `docs/superpowers/specs/2026-09-05-claude-auto-review-selector-design.md`

## Global Constraints

- Change the bootstrap interaction only; do not install, invoke, embed, vendor, copy, patch, or automate `/install-github-app`, the Claude GitHub App, Claude Code Action, or any third-party upstream content.
- The selector is available only after `github-workflow` is selected; it is neither a workflow nor a provider configuration.
- Persist exactly `components.claude_auto_review: selected` or `components.claude_auto_review: skipped`; do not write `governance.reviewer: claude`.
- Use `--select-claude-auto-review` and `--skip-claude-auto-review` as the only noninteractive choices; they conflict with each other, are invalid outside `github-workflow`, and are invalid with `--update`.
- Upgrade source and emitted target manifests from schema v4 to v5. During `--update`, an old v4 manifest without the field migrates deterministically to `skipped` without printing or executing any Claude/GitHub action.
- Keep source code comments in English and user-facing documentation in Chinese.
- Do not modify `.github/workflows/`, `policies/workflow-selection.md`, `schemas/provider-config.schema.json`, `scripts/evaluate-ai-review-gate.sh`, `scripts/authorize-fixer-push.sh`, `scripts/configure-github.sh`, `scripts/rehydrate.sh`, `integrations/`, `catalog/`, or `tests/test-pins.sh`.
- Do not create a Git commit without separate, explicit user authorization.

---

## File Structure

- `scripts/bootstrap.sh` — the sole implementation of CLI flags, interactive selector, selection validation, update migration/replay, emitted manifest field, and post-bootstrap reminder.
- `tests/test-bootstrap.sh` — proves initial bootstrap selection behavior, bad invocations, and absence of remote/App/workflow/provider side effects.
- `tests/test-bootstrap-update.sh` — proves v4-to-v5 migration, v5 replay, invalid persisted-state failure, and update override rejection.
- `bootstrap-manifest.yml` and `.agent/bootstrap.yml` — define schema v5 source contract and a v5 consumer-state example.
- `AGENTS.md`, `templates/AGENTS.md`, and `README.md` — explain the interactive choice and forbid treating the selection as authorization for external actions.
- `tests/test-policy-text.sh` — locks the durable wording in source documents and bootstrap output.
- `scripts/configure-validation.sh` and `tests/test-governance-contracts.sh` — demonstrate that validation configuration accepts both target manifest v4 and v5; update only diagnostic text if the existing behavior is already version-agnostic.

### Task 1: Implement Initial Bootstrap Selection and Safety Boundary

**Files:**
- Modify: `scripts/bootstrap.sh:13-26, 33-65, 120-223, 226-307, 339-395, 503-610`
- Modify: `tests/test-bootstrap.sh:8-129`
- Test: `tests/test-bootstrap.sh`

**Interfaces:**
- Consumes: `--workflow github-workflow`, `--select-claude-auto-review`, and `--skip-claude-auto-review`.
- Produces: `.agent/bootstrap.yml` component state `claude_auto_review: selected|skipped` and, only for initial `selected`, the literal `/install-github-app` reminder.
- Does not produce: a provider configuration, GitHub App installation, credential, `origin`, `.github/workflows/` file, `gh` call, review gate, fixer, or merge configuration.

- [ ] **Step 1: Add failing initial-bootstrap behavior cases**

In `tests/test-bootstrap.sh`, change the first successful `github-workflow` invocation to include `--skip-claude-auto-review`, then add this complete block before the existing overwrite test:

```bash
mock_bin="${test_root}/mock-bin"
mkdir -p "${mock_bin}"
cat > "${mock_bin}/gh" <<'EOF'
#!/usr/bin/env bash
echo "bootstrap unexpectedly invoked gh" >&2
exit 99
EOF
chmod +x "${mock_bin}/gh"

selected_target="${test_root}/selected-auto-review"
selected_output="$(PATH="${mock_bin}:${PATH}" "${repo_root}/scripts/bootstrap.sh" \
  --target "${selected_target}" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything \
  --select-claude-auto-review)"
grep -q '^schema_version: 5$' "${selected_target}/.agent/bootstrap.yml"
grep -q '^  claude_auto_review: selected$' "${selected_target}/.agent/bootstrap.yml"
grep -q '/install-github-app' <<<"${selected_output}"
grep -q '^  reviewer: none$' "${selected_target}/.agent/bootstrap.yml"
test ! -e "${selected_target}/.github/workflows"
if git -C "${selected_target}" remote get-url origin >/dev/null 2>&1; then
  echo "Claude Auto Review selection unexpectedly created origin" >&2
  exit 1
fi

skipped_target="${test_root}/skipped-auto-review"
skipped_output="$("${repo_root}/scripts/bootstrap.sh" \
  --target "${skipped_target}" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything \
  --skip-claude-auto-review)"
grep -q '^  claude_auto_review: skipped$' "${skipped_target}/.agent/bootstrap.yml"
if grep -q '/install-github-app' <<<"${skipped_output}"; then
  echo "skipped Claude Auto Review unexpectedly printed setup guidance" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" \
  --target "${test_root}/conflicting-auto-review" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything \
  --select-claude-auto-review \
  --skip-claude-auto-review >/dev/null 2>&1; then
  echo "bootstrap unexpectedly accepted conflicting Claude Auto Review choices" >&2
  exit 1
fi

if "${repo_root}/scripts/bootstrap.sh" \
  --target "${test_root}/missing-auto-review" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything </dev/null >/dev/null 2>&1; then
  echo "non-interactive github-workflow bootstrap unexpectedly chose Claude Auto Review" >&2
  exit 1
fi

if AI_AGENT=codex "${repo_root}/scripts/bootstrap.sh" \
  --target "${test_root}/agent-missing-auto-review" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything >/dev/null 2>&1; then
  echo "Agent bootstrap unexpectedly chose Claude Auto Review" >&2
  exit 1
fi

for workflow in none superpowers; do
  if "${repo_root}/scripts/bootstrap.sh" \
    --target "${test_root}/inapplicable-${workflow}" \
    --workflow "${workflow}" \
    --skip-skills \
    --skip-understand-anything \
    --skip-superpowers \
    --select-claude-auto-review >/dev/null 2>&1; then
    echo "${workflow} unexpectedly accepted Claude Auto Review selection" >&2
    exit 1
  fi
done
```

Run:

```bash
bash tests/test-bootstrap.sh
```

Expected: FAIL because the flags do not exist, `schema_version` remains 4, and no `claude_auto_review` field is emitted.

- [ ] **Step 2: Add the selector state, help text, and paired flag parser**

In `scripts/bootstrap.sh`:

1. Add `claude_auto_review_mode=""` beside the existing selection variables.
2. Extend `usage()` with these exact entries after the Superpowers options:

```text
  --select-claude-auto-review
                        Record Claude Auto Review setup guidance for github-workflow
  --skip-claude-auto-review
                        Do not record Claude Auto Review setup guidance
```

3. Add these paired parser cases after the Superpowers parser cases and before `--init-git`:

```bash
    --select-claude-auto-review)
      [[ -z "${claude_auto_review_mode}" || "${claude_auto_review_mode}" == selected ]] || {
        echo "--select-claude-auto-review conflicts with --skip-claude-auto-review" >&2
        exit 2
      }
      claude_auto_review_mode="selected"
      shift
      ;;
    --skip-claude-auto-review)
      [[ -z "${claude_auto_review_mode}" || "${claude_auto_review_mode}" == skipped ]] || {
        echo "--skip-claude-auto-review conflicts with --select-claude-auto-review" >&2
        exit 2
      }
      claude_auto_review_mode="skipped"
      shift
      ;;
```

4. Capture `cli_claude_auto_review_mode` before update/default/prompt filling and initialize `record_claude_auto_review="skipped"` beside the other `record_*` values.

- [ ] **Step 3: Add applicability, Agent/non-TTY, and TTY selector logic**

After the workflow `case` validation and before the Superpowers selector:

1. Reject any nonempty `claude_auto_review_mode` unless `workflow` is exactly `github-workflow`:

```bash
if [[ "${workflow}" != github-workflow && -n "${claude_auto_review_mode}" ]]; then
  echo "Claude Auto Review guidance requires --workflow github-workflow" >&2
  exit 2
fi
```

2. Extend the existing Agent-process completeness condition so `workflow == github-workflow && -z claude_auto_review_mode` is rejected with the existing interactive-selector guard.
3. When the selector is applicable and the mode is empty, use this exact TTY/non-TTY behavior:

```bash
if [[ "${workflow}" == github-workflow && -z "${claude_auto_review_mode}" ]]; then
  if [[ -t 0 && -t 1 ]]; then
    read -r -p "Enable Claude Auto Review setup guidance? [y/N]: " claude_auto_review_choice
    case "${claude_auto_review_choice}" in
      y|Y|yes|YES) claude_auto_review_mode="selected" ;;
      *) claude_auto_review_mode="skipped" ;;
    esac
  else
    echo "Interactive Claude Auto Review choice is required for github-workflow." >&2
    echo "Guide the user to run this script in a terminal; do not choose on their behalf." >&2
    exit 2
  fi
fi
```

4. Keep `claude_auto_review_mode` empty for `none` and `superpowers`; never prompt for it in those workflows.

- [ ] **Step 4: Emit schema v5 state and the initial-only reminder**

Before manifest serialization, set the recorded state only for initial bootstrap:

```bash
if [[ "${update_mode}" == false ]]; then
  record_claude_auto_review="${claude_auto_review_mode:-skipped}"
fi
```

Change the emitted manifest header to `schema_version: 5`, then add this component line after `governance_observe`:

```yaml
  claude_auto_review: ${record_claude_auto_review}
```

After the existing `github-workflow is active but Curated Skills installation was skipped` notice, add:

```bash
if [[ "${update_mode}" == false && "${record_claude_auto_review}" == selected ]]; then
  echo "Claude Auto Review guidance was selected."
  echo "In a Claude Code session for this project, run /install-github-app to continue."
fi
```

Do not add any `gh`, `npx`, `claude`, provider, secret, or workflow call in this task.

- [ ] **Step 5: Run the focused behavior test**

Run:

```bash
bash tests/test-bootstrap.sh
```

Expected: PASS, including selected/skipped persistence, literal reminder output only for selected, inapplicable/ambiguous choice rejection, and no `gh` execution.

- [ ] **Step 6: Check the runtime scope**

Run:

```bash
git diff --name-only -- .github/workflows policies/workflow-selection.md schemas/provider-config.schema.json scripts/evaluate-ai-review-gate.sh scripts/authorize-fixer-push.sh scripts/configure-github.sh scripts/rehydrate.sh integrations catalog tests/test-pins.sh
```

Expected: no output.

- [ ] **Step 7: Do not commit without separate authorization**

Report the Task 1 diff and test result. Do not stage or commit files.

### Task 2: Add Update Replay, v4-to-v5 Migration, and Validation Compatibility

**Files:**
- Modify: `scripts/bootstrap.sh:226-291, 503-540`
- Modify: `scripts/configure-validation.sh:57-65`
- Modify: `tests/test-bootstrap-update.sh:14-116`
- Modify: `tests/test-governance-contracts.sh:106-120`
- Test: `tests/test-bootstrap-update.sh`, `tests/test-governance-contracts.sh`

**Interfaces:**
- Consumes: existing v4 manifest with no `components.claude_auto_review`, or v5 manifest with `selected|skipped`.
- Produces: schema v5 target manifest with a validated `components.claude_auto_review` state.
- Error interface: invalid recorded value and selector flags supplied with `--update` exit nonzero without performing an external action.

- [ ] **Step 1: Add failing update and compatibility cases**

In `tests/test-bootstrap-update.sh`, add this complete block after the existing selection replay assertions and before the guard-rails section:

```bash
# 7) Claude Auto Review selection is replayed without a reminder or selector.
selected_target="${test_root}/selected-auto-review"
"${templates}/scripts/bootstrap.sh" \
  --target "${selected_target}" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything \
  --select-claude-auto-review >/dev/null
grep -q '^schema_version: 5$' "${selected_target}/.agent/bootstrap.yml"
grep -q '^  claude_auto_review: selected$' "${selected_target}/.agent/bootstrap.yml"
update_output="$("${templates}/scripts/bootstrap.sh" --target "${selected_target}" --update)"
grep -q '^  claude_auto_review: selected$' "${selected_target}/.agent/bootstrap.yml"
if grep -q '/install-github-app' <<<"${update_output}"; then
  echo "--update unexpectedly repeated Claude Auto Review guidance" >&2
  exit 1
fi

if "${templates}/scripts/bootstrap.sh" \
  --target "${selected_target}" \
  --update \
  --skip-claude-auto-review >/dev/null 2>&1; then
  echo "--update unexpectedly accepted a Claude Auto Review override" >&2
  exit 1
fi

# 8) v4 manifests migrate to v5 with the safe skipped default.
v4_target="${test_root}/v4-auto-review"
"${templates}/scripts/bootstrap.sh" \
  --target "${v4_target}" \
  --workflow github-workflow \
  --skip-skills \
  --skip-understand-anything \
  --skip-claude-auto-review >/dev/null
sed -i.bak \
  -e 's/^schema_version: 5$/schema_version: 4/' \
  -e '/^  claude_auto_review: /d' \
  "${v4_target}/.agent/bootstrap.yml"
rm -f "${v4_target}/.agent/bootstrap.yml.bak"
v4_update_output="$("${templates}/scripts/bootstrap.sh" --target "${v4_target}" --update)"
grep -q '^schema_version: 5$' "${v4_target}/.agent/bootstrap.yml"
grep -q '^  claude_auto_review: skipped$' "${v4_target}/.agent/bootstrap.yml"
if grep -q '/install-github-app' <<<"${v4_update_output}"; then
  echo "v4 migration unexpectedly printed Claude Auto Review guidance" >&2
  exit 1
fi

# 9) Invalid persisted state fails closed.
sed -i.bak 's/^  claude_auto_review: skipped$/  claude_auto_review: enabled/' "${v4_target}/.agent/bootstrap.yml"
rm -f "${v4_target}/.agent/bootstrap.yml.bak"
if "${templates}/scripts/bootstrap.sh" --target "${v4_target}" --update >/dev/null 2>&1; then
  echo "--update unexpectedly accepted an invalid Claude Auto Review state" >&2
  exit 1
fi
```

Also add `--skip-claude-auto-review` to every noninteractive initial bootstrap using `--workflow github-workflow` in this test.

Run:

```bash
bash tests/test-bootstrap-update.sh
```

Expected: FAIL because update does not yet parse/replay/migrate `claude_auto_review`, schema v5 is incomplete, and update flags are still accepted.

- [ ] **Step 2: Parse and validate recorded state during `--update`**

In `scripts/bootstrap.sh`'s update branch:

1. Before defaulting record values, read the uniquely named component field:

```bash
recorded_claude_auto_review="$(recorded_selection "${existing_manifest}" '^  claude_auto_review:')"
```

2. Treat missing values as the v4 migration default:

```bash
if [[ -z "${recorded_claude_auto_review}" ]]; then
  record_claude_auto_review="skipped"
else
  record_claude_auto_review="${recorded_claude_auto_review}"
fi
```

3. Validate replayed state exactly:

```bash
case "${record_claude_auto_review}" in
  selected|skipped) ;;
  *)
    echo "Invalid recorded Claude Auto Review state '${record_claude_auto_review}' in ${existing_manifest}" >&2
    exit 1
    ;;
esac
```

4. Before applying replayed defaults, reject any nonempty `cli_claude_auto_review_mode` when `update_mode` is true:

```bash
if [[ "${update_mode}" == true && -n "${cli_claude_auto_review_mode}" ]]; then
  echo "--select-claude-auto-review and --skip-claude-auto-review cannot be used with --update" >&2
  exit 2
fi
```

5. Set `claude_auto_review_mode="${record_claude_auto_review}"` after workflow replay so the existing applicability guard treats a recorded `github-workflow` selection as complete without prompting.

Ensure `--update` never reaches the initial-only reminder block from Task 1.

- [ ] **Step 3: Make validation-config diagnostics version-neutral and prove v5 works**

`configure-validation.sh` already tests required governance fields rather than matching an exact `schema_version`. Preserve that compatible behavior, but replace its stale diagnostic text:

```bash
echo "Bootstrap configuration predates the required governance fields; run bootstrap --update before configuring validation" >&2
```

In `tests/test-governance-contracts.sh`, after the successful `configure-validation.sh` invocation for `pending_project`, assert:

```bash
grep -q '^schema_version: 5$' "${pending_project}/.agent/bootstrap.yml"
```

This proves the existing field-based validator accepts a v5 target manifest without adding an unnecessary schema-version branch.

- [ ] **Step 4: Run focused update and validation tests**

Run:

```bash
bash tests/test-bootstrap-update.sh
```

Expected: PASS.

Run:

```bash
bash tests/test-governance-contracts.sh
```

Expected: PASS.

- [ ] **Step 5: Do not commit without separate authorization**

Report the Task 2 diff and test results. Do not stage or commit files.

### Task 3: Publish the Source Contract and Durable User Guidance

**Files:**
- Modify: `bootstrap-manifest.yml:1, 125-139`
- Modify: `.agent/bootstrap.yml:1-20`
- Modify: `AGENTS.md:18-49`
- Modify: `templates/AGENTS.md:19-29`
- Modify: `README.md:37-86`
- Modify: `tests/test-policy-text.sh:13-35`
- Modify: `tests/test-create-github.sh:44-51`
- Test: `tests/test-policy-text.sh`, `tests/test-bootstrap.sh`, `tests/test-create-github.sh`

**Interfaces:**
- Consumes: the persisted `components.claude_auto_review` state produced by Tasks 1 and 2.
- Produces: source and target documentation that accurately describes `selected` as reminder-only and directs only selected users to manually run `/install-github-app` in a Claude Code session.

- [ ] **Step 1: Add failing source-contract assertions**

In `tests/test-policy-text.sh`, add these assertions before its final success message:

```bash
grep -q '^schema_version: 5$' "${repo_root}/bootstrap-manifest.yml"
grep -q '^  claude_auto_review:$' "${repo_root}/bootstrap-manifest.yml"
grep -q 'eligible_workflow: github-workflow' "${repo_root}/bootstrap-manifest.yml"
grep -q 'post_bootstrap_command: /install-github-app' "${repo_root}/bootstrap-manifest.yml"
grep -q 'does not configure GitHub App, authentication, secrets, remotes, providers, or workflows' "${repo_root}/bootstrap-manifest.yml"
grep -q 'does not authorize an Agent to run `\/install-github-app`' "${repo_root}/AGENTS.md"
grep -q 'does not authorize GitHub App installation, authentication, secret configuration, remote mutation, or running /install-github-app' "${repo_root}/templates/AGENTS.md"
grep -q '/install-github-app' "${repo_root}/README.md"
grep -q 'Claude Auto Review guidance was selected' "${repo_root}/scripts/bootstrap.sh"
```

Run:

```bash
bash tests/test-policy-text.sh
```

Expected: FAIL because no source contract or durable wording exists yet.

- [ ] **Step 2: Update schema examples and the source manifest contract**

Change the first line of `bootstrap-manifest.yml` to:

```yaml
schema_version: 5
```

Under the existing `github:` mapping, after the `rulesets:` block, add this exact declarative entry and English comment:

```yaml
  # This records only a user's request for a post-bootstrap instruction. It does not configure GitHub App, authentication, secrets, remotes, providers, or workflows.
  claude_auto_review:
    opt_in: true
    eligible_workflow: github-workflow
    selection: prompt
    post_bootstrap_command: /install-github-app
    action: instruction_only
    external_configuration: user_runs_official_claude_code_installer
```

Change the root `.agent/bootstrap.yml` example to `schema_version: 5` and add:

```yaml
  claude_auto_review: skipped
```

after its existing `governance_observe` component line.

- [ ] **Step 3: Update agent policy and user documentation with the exact boundary**

In the root `AGENTS.md` bootstrap section, extend the standard-flow explanation after the workflow selection sentence with this English policy text:

```markdown
Only when the user selects `github-workflow` should the command offer the optional Claude Auto Review setup guidance selector. A selected value only records that the user wants the follow-up instruction; it does not authorize an Agent to run `/install-github-app`, install a GitHub App, configure authentication or secrets, create a remote, or mutate GitHub configuration.
```

In `templates/AGENTS.md`, add this durable rule under `## Project-specific instructions`:

```markdown
- `components.claude_auto_review: selected` is a reminder only. It does not authorize GitHub App installation, authentication, secret configuration, remote mutation, or running `/install-github-app`; the user must run the official Claude Code installer themselves.
```

In `README.md`:

1. Change the standard-flow numbered list to include this new fourth item immediately after workflow selection:

```markdown
4. 仅当选择 `github-workflow` 时，选择是否记录 Claude Auto Review 的官方安装引导；选择后，用户必须在该项目的 Claude Code session 中亲自运行 `/install-github-app`。
```

2. Renumber the existing Superpowers item from `4.` to `5.`.
3. Add this paragraph after the list:

```markdown
Claude Auto Review 的选择只记录后续引导，不安装 GitHub App、Claude Code Action、认证或 secret，也不创建 workflow、启用 AI gate、Auto Fixer 或 Auto Merge。
```

4. Extend the existing noninteractive example to include `--skip-claude-auto-review`, and add a Chinese sentence stating that a noninteractive `github-workflow` bootstrap must use one of the two explicit Claude Auto Review flags.

- [ ] **Step 4: Update remaining initial github-workflow test callers**

Add `--skip-claude-auto-review` to each noninteractive initial bootstrap call using `--workflow github-workflow` outside `tests/test-bootstrap.sh` and `tests/test-bootstrap-update.sh`:

- `tests/test-create-github.sh`

Confirm this command identifies no additional callers that lack an explicit choice:

```bash
rg -l -- '--workflow github-workflow' tests | sort
```

Expected output: only `tests/test-bootstrap.sh`, `tests/test-bootstrap-update.sh`, and `tests/test-create-github.sh`; every invocation in those files now either selects or skips Claude Auto Review.

- [ ] **Step 5: Run focused contract and initial-bootstrap tests**

Run:

```bash
bash tests/test-policy-text.sh
```

Expected: PASS.

Run:

```bash
bash tests/test-bootstrap.sh
```

Expected: PASS.

- [ ] **Step 6: Run the full repository verification baseline**

Run:

```bash
shellcheck -S style scripts/*.sh tests/*.sh
```

Expected: exit code `0`.

Run:

```bash
bash -n scripts/*.sh tests/*.sh
```

Expected: exit code `0`.

Run:

```bash
./scripts/check-third-party-inventory.sh
```

Expected output: `third-party inventory consistency passed`.

Run:

```bash
for test_file in tests/test-*.sh; do bash "${test_file}"; done
```

Expected: every test script exits `0`.

- [ ] **Step 7: Confirm scope, inspect the final diff, and wait for commit authorization**

Run:

```bash
git diff --check
```

Expected: no output.

Run:

```bash
git diff --name-only -- .github/workflows policies/workflow-selection.md schemas/provider-config.schema.json scripts/evaluate-ai-review-gate.sh scripts/authorize-fixer-push.sh scripts/configure-github.sh scripts/rehydrate.sh integrations catalog tests/test-pins.sh
```

Expected: no output.

Run:

```bash
git diff -- bootstrap-manifest.yml scripts/bootstrap.sh .agent/bootstrap.yml scripts/configure-validation.sh AGENTS.md templates/AGENTS.md README.md tests/test-bootstrap.sh tests/test-bootstrap-update.sh tests/test-governance-contracts.sh tests/test-policy-text.sh tests/test-create-github.sh
```

Report the reviewed diff and all verification results. Do not stage, commit, push, configure GitHub, or run `/install-github-app` without new explicit authorization.

## Plan Self-Review

### Spec coverage

- Explicit selector, paired flags, applicability, Agent/non-TTY fail-closed behavior, selected/skipped state, and initial-only reminder are implemented and tested in Task 1.
- Replay, invalid-state failure, v4-to-v5 safe migration, update override rejection, and schema-v5 validation compatibility are implemented and tested in Task 2.
- The source manifest, root consumer example, root and target policy, Chinese README, all remaining test callers, and full verification are covered in Task 3.
- Every explicitly excluded external integration and governance capability is named in Global Constraints and protected by the Task 1 side-effect test and Task 3 scope check.

### Placeholder scan

The plan contains exact file paths, flag names, persisted states, output strings, error behavior, YAML fields, test code, and verification commands. It has no deferred or unspecified implementation items.

### Consistency check

The only persisted values are `selected` and `skipped`; the only CLI flags are `--select-claude-auto-review` and `--skip-claude-auto-review`; the only official follow-up string is `/install-github-app`; and schema v5 is used consistently by source and emitted manifests.
