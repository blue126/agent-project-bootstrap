# Claude Auto Review 引导选择器设计

**状态：** 已获设计批准，待规格审阅。
**日期：** 2026-09-05
**范围：** 为 `github-workflow` 增加一个显式、交互式的 Claude Auto Review 引导选择；不安装或配置 Claude GitHub App、Claude Code Action、认证、GitHub Actions workflow、Auto Fixer、AI merge gate 或 Auto Merge。

## 背景

项目当前提供了许多 GitHub governance 契约和验证内核，但没有实现端到端的自动 review、自动修复或自动合并。用户要先实现的真实能力是评论型 Claude Auto Review：在 PR 上分析并发布 review/comment；Auto Fixer 和 Auto Merge 均明确暂缓。

Claude Code 的官方 GitHub App 安装向导负责 GitHub App、凭据和 review workflow 的实际设置。当前官方文档将该向导写作 `/install-github-app`。本仓库不得重新实现、嵌入或代跑该向导；bootstrap 只能让用户在项目初始化时明确选择是否需要后续指引。

现有 bootstrap 已对 Curated Skills、Understand Anything、workflow 和 Superpowers 使用显式交互式选择，并将每项选择记录到目标 `.agent/bootstrap.yml`，使 `--update` 能安全重放。不记录 Claude Auto Review 的选择会让更新无法确定用户意图；把它写成 `reviewer: claude` 或“已安装”则会虚假声称远端能力已经完成。

## 目标

1. 仅在用户选择 `github-workflow` 后，以 TTY 互动方式询问是否选择 Claude Auto Review setup guidance。
2. 将选择持久化为 `selected` 或 `skipped`，以便更新可重放且不会猜测用户意图。
3. 仅在初次 bootstrap 且状态为 `selected` 时，输出用户必须在 Claude Code 中亲自运行 `/install-github-app` 的下一步。
4. 将 bootstrap manifest 升级到 schema v5，并使已有 v4 项目以安全默认值迁移。
5. 清晰说明选择只是提醒，绝不授权 GitHub、App、认证、secret、workflow、remote 或其他外部 mutation。

## 非目标

- 不调用 `/install-github-app`，不尝试启动 Claude CLI，也不执行任何官方安装器。
- 不安装 Claude GitHub App、Claude Code Action 或任何第三方上游内容。
- 不创建、修改或复制 `.github/workflows/` 中的 workflow。
- 不设置 `ANTHROPIC_API_KEY`、OAuth token、OIDC/WIF、GitHub App token 或任何 secret。
- 不向 provider config 写入 `reviewer: claude`。
- 不启用 AI review verdict gate、required check、Auto Fixer、Auto Merge、GitHub ruleset 变更或 `configure-github`。
- 不将 Claude Auto Review 变成第四种 workflow，也不改变 `none`、`github-workflow`、`superpowers` 的互斥关系。
- 不新增 managed integration manifest、upstream pin、rehydration 行为或 Action pin test。

## 用户交互与状态模型

### 适用条件

Claude Auto Review 选择器仅在 workflow 已确定为 `github-workflow` 时适用。它出现在 workflow 选择之后、任何 bootstrap 文件写入之前。

用户在 TTY 中看到：

```text
Enable Claude Auto Review setup guidance? [y/N]
```

输入 `y` / `Y` 产生 `selected`；任何其他接受的默认回答产生 `skipped`。现有 bootstrap 的输入校验和取消语义保持一致。

### 显式 CLI 选择

新增一对相互冲突的参数：

```bash
--select-claude-auto-review
```

```bash
--skip-claude-auto-review
```

它们只能与 `--workflow github-workflow` 一起使用。以下情况必须失败且不写目标文件：

1. 两个参数同时给出；
2. workflow 为 `none` 或 `superpowers` 时给出任一参数；
3. 在非 TTY 或 Agent process 中选择 `github-workflow`，但未给出任一参数；
4. 与 `--update` 同时给出任一参数。

第四项遵循现有更新契约：`--update` 只重放已记录选择，不接受新选择覆盖。

### 持久化状态

目标 `.agent/bootstrap.yml` 的 schema 升为 v5，并记录：

