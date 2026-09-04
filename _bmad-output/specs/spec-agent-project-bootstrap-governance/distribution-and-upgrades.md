# Distribution and upgrades

## 1. One-repository release model

`blue126/agent-project-bootstrap` 是唯一 public source 和 governance runtime release repository。它发布经过测试的 immutable commit SHA；consumer 不执行浮动 `main`、branch 或可移动 tag。Tag/changelog 用于发现，SHA 用于执行。

Public/private consumer 使用相同 caller contract：GitHub repository visibility 不能改变 runtime 行为，只改变 secret/App 安装和 fixture 组合。

## 2. Consumer footprint

```text
.github/workflows/<thin-caller>.yml
.agent/bootstrap.yml
<local validation adapter>
<local sensitive-path policy>
explicit secret mappings
```

Thin caller 只声明 event、最小 permissions、immutable runtime `uses:`、显式 inputs/secrets。禁止复制 public runtime 逻辑进 consumer，禁止 `secrets: inherit`。

## 3. Manifest evolution

扩展现有 `bootstrap-manifest.yml`，而不是创建平行 manifest。后续 schema 应声明：

- governance runtime release/pin policy；
- managed caller、config 与 default sensitive policy；
- adapter contract version 与 lifecycle state；
- provider slots；
- GitHub required checks/auto-merge/cleanup 的 opt-in state；
- external adapter/Skill catalog metadata。

Schema migration 必须向后识别 v3 consumer；未知更高版本 fail closed。`.agent/bootstrap.yml` 继续记录 managed file hashes 与 selections，并新增 validation/provider/runtime state。

## 4. Managed-file upgrade semantics

保留现有算法：

1. destination 不存在：创建并记录新 hash。
2. current == desired：仅刷新记录。
3. current == previously-recorded：可升级并记录新 hash。
4. current != recorded：保留 consumer 修改，列出差异，不更新为 desired。
5. 只有用户显式 `--update --force` 才覆盖 consumer 修改。

Caller、policy、adapter scaffold 与 managed config 都适用。Runtime pin/Ruleset/permission 变更即使机械可升级，也必须以 governance-sensitive PR 呈现，不能在本地命令中静默生效。

## 5. Runtime release promotion

Release candidate 必须通过：

- shell/relative-reference/bootstrap tests；
- schema/contract/provider tests；
- public/private consumer fixtures；
- fork/actor/secret/permission tests；
- self-modification/provenance tests；
- license、secret、PII/internal URL 与 dependency audit；
- rollout rollback rehearsal。

通过后记录 immutable SHA、schema versions、supported migrations 与 known limitations。Public `main` 的普通合并不自动更新任何 consumer。

## 6. Adapter catalog

每个 external adapter 记录：source、immutable version/ref、license、supported stacks、contract version、install docs、maintenance status。登记不是信任或自动安装。Consumer 通过 PR 显式选择，先 shadow；contract、no-deploy 与 secret-boundary tests 全过后才 enforce。

Core release 不捆绑 adapter implementation。失联、许可变化、stale 或 digest mismatch 的 catalog entry 必须标记 unavailable，consumer fail closed 或回退上一受信 pin。

## 7. GitHub configuration

沿用 `configure-github.sh` 的显式 target、幂等 create/update 与 drift normalization。扩展 Ruleset 时：

- 从 verified repository metadata 取得 default branch，不硬编码本地 branch 名；
- 先 read/normalize/compare，重复命名或歧义拒绝选择；
- required checks、conversation resolution、no direct/force push、squash-only 与 auto-merge 分阶段启用；
- 每个外部写均需独立显式 opt-in；dry-run/evaluate 优先。

Repository creation、App install、secrets、visibility 与 Ruleset 不因 bootstrap init 自动发生。

## 8. Compatibility with existing integrations

Superpowers 与 Understand Anything 保持 managed-upstream、project-scoped/explicit、immutable known-good pin 和 manual promotion。Public readiness audit 可改变是否继续 catalog/bundle，但不得把浮动 upstream 安装变成默认。

Human 3.0 按 [public-readiness.md](public-readiness.md) 从 public bundle 移除，只保留不可自动化的 external record。

