# Public Bootstrap Governance SPEC

状态：Draft for implementation planning

版本：0.1

基线：`origin/main@dc69db7f196c369b6fe5bb9e1408e30308647ce8`

范围：规范，不实施 workflow、repository migration 或 GitHub 设置变更

## 1. Capability intent

把 `agent-project-bootstrap` 建成 MIT 授权、技术栈无关、可接受外部贡献的 public bootstrap。它从真正的空目录或既有项目开始，安装通用 agent policy 与 GitHub PR governance，并在验证能力成熟后提供：

```text
review -> deterministic validation -> fix -> re-review
       -> required gates -> squash auto-merge -> remote cleanup
```

核心不猜测 consumer 技术栈，不提供假绿色 validator，也不把某个模型供应商、IaC 或特定构建工具固化为唯一实现。

## 2. Capability success

成功意味着：

- 空目录可初始化为 `validation: pending`；pending 只允许 review，不允许 auto-merge。
- public/private consumer 都通过 immutable commit SHA 调用同一 public reusable runtime。
- 当前 SHA 的真实 `repo-validation`、schema-valid `ai-review-gate` 和 Ruleset 同时满足后，普通 PR 才可 squash auto-merge。
- 新 HEAD 使旧 review、validation 与 merge readiness 全部失效；fixer push 会重新触发 review/validation。
- secrets、写权限与模型执行隔离；fork、未知 actor 与治理敏感改动 fail closed。
- public snapshot 不含旧 private history、secret、个人数据、内部 URL、private dependency、consumer adapter 或无再分发许可的 bundled content。
- 现有 managed-file hash、manifest、immutable pins、显式 repository targeting 和 Ruleset reconcile 继续作为兼容基线。

## 3. Context and existing baseline

截至基线提交，仓库已有且必须保留：

- `bootstrap-manifest.yml` schema v3，声明 project files、Skills、workflow、integration 与 GitHub 行为。
- `.agent/bootstrap.yml` 中的 per-file SHA-256；`--update` 只升级未被 consumer 修改的 managed file，`--force` 才覆盖用户修改。
- `scripts/configure-github.sh` 对显式 `OWNER/REPOSITORY` 的 `Protect main` Ruleset 做 create/read/normalize/compare/update；检测重复 Ruleset 时拒绝猜测。
- `scripts/create-github.sh` 要求显式 repository 与 visibility，拒绝覆盖既有 `origin`，只发布 bootstrap 管理文件。
- Superpowers 与 Understand Anything 的 immutable known-good pins，以及 pin consistency tests。
- bootstrap、update、GitHub create/configure、policy、pin、Understand Anything 测试；当前基线全部通过。
- `BACKLOG.md` 与 `prompts/adopt-github-workflow.md` 已将 brownfield adoption 设计为显式、增量、独立 worktree/Draft PR 流程；governance init 不得绕过该保留式迁移边界。

当前 public-readiness 缺口见 [public-readiness.md](public-readiness.md)。

## 4. Actors and trust zones

| Actor | Allowed | Forbidden |
|---|---|---|
| Reviewer | 读取代码/PR；发布评论与结构化 verdict | push、settings、secrets、以自然语言直接放行 gate |
| Validation workflow | 用受信 adapter 验证 PR checkout；发布当前 SHA check | 使用 PR 自带控制面给自身放行 |
| Dedicated Fixer App | 对可信同库 PR head 普通 push | 默认分支、fork、force push、settings、治理敏感路径 |
| GitHub auto-merge | Ruleset 满足后 squash merge | 绕过 required checks 或敏感路径人工确认 |
| Remote cleanup | 删除已合并远端 head、取消 obsolete runs、限期 artifacts | 删除本地 branch/worktree/sandbox；重写审计历史 |
| Maintainer | 明确批准外部变更、升级与敏感 PR | 通过隐式目标或浮动 pin 扩大影响面 |

## 5. Capabilities

### CAP-001 — Empty/existing init

`bootstrap init` 必须接受真正的空目录和既有项目。技术栈未知时写入 `validation: pending`，不得要求预先存在 `scripts/validate-pr.sh`，不得生成无操作但成功的 validator。显式技术栈选择优先于后续探测。