```yaml
schema_version: 5
components:
  claude_auto_review: selected # 或 skipped
```

`selected` 的定义是“用户选择显示官方下一步”。它不表示 App、Action、review provider、review gate、GitHub repository、认证或 secret 已安装、启用或配置。

仓库根目录的 `.agent/bootstrap.yml` 作为消费者状态样例也必须使用 schema v5，并使用：

```yaml
components:
  claude_auto_review: skipped
```

### 初次 bootstrap 输出

只有初次 bootstrap 且状态为 `selected` 时，在最终摘要输出：

```text
Claude Auto Review guidance was selected.
In a Claude Code session for this project, run /install-github-app to continue.
```

该文本是纯输出，不得作为 shell input、child process、`npx`、`gh`、Claude CLI 或任何安装命令执行。

状态为 `skipped` 时不得输出 `/install-github-app`。

## 更新与 schema 迁移

### v4 到 v5

`--update` 遇到 schema v4 的目标 manifest 时，必须完成以下确定性迁移：

```text
schema_version: 4
且没有 components.claude_auto_review
  → schema_version: 5
  → components.claude_auto_review: skipped
```

迁移不可把旧项目推断为 `selected`，不可打印官方安装指令，不可触发任何 GitHub 或 Claude 行为。

### v5 更新重放

schema v5 项目在 `--update` 时必须读取并重放记录的 `selected` 或 `skipped` 值，而不弹出选择器、不运行任何 App/Action 安装器，也不打印初次 bootstrap 的官方安装指令。

如记录值不是 `selected` 或 `skipped`，更新必须 fail closed 并说明 manifest 值无效。

凡是检查 target bootstrap schema 版本的脚本（包括 `scripts/configure-validation.sh`）必须接受 schema v5，同时继续兼容 schema v4 项目直到它们被 `--update` 迁移。

## Source manifest 契约

`bootstrap-manifest.yml` 从 `schema_version: 4` 升为 `schema_version: 5`，并在 `github` 下声明 Claude Auto Review 为：

```yaml
claude_auto_review:
  opt_in: true
  eligible_workflow: github-workflow
  selection: prompt
  post_bootstrap_command: /install-github-app
  action: instruction_only
  external_configuration: user_runs_official_claude_code_installer
```

该契约必须配有英文注释，明确它不会配置 GitHub App、GitHub authentication、secret、remote、ruleset、provider 或 workflow。

## 文件变更

| 文件 | 责任 |
|---|---|
| `bootstrap-manifest.yml` | schema v5 及 Claude Auto Review 的 declarative `github` 契约。 |
| `scripts/bootstrap.sh` | flags、冲突检查、TTY selector、Agent/non-TTY fail-closed、v4→v5 migration、state serialization、初次 selected 提示。 |
| `.agent/bootstrap.yml` | v5 消费者状态样例，包含 `claude_auto_review: skipped`。 |
| `scripts/configure-validation.sh` | 接受 schema v5，并保留 v4 兼容。 |
| `AGENTS.md` | 更新 bootstrap 的通用交互说明；禁止 Agent 代跑官方后续命令。 |
| `templates/AGENTS.md` | 写入目标项目的 durable rule：记录选择只是提醒，不构成外部 mutation 授权。 |
| `README.md` | 更新标准互动流程和 non-interactive 行为说明。 |
| `tests/test-bootstrap.sh` | 选择器、flags、输出、适用范围、无外部副作用的行为测试。 |
| `tests/test-bootstrap-update.sh` | 重放、v4→v5 migration、invalid value、update override 拒绝。 |
| `tests/test-policy-text.sh` | 用户可见 guard wording 的回归测试。 |

`policies/workflow-selection.md`、`.github/workflows/`、`schemas/provider-config.schema.json`、`scripts/evaluate-ai-review-gate.sh`、`scripts/authorize-fixer-push.sh`、`scripts/configure-github.sh`、`scripts/rehydrate.sh`、`integrations/`、`catalog/` 和 `tests/test-pins.sh` 必须保持不变。

## 详细行为要求

### `scripts/bootstrap.sh`

