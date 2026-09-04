# Rollout and rollback

## 1. Rollout principles

每阶段先 evidence 后扩大权限；observe before enforce；修复权限晚于只读 review/validation；auto-merge 最后启用。每个阶段指定 owner、consumer fixtures、entry/exit criteria 和演练过的 rollback。

## 2. Stages

### R1 — Sanitize

产物：private archive plan、full-history audit、sanitized no-history snapshot、MIT/third-party notices、public contribution/security docs。

Exit：PUB-001–009 关闭；snapshot scans/tests 通过；未执行 public create，直到独立授权。

### R2 — Contract

产物：versioned adapter/provider/review schemas、thin caller、只读 reusable workflow、pending lifecycle、external catalog schema。

Exit：empty/existing/public/private fixtures 通过；未知 stack 无假绿色；caller pin lint 通过。

### R3 — Observe

产物：shadow `ai-review-gate` 与 `repo-validation`，不作为 required checks，不 auto-fix/merge。

Exit：误报/漏报、latency、provenance 与 SHA freshness 数据满足阈值；shadow 不能被误读为 success。

### R4 — Validate

产物：public/private consumer permission、fork、actor、secret、adapter provenance/self-modification fixtures。

Exit：模型 job 无 write token；push job 无模型 secret；fork/unknown 无 secrets；PR 无法修改控制面自批。

### R5 — Repair

产物：Dedicated Fixer App、pre-push authorization、先一次修复，再启用最多三轮与 fingerprint guard。

Exit：新 SHA 重触发；重复/含糊/架构/冲突/validation/permission failure 转 human_required；无 force/PAT/default-branch write。

### R6 — Protect

产物：幂等 Ruleset reconcile required checks、conversation resolution、no direct/force push、squash-only、auto-merge 与 sensitive-path human approval。

Exit：普通 fixture 全绿可 squash；任一缺失 gate 或敏感路径不可 auto-merge；重复 reconcile 无 drift。

### R7 — Adopt

选择一个明确授权 consumer 试点，从 pending/shadow 开始，记录 incident、人工介入、cost、latency 与 false-positive。首个 IaC consumer 的 provider/adapter 只存在于 consumer 配置。

Exit：至少一个完整 happy path 和所有关键 stop path 在真实 PR 演练通过。

### R8 — Expand

仅向 contract/no-deploy/secret-boundary/provenance tests 全过的 consumers/adapters 扩展。每个 consumer 独立 pin、secrets、App install 与 sensitive policy；无组织级隐式 rollout。

## 3. Rollback controls

| Failure | Immediate action | Preserved capability |
|---|---|---|
| Fixer incident | disable fixer / revoke Fixer App or secret | read-only review + validation |
| Auto-merge incident | disable auto-merge | required gates + human merge |
| Gate outage | explicit Ruleset change required -> evaluate/disabled，恢复 human merge | audit + deterministic checks where available |
| Provider outage | switch reviewer/fixer to supported provider or `none` via sensitive PR | validation/human path |
| Runtime regression | consumer PR pin previous immutable SHA | published pins remain immutable |
| Adapter regression | return shadow/pending or previous trusted adapter pin | review-only/human merge |
| Secret exposure | stop jobs, revoke/rotate credential, preserve redacted incident evidence | no history rewrite |

Rollback 变更本身是 governance-sensitive，必须显式人工批准。紧急 gate downgrade 要记录 owner、reason、expiry 和恢复条件，不能静默长期 disabled。

## 4. Forbidden rollback shortcuts

- 不使用 PAT、force push、history rewrite。
- 不移动或重新发布既有 tag/SHA pin。
- 不通过删除审计 comments/checks/commits“清理”事故。
- 不把 validation failure 变成 placeholder pass。
- 不让 PR 修改自己的 caller/adapter/gate/policy 完成自救放行。

## 5. Remote cleanup

只在 GitHub 远端：

- Merge 后删除同库、已合并且仍指向预期 SHA 的 head branch；fork branch 不删除。
- 新 SHA 到达时通过 concurrency/API 取消同 PR 的 obsolete runs；run 在发布 check 前再次核对 SHA。
- Review/validation artifacts 使用有限 retention；debug/model artifacts 更短并 redacted。
- 保留 PR、review、commit、checks、repair decisions 与必要 bot comments。

不提供 local cleanup CLI/daemon/schedule，不枚举或删除本地 worktree、branch、sandbox。Codex、Claude、OpenCode 等 agent 按自身生命周期管理本地资源。

## 6. Rollout evidence dashboard

每阶段最少记录：runtime/adapter SHA、fixture matrix、pass/fail、permissions snapshot、secret exposure result、false green count、human_required reasons、repair rounds、rollback rehearsal date。不得记录 raw secrets、完整模型 transcript、consumer private source 或个人数据。

## 7. Final go/no-go

Go 需要：所有 CAP-001–020 acceptance evidence、两轮 SPEC preservation/coherence 复核、public readiness gates、试点成功、rollback 演练和 maintainer 对外部 mutations 的单独授权。任何 fake-green、provenance bypass、secret leak 或 sensitive-path auto-merge 是立即 no-go。