对既有 brownfield 项目，“接受”表示进入显式 adoption/reconcile 路径并保留现有文件，不表示用 empty-project bootstrap 覆盖冲突内容。

**Success signal:** 空目录 fixture 初始化成功；validation gate 明确非绿色；auto-merge 不可用。

### CAP-002 — Validation lifecycle

生命周期必须是 `init -> pending -> review-only -> configure/sync adapter -> shadow -> enforced`。状态转换需要可审计配置变更；不得由一次探测直接从 pending 跳到 enforced。

**Success signal:** 每个转换都有前置条件、当前 SHA check 与回退路径。

### CAP-003 — Stable adapter contract

公共 runtime 只调用固定协议；项目真实命令位于 consumer repository 的 local adapter。公共核心不包含 IaC、Terraform、Ansible、Jenkins、Node、Python 或其他技术栈实现。external catalog 可记录社区 adapter，但不捆绑实现。

**Success signal:** contract fixture 可替换任意技术栈 adapter；core tree 无 consumer-specific validator。

### CAP-004 — Trusted validation provenance

Gate 必须从默认分支或 immutable runtime 取得 adapter 控制面，再验证 PR checkout。adapter missing、invalid、stale、失败或 SHA 不匹配均 fail closed。PR 对自身 caller、adapter、gate 或 policy 的修改不能批准自己。

**Success signal:** self-modification fixture 无法产出可计入 merge 的绿色 check。

### CAP-005 — Provider-neutral configuration

配置至少支持：

```yaml
reviewer: claude
fixer: claude-action # codex-action or none
validation: pending  # pending or configured
```

Provider 通过同一 contract 接入。首个 IaC consumer 的 Claude reviewer、Claude Action fixer 与独立 Fixer App 只是 consumer 选择。

**Success signal:** provider contract tests 在 `fixer: none` 及至少两个 fixer provider 下通过。

### CAP-006 — Structured review verdict

唯一 gate 输入是 schema-valid structured result：

```json
{
  "repository": "owner/repository",
  "pull_request": 123,
  "reviewed_sha": "full commit SHA",
  "status": "pass | needs_fix | human_required",
  "findings": [{
    "fingerprint": "stable identifier",
    "severity": "blocking | non_blocking",
    "actionable": true,
    "path": "repository-relative path",
    "summary": "short explanation"
  }]
}
```

评论、reaction、summary 和 provider-native approval 本身均不是 `ai-review-gate` 输入。

**Success signal:** malformed、wrong-repository、wrong-PR 或 wrong-SHA verdict 被拒绝。

### CAP-007 — SHA-bound freshness

每个新 HEAD SHA 必须使旧 review、validation 和 merge readiness 失效。Fixer 只能普通 push；`synchronize` 必须触发同一 SHA 的新 review 与 validation。

**Success signal:** SHA A 的 pass 不可用于 SHA B；fixer commit 后两项 checks 都重新生成。

### CAP-008 — Bounded repair loop

自动修复最多三轮。重复 fingerprint、冲突、validation failure、permission failure、含糊意见或架构性意见立即停止为 `human_required`。先 rollout 一轮，验证后才放宽为三轮。

**Success signal:** 重复 fingerprint fixture 在第三轮以前停止；无第四次 push。

### CAP-009 — Thread ownership

Bot 只能 resolve 已消失的 bot finding thread；human thread 永不自动 resolve。线程来源与 fingerprint 必须可审计。

**Success signal:** human-authored unresolved thread 始终阻止要求 conversation resolution 的 merge。

### CAP-010 — Identity and token isolation

Reviewer、validation、Fixer App、auto-merge 与 cleanup 使用分离身份/permissions。模型步骤不持有 GitHub write token。修复后先验证，再由最小 push step 重查 repository、PR state、actor allowlist、head ref、完整 SHA、changed paths，最后获取短期 App token。

**Success signal:** 模型进程环境无 write token；push step 无模型 credential。

### CAP-011 — Untrusted-input and secret boundary