1. 使用单独变量保存选择，值仅允许 `selected`、`skipped` 或未定。
2. 复用现有成对 install/skip flags 的冲突校验模式；不可把新状态伪装为 integration installation。
3. 当 `github-workflow` 适用且用户在 Agent process 或非 TTY 中未提供显式状态时，以错误退出；不可采用默认 `skipped` 静默继续。
4. 对非 `github-workflow` 的 workflow，确保选择器不出现且 flags 被拒绝。
5. 在已有 target manifest 的 `--update` 分支中，读取 v4/v5 状态并实施上述迁移/重放规则。
6. target manifest 输出固定为 schema v5，包含 `components.claude_auto_review`。
7. 只在初次 selected 成功写入 bootstrap-managed 文件后输出官方命令提醒。
8. 不增添任何 `gh`、`git remote add`、secret、workflow、provider 或 shell command execution。

### 文档与 policy

- `AGENTS.md` 必须说明标准 interactive flow 在选择 `github-workflow` 后会显示此可选引导，并说明用户必须亲自在 Claude Code session 中执行官方命令。
- `templates/AGENTS.md` 必须把该限制作为 target project 的 cross-agent policy：该状态不授权 App 安装、GitHub/Auth/secret 配置、remote mutation 或官方命令执行。
- `README.md` 必须以中文说明该选择的作用与局限，且必须保持 GitHub repository creation、GitHub configuration 与该引导是独立明确操作的边界。

## 验收标准

1. TTY 的 `github-workflow` bootstrap 显示 Claude Auto Review selector，并将 selected/skipped 精确写入 v5 target manifest。
2. selected 的初次 bootstrap 输出字面包含 `/install-github-app`；skipped 输出不包含该文本。
3. selected 路径不执行 `gh`、不认证 GitHub、不创建 `origin`、不创建 `.github/workflows/`，且不写 `reviewer: claude`。
4. `none` / `superpowers` 路径不显示 selector；使用 Claude Auto Review flag 时失败。
5. `github-workflow` 的 Agent/non-TTY 路径没有显式选择时失败。
6. 冲突 flags 与 `--update` override flags 均失败。
7. v4 target manifest 在 `--update` 中变为 v5 + skipped，且不输出命令提示。
8. v5 target manifest 的 `--update` 重放值、不提示、不触发外部行为；非法记录值 fail closed。
9. 所有不受影响的现有 bootstrap、update、GitHub、governance、integration 和 public readiness 测试继续通过。
10. ShellCheck、Bash 语法检查、third-party inventory 检查和全体 `tests/test-*.sh` 继续通过。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| 用户误以为 selected 已启用 reviewer | 采用 `selected` 状态名称；所有文档明确它只表示提醒。 |
| Agent 自动执行官方安装命令 | 将命令限定为纯文本 bootstrap output；模板 policy 明确禁止代跑。 |
| 非 TTY bootstrap 静默跳过新选择 | 适用 workflow 缺显式 flag 时 fail closed，并增加测试。 |
| v4 项目被错误标记为已选择 | v4 缺字段只能迁移到 `skipped`，并测试。 |
| schema v5 被其他脚本拒绝 | 更新所有 target schema version validator，并覆盖其兼容路径。 |
| 选择器被误当成 workflow/provider/remote 配置 | 单独 component state、source manifest 注释、AGENTS/README wording 和 no-side-effect tests 共同限定。 |

## 验证策略

实现后按以下顺序验证：

```bash
shellcheck -S style scripts/*.sh tests/*.sh
```

```bash
bash -n scripts/*.sh tests/*.sh
```

```bash
./scripts/check-third-party-inventory.sh
```

```bash
for test_file in tests/test-*.sh; do bash "${test_file}"; done
```

另外执行 `git diff --check`，并确认受限文件的 diff 为空：

```bash
git diff --name-only -- .github/workflows policies/workflow-selection.md schemas/provider-config.schema.json scripts/evaluate-ai-review-gate.sh scripts/authorize-fixer-push.sh scripts/configure-github.sh scripts/rehydrate.sh integrations catalog tests/test-pins.sh
```
