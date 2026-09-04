# Provider options

查证日期：2026-09-04。以下均以官方文档为依据；provider 功能会变化，实施时应重新核对并 pin action/runtime SHA。

## 1. Contract position

Public core 不把 provider-native comment、reaction、approval 或 auto-fix session 当作安全边界。每个 reviewer/fixer adapter 必须输出公共 schema，由可信 runtime 验证并发布 SHA-bound gate。Deterministic project validation 始终独立。

## 2. Claude Code GitHub Actions

官方文档：[Claude Code GitHub Actions](https://code.claude.com/docs/en/github-actions)。

已核实：

- `claude-code-action` 可响应 PR/issue、运行自动 prompt、修改代码并 push。
- 官方支持 reusable workflow 组织级复用，也支持 API key/OAuth/OIDC provider authentication。
- Public fork PR 默认拿不到 secrets；官方示例对 review 使用 read permissions。
- 官方明确说明：用默认 `GITHUB_TOKEN` 产生的 commit 不会触发 workflows；应让 Claude GitHub App 认证或提供 custom App token。
- 官方 App 权限面较宽；若只需要 Action，可用 custom GitHub App 缩小权限。

规范判断：可作为 reviewer 或 fixer provider，但 public runtime 必须把模型执行与 push 分 step/job，并采用 Dedicated Fixer App 短期 token；不得直接照搬宽权限 quickstart 为公共默认。

## 3. Claude Code Web auto-fix

官方文档：[Claude Code on the web — Auto-fix pull requests](https://code.claude.com/docs/en/claude-code-on-the-web#auto-fix-pull-requests)。

已核实：

- Claude 可监听 PR 的 CI failure/review comments并在 fix 清晰时 push。
- Auto-fix 是 per-PR toggle，需要 Claude GitHub App。
- Claude Code on the web 目前是 research preview。
- 含糊或架构性请求会询问用户；重复/no-action event 不修；base advance 造成的冲突没有 webhook 自动触发。

规范判断：它最接近现成闭环，但不是稳定、provider-neutral、全 repository 的公共 runtime，且其交互/身份模型无法替代本规范的结构化 gate、三轮 guard 与 sensitive-path policy。因此只作为可选 consumer convenience，不作为 core。

## 4. Codex GitHub Action

官方文档：[Codex GitHub Action](https://learn.chatgpt.com/docs/github-action)。

已核实：

- `openai/codex-action@v1` 可在 CI 中 review、apply patches、执行 repeatable tasks。
- 需要 OpenAI credential（例如显式 `OPENAI_API_KEY` secret）。
- 支持 sandbox/safety inputs、trigger allowlists 与 `--output-schema` 结构化 JSON。
- 官方安全清单要求限制触发者、把 PR/commit/issue 输入视为 prompt-injection 风险，并使用最小 sandbox。

规范判断：适合作为可插拔 reviewer/fixer。Consumer 必须显式提供 OpenAI credential；action version 在真实实现中 pin immutable SHA；模型 job 无 GitHub write token，patch 由独立 push step 授权。

## 5. GitHub Copilot code review

官方文档：[About GitHub Copilot code review](https://docs.github.com/en/copilot/concepts/agents/code-review)。

已核实：

- Copilot 可自动 review，发现问题并建议 fixes；可配置 review new pushes。
- 默认 review 不计 required approvals；启用后 approval 可计入 merge requirements，但该能力目前 public preview。
- 新 commit 后 approval 会 dismissed，可重新请求 review。
- Copilot 从 PR head 读取 repository instructions/agent skills，而非 base branch。

规范判断：可选 reviewer/approval gate，但不能替代 deterministic validation。由于 instructions 来自 head branch，治理敏感 PR 更不能让 Copilot native verdict 单独控制自身 gate；必须由 base/runtime schema 与 path policy包裹。

## 6. Comparative decision

| Option | Reviewer | Fixer | Structured output fit | Core role |
|---|---:|---:|---|---|
| Claude Code Action | yes | yes | adapter required | supported provider |
| Claude Web auto-fix | indirect | yes | insufficient as-is | optional convenience only |
| Codex Action | yes | yes | strong via output schema | supported provider |
| Copilot review | yes | suggestions/native approval | native review, adapter needed | optional reviewer/gate input |
| `none` fixer | n/a | no | n/a | required safe option |

GitHub 没有官方 App 能自动理解所有 consumer 技术栈并替代 deterministic validation。技术栈判定与真实命令必须由项目 adapter contract 解决；未知时保持 pending。