禁止 `pull_request_target` checkout/执行 PR head。PR 内容、commit message、review comment 与模型输出均是不可信输入。fork/未知 actor 不获得模型、App 或其他 secrets。consumer 逐个映射 secrets，禁止 `secrets: inherit`；public repo 不保存 consumer secrets。

**Success signal:** fork fixture 和 unknown-actor fixture 的 secret-bearing jobs 均 skipped/denied。

### CAP-012 — Governance-sensitive paths

公共默认敏感路径至少覆盖：`.github/workflows/**`、Ruleset/permission 配置、validation adapter、AI gate、bootstrap managed config、secret/credential handling、release/deploy/external-write approval。consumer 可扩展。此类 PR 可只读 AI review与无 secret deterministic checks，但禁止 AI fix 和 auto-merge，必须人工确认。

**Success signal:** 任一敏感路径命中后，fixer/auto-merge 均 fail closed。

### CAP-013 — Required gates and merge

普通项目文件仅在当前 SHA 的 `repo-validation`、`ai-review-gate` 与 active Ruleset 全部满足后允许 GitHub squash auto-merge。Pending validation 永不满足 required validation。

**Success signal:** ordinary fixture 全绿可 squash；缺任一 gate 或 merge method 非 squash 不可自动合并。

### CAP-014 — Thin pinned distribution

只维护一个 public bootstrap repository。consumer footprint 为 thin caller、`.agent/bootstrap.yml`、local adapter、sensitive-path policy 与显式 secret mappings。caller 必须引用 `blue126/agent-project-bootstrap` 的 immutable commit SHA，不能引用浮动 `main`。

**Success signal:** public/private fixtures 都调用同一 released SHA；floating ref lint 失败。

### CAP-015 — Safe upgrades

Bootstrap release 发布经过测试的 runtime SHA。runtime pin、caller、Ruleset 或 permission 的升级走普通 PR，并按敏感路径处理。继续使用现有 managed-file hash：未修改文件可升级，consumer 修改文件保留并报告差异，除非显式 `--force`。

**Success signal:** 现有 update tests 继续通过，并增加 caller/policy upgrade preservation fixtures。

### CAP-016 — Explicit external mutations

GitHub repository 创建、App 安装、secrets、Ruleset、auto-merge 与 visibility 均显式 opt-in。配置脚本幂等并要求 verified `OWNER/REPOSITORY`；不得从不可信路径或缺失 remote 猜测目标。

**Success signal:** 缺显式 target/flag 时零外部写；重复 reconcile 无漂移。

### CAP-017 — Remote-only cleanup

Merge 后删除远端 head branch；新 SHA 取消 obsolete workflow runs；artifacts 采用有限 retention；PR/review/commit/gate/必要评论保留为审计链。

**Success signal:** remote cleanup fixtures 通过；本地 branch/worktree/sandbox 未被访问或删除。

### CAP-018 — Sanitized public release

现有 private repository 先重命名为 `agent-project-bootstrap-private-archive` 并保持 private；经 secret、个人信息、内部 URL、private dependency 与许可审计后，从 sanitized snapshot 创建新的 public `blue126/agent-project-bootstrap`，不携带旧 history。根许可证 MIT，第三方保留原版权/许可并生成 `THIRD_PARTY_NOTICES.md`。

**Success signal:** public clone 无 private ancestry；scanner 与 license CI 通过。

### CAP-019 — Human 3.0 private-only handling

`human-3-development-assessor` 上游 `chengjialu8888/Human-3.0` 未声明许可证。Public repo 不捆绑、不复制、不 patch、不自动下载、不一键安装、不暗示再分发授权。catalog 仅可记录 `availability: private_only`、`license: undeclared`、`bundled: false`、`automated: false`、`action: Visit upstream`。

**Success signal:** public tree 与 packages 不含该 Skill 内容；catalog 文案仅引导 `Visit upstream`。

### CAP-020 — Staged rollout and reversible control

