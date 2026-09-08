# Verification Documentation Calibration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `CONTRIBUTING.md` the sole authoritative explanation of local checks, CI verification, and release-preparation packaging, while directing README readers to it.

**Architecture:** This is a documentation-only change. `CONTRIBUTING.md` owns the complete Chinese maintenance-verification guidance; `README.md` contains only a concise link to that section. Existing CI and Shell scripts remain unchanged, so behavior is preserved while the documented purpose and timing of existing commands become clear.

**Tech Stack:** Markdown, Bash verification commands, existing GitHub Actions CI.

**Spec:** `docs/superpowers/specs/2026-09-05-verification-documentation-design.md`

## Global Constraints

- Change only `README.md` and `CONTRIBUTING.md`; do not create verification wrapper scripts, a Makefile, new workflows, or new repository tests.
- Do not modify `.github/workflows/ci.yml`, `scripts/`, release metadata, rulesets, versions, GitHub configuration, consumer governance state, or `dist/` behavior.
- Keep user-facing repository documentation in Chinese.
- Preserve CI as independent evidence for the exact pushed PR commit; do not claim local checks replace CI.
- Describe `./scripts/package-skills.sh` exclusively as a release-preparation operation that creates ignored `dist/*.zip` artifacts and does not publish, upload, or version anything.
- Do not create a Git commit without separate, explicit user authorization, as required by `AGENTS.md`.

---

## File Structure

- Modify `CONTRIBUTING.md`: Become the canonical maintenance-verification document. It will distinguish scoped local feedback, CI’s independent verification role, and release-preparation packaging.
- Modify `README.md`: Replace its duplicated maintenance command block with a concise link to `CONTRIBUTING.md#验证`.
- Do not create test files: the approved specification intentionally avoids testing documentation via brittle repository tests. Use explicit one-off documentation assertions plus the existing repository verification suite.

### Task 1: Establish Canonical Verification Documentation

**Files:**
- Modify: `CONTRIBUTING.md:13-22`
- Modify: `README.md:144-151`
- Test: one-off documentation-contract command in this task; existing `tests/test-*.sh`

**Interfaces:**
- Consumes: `docs/superpowers/specs/2026-09-05-verification-documentation-design.md`; the unchanged CI contract in `.github/workflows/ci.yml`; existing commands in `scripts/check-third-party-inventory.sh` and `scripts/package-skills.sh`.
- Produces: a single canonical Markdown section at `CONTRIBUTING.md#验证`, linked by `README.md`, that tells maintainers which existing checks to run in which situation.

- [ ] **Step 1: Run the failing documentation-contract check before editing**

Run:

```bash
bash -c 'set -euo pipefail; ! rg -q "shellcheck -S style scripts/\\*\\.sh tests/\\*\\.sh" README.md; rg -q "jq empty github/rulesets/protect-main.json" CONTRIBUTING.md; rg -q "准备发布分发物" CONTRIBUTING.md'
```

Expected: FAIL. The current README still contains the complete ShellCheck command block, while the current contribution guide does not yet document ruleset JSON validation or a separate release-preparation packaging phase.

- [ ] **Step 2: Replace the `## 验证` section in `CONTRIBUTING.md` with the canonical guidance**

Replace the current verification section through the paragraph immediately before the end of the file with exactly this Markdown:

````markdown
## 验证

本地检查用于尽早获得反馈，应按改动范围选择；它们不能替代 CI。修改 Shell 脚本时优先运行静态检查和语法检查，修改特定功能时优先运行对应测试；准备提交 PR 或需要完整本地确认时，再运行全部仓库测试。

```bash
shellcheck -S style scripts/*.sh tests/*.sh
```

```bash
bash -n scripts/*.sh tests/*.sh
```

修改 `github/rulesets/protect-main.json` 后，运行：

```bash
jq empty github/rulesets/protect-main.json
```

准备提交 PR 或需要完整本地确认时，运行：

