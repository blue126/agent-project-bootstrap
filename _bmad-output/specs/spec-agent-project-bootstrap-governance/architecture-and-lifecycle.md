# Architecture and lifecycle

## 1. System shape

```text
consumer repository
  thin caller (immutable runtime SHA)
  .agent/bootstrap.yml
  local validation adapter + sensitive-path policy
  explicit secret mappings
             |
             v
public reusable runtime (trusted immutable SHA)
  classify -> review -> validate -> gate -> optional repair
             |                         |
             v                         v
 provider implementation       Dedicated Fixer App push
                                      |
                                      v
                            new HEAD / synchronize
                                      |
                                      +----> review + validate again
```

Runtime orchestration、schema 与安全策略属于 public core；技术栈命令、consumer secrets 与扩展敏感路径属于 consumer。

既有 brownfield 项目沿用仓库已提出的独立 adoption 流程：先只读检查与增量合并，再由治理 init 写入新状态。它不得退化为对既有 `AGENTS.md`、CI 或 adapter 的覆盖式 empty-project 初始化。

## 2. State machine

| State | Review | Validation | Fixer | Auto-merge | Transition condition |
|---|---:|---:|---:|---:|---|
| `pending` | yes | unavailable/fail closed | no | no | init with unknown stack |
| `review_only` | yes | contract not trusted | no | no | reviewer configured |
| `shadow` | yes | runs but not required | no by default | no | adapter installed + contract tests pass |
| `enforced` | yes | current-SHA required | policy-controlled | ordinary paths only | provenance/security fixtures pass |
| `human_required` | read-only | may run | no | no | ambiguity, sensitive path, loop/permission/validation failure |

状态保存在 managed config，但执行时以默认分支/immutable runtime 的 schema 验证。PR head 不能通过修改状态字段把自己升级到 `enforced` 或降低 gate。

## 3. Validation adapter contract

Contract 阶段至少定义：

- versioned manifest：adapter id、version、license、supported stacks、entrypoint、install docs、content SHA。
- invocation：runtime 传入 repository、PR number、base SHA、head SHA、workspace 与无 secret 环境。
- deterministic result：exit 0 只代表所有声明验证成功；非零或缺失结果 fail closed。
- provenance：控制面 adapter SHA 必须与默认分支配置或 immutable catalog pin 一致。
- limits：timeout、resource ceiling、network policy、artifact policy。
- tests：contract、no-deploy、secret-boundary、tamper、missing/stale/SHA mismatch。

External catalog 仅登记元数据和安装说明。安装 adapter 是显式 consumer PR；public core 不自动拉取任意社区代码。

## 4. Trusted checkout pattern

1. 可信 job 从 immutable runtime 启动，读取 GitHub event metadata。
2. 通过 API 重新取得 repository、PR、base/head refs 与完整 SHA，拒绝不一致。
3. 从 base/default branch 或 runtime pin 读取 adapter manifest、gate schema 与 sensitive policy。
4. 单独 checkout PR head 作为被验证工作区；不使用 `pull_request_target` 执行它。
5. 调用受信 adapter entrypoint 验证 PR workspace。
6. check producer 发布绑定 `repository + PR + head SHA + adapter SHA` 的结果。

PR 修改 adapter 时，本次运行仍使用 base 控制面；该修改自身被分类为 governance-sensitive，必须人工合并后才影响后续 PR。

## 5. Review/fix/re-review algorithm

1. Classifier 先判断 fork、actor trust、sensitive paths、validation state 与当前 HEAD。
2. Reviewer 在 read-only context 生成 structured verdict；独立 schema validator 验证身份、SHA、enum、paths 与 fingerprint。
3. `pass` 仅满足 AI gate；仍等待 deterministic validation 与 Ruleset。
4. `needs_fix` 只有在同库可信 actor、普通路径、configured validation、round < limit 且 findings 明确可执行时进入 fixer。
5. Fixer 在无 GitHub write token 的 workspace 生成 patch；受信 validation 先验证结果。
6. 最小 push step 重新读取 PR，核对 repository、open state、actor、head ref、旧/新完整 SHA、changed paths；之后获取短期 Fixer App token并普通 push。
7. `synchronize` 产生新 HEAD，旧 checks/verdict 失效并回到步骤 1。
8. 相同 blocking fingerprint 再现、达到三轮、冲突、验证/权限失败、含糊或架构性 finding -> `human_required`。

Round 以 `(repository, PR, initial-series-id)` 计数；每次 fixer push 至多加一。人工 push 创建新 SHA，但不自动清除历史 fingerprint，除非 maintainer 明确开始新 repair series。

## 6. Gate truth table

| Condition | `ai-review-gate` | `repo-validation` | Auto-fix | Auto-merge |
|---|---|---|---|---|
| validation pending | current verdict possible | not satisfied | no | no |
| fork / unknown actor | no-secret read-only policy only | no-secret checks only | no | no |
| sensitive path | review informational | no-secret checks possible | no | no |
| ordinary, verdict pass, validation pass, current SHA | pass | pass | n/a | yes if Ruleset satisfied |
| needs_fix, eligible | pending | current result | bounded | no until next SHA passes |
| human_required | fail/neutral per mode | may report | no | no |

## 7. Check naming and provenance

Required stable check names are `ai-review-gate` and `repo-validation`. Shadow mode uses distinct non-required names or an explicit neutral conclusion so it cannot masquerade as enforced success. Every check includes head SHA, runtime SHA, adapter SHA/version and policy classification in machine-readable output. Only approved GitHub App/workflow identities may produce required checks.

## 8. Audit trail

保留 PR、commits、review results、gate results、adapter/runtime SHA、repair round/fingerprints 与必要 bot comments。不要把完整模型 transcript 作为默认长期 artifact；若调试需要，使用短 retention、redaction 与受限访问。