按 Sanitize、Contract、Observe、Validate、Repair、Protect、Adopt、Expand 推进。可关闭 fixer/auto-merge、将 gate 临时调为 evaluate/disabled、撤销 Fixer App/secret、回退上一 immutable SHA；禁止 PAT、force push、history rewrite 或移动已发布 pin。

**Success signal:** 每阶段有 entry/exit、owner、evidence 与 tested rollback。

## 6. Constraints

- Public core 技术栈无关、provider-neutral、fail closed。
- 所有跨仓库 runtime/action 依赖使用 immutable SHA；release tag 仅用于发现，不作为 consumer 执行 pin。
- 默认分支或 immutable runtime 是治理控制面的信任根；PR head 只能提供被验证的数据面。
- permissions 在 workflow/job/step 取最小交集；secret 仅进入明确声明的 job。
- 外部贡献不能直接传播至 consumer；必须经 release 与 consumer upgrade PR。
- 所有配置变更可重复、可比较、可审计。

## 7. Non-goals

- 不在 public core 实现任何项目技术栈 validator。
- 不承诺 AI reviewer 取代 deterministic validation 或人工架构判断。
- 不提供本地 cleanup CLI、daemon、schedule，不删除本地 worktree/branch/sandbox。
- 不在本规范阶段执行 repository rename、public repo 创建、visibility、Apps、secrets、Rulesets、auto-merge、commit、push 或 PR。
- 不为无许可证内容取得或推定再分发授权。
- 不建立第二个 governance runtime repository。

## 8. Acceptance matrix

| Acceptance | Capability / evidence |
|---|---|
| 空目录无假绿色 validation | CAP-001–004；empty/pending fixture |
| public/private consumer 调 pinned workflow | CAP-014；dual visibility fixtures |
| secrets 只进入声明 job | CAP-010–011；permission/secret tests |
| caller/adapter/gate/policy 不自批 | CAP-004、CAP-012；self-modification tests |
| fixer commit 触发新 review/validation | CAP-007；SHA transition test |
| 重复 finding 三轮内停止 | CAP-008；fingerprint loop test |
| fork/untrusted 无 write/model secrets | CAP-011；fork/actor tests |
| 普通 PR 全绿 squash auto-merge | CAP-013；happy path fixture |
| 敏感 PR 无 auto-fix/auto-merge | CAP-012；path policy test |
| 安全远端 cleanup、不碰本地 | CAP-017；cleanup boundary test |
| public snapshot 无私密/无许可/consumer 内容 | CAP-018–019；sanitization/license tests |

## 9. Companion specifications

- [architecture-and-lifecycle.md](architecture-and-lifecycle.md)
- [distribution-and-upgrades.md](distribution-and-upgrades.md)
- [security-and-permissions.md](security-and-permissions.md)
- [provider-options.md](provider-options.md)
- [public-readiness.md](public-readiness.md)
- [rollout-and-rollback.md](rollout-and-rollback.md)
- [.memlog.md](.memlog.md)

## 10. Assumptions and open questions

Assumptions：

- GitHub Actions reusable workflows、Rulesets、Checks 与 auto-merge 是首发平台能力。
- Consumer 默认分支可不是 `main`；未来实现必须从 verified repository metadata 获取，而现有 `Protect main` 是待演进基线。
- “人工确认”最终由 Ruleset/approval policy 表达，而不是模型 verdict。

Open questions（不阻塞本规范）：

1. Adapter contract 的 executable path、JSON schema versioning 与 timeout 上限需在 Contract 阶段定稿。
2. `ai-review-gate` 的结构化 verdict 存储介质选 check output、artifact 加 attest/签名，还是外部 store；无论选择都须绑定 repo/PR/SHA 与可信 producer。
3. **Resolved 2026-09-04:** maintainer 明确接受 `pre-mortem` 的 `MIT + Commons Clause` 销售限制并继续 bundled；完整许可证、inventory acceptance 和 prominent notice 必须保留。
4. 敏感路径人工确认所需 approval count、CODEOWNERS team 与 private consumer 的 App installation topology 需逐 consumer 配置。
5. Obsolete run cancellation 与 branch deletion 的具体身份可共用 cleanup App 还是拆分，需权限测试后决定。