```bash
for test_file in tests/test-*.sh; do bash "${test_file}"; done
```

无论本地运行了哪些检查，CI 都会在干净的 Ubuntu 和 macOS 环境中验证推送到 PR 的实际提交。CI 提供评审和合并所需的独立、可重跑证据。

### 准备发布分发物

准备发布 Skills 分发物时，在完成相关本地检查后运行：

```bash
./scripts/package-skills.sh
```

该命令生成被 Git 忽略的 `dist/*.zip`；它不会上传产物、创建发布或修改版本号。普通 PR、文档修改和日常治理脚本修改不需要为了打包而重复执行此命令。

Pull request 应说明行为变化、风险、验证结果和未执行的检查。治理敏感路径不能由自动 fixer 修改或自动合并。
````

Do not alter the existing `## 开发原则` section.

- [ ] **Step 3: Replace the README maintenance command block with a concise canonical-document link**

Replace the current `## 维护与验证` section, including its four-command code block, with exactly:

```markdown
## 维护与验证

贡献或维护此仓库时，请参阅[贡献指南的“验证”章节](CONTRIBUTING.md#验证)，按改动范围选择本地检查，了解 CI 对推送提交的独立验证，并在准备发布分发物时执行打包步骤。

不要提交个人数据、对话转录、生成报告、凭据、`.env`、证书或私钥。
```

- [ ] **Step 4: Run the documentation-contract check after editing**

Run:

```bash
bash -c 'set -euo pipefail; ! rg -q "shellcheck -S style scripts/\\*\\.sh tests/\\*\\.sh" README.md; rg -q "CONTRIBUTING.md#验证" README.md; rg -q "jq empty github/rulesets/protect-main.json" CONTRIBUTING.md; rg -q "CI 都会在干净的 Ubuntu 和 macOS 环境中验证推送到 PR 的实际提交" CONTRIBUTING.md; rg -q "### 准备发布分发物" CONTRIBUTING.md; rg -q "./scripts/package-skills.sh" CONTRIBUTING.md; rg -q "不会上传产物、创建发布或修改版本号" CONTRIBUTING.md'
```

Expected: PASS. README no longer owns the complete command list; it links to the canonical section, and the contribution guide describes local checks, CI, and release packaging separately.

- [ ] **Step 5: Check scope and documentation quality before running repository verification**

Run:

```bash
git diff --check
```

Expected: exit code `0` with no whitespace errors.

Run:

```bash
git diff --name-only -- .github/workflows/ci.yml scripts releases github/rulesets
```

Expected: no output, proving this task did not alter CI, scripts, release metadata, or rulesets.

Manually open the Markdown preview or source for both changed files and confirm that the README link resolves to the `验证` heading in `CONTRIBUTING.md`.

- [ ] **Step 6: Run the unchanged repository verification baseline**

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

- [ ] **Step 7: Report changes and wait for explicit commit authorization**

Run:

```bash
git diff -- README.md CONTRIBUTING.md
```

Report the documentation-only diff and verification results. Do not run `git add` or `git commit` unless the user separately and explicitly authorizes a commit.

## Plan Self-Review

### Spec coverage

- The plan makes `CONTRIBUTING.md` the only full command reference: Task 1, Steps 2 and 3.
- It separates scoped local feedback, independent CI verification, and release-preparation packaging: Task 1, Step 2.
- It preserves CI, scripts, release behavior, rulesets, and consumer governance: Global Constraints and Task 1, Step 5.
- It verifies the unchanged repository baseline after documentation changes: Task 1, Step 6.
- It does not add a wrapper script, Makefile, workflow, or test: Global Constraints and File Structure.

### Placeholder scan

No `TODO`, `TBD`, deferred implementation language, unspecified file paths, or undefined command interfaces appear in this plan.

### Consistency check

Every reference uses the same canonical anchor, `CONTRIBUTING.md#验证`; release packaging always refers to `./scripts/package-skills.sh`; CI remains unmodified throughout.
