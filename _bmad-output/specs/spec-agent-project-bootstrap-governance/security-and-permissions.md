# Security and permissions

## 1. Security invariants

1. PR head、PR text、commit messages、comments 与 model output 均不可信。
2. Default branch 或 immutable runtime 提供控制面；PR checkout 仅是数据面。
3. 模型可读代码但不持 GitHub write token；push step 不持模型 credential。
4. Required checks 绑定完整 HEAD SHA 和可信 producer。
5. Fork、unknown actor、sensitive paths、missing/stale adapter、schema/provenance/permission failure 全部 fail closed。
6. Public repository 不保存 consumer secrets；consumer caller 逐项映射 secrets。

## 2. Permission matrix

| Component | GitHub permissions | Secrets | Network/write |
|---|---|---|---|
| Classifier | contents/PR metadata read | none | no repo write |
| Reviewer model | checkout read; no GitHub write token | one explicit provider credential/OIDC only | provider egress only |
| Verdict publisher | checks/PR write as dedicated trusted identity | short-lived publisher token | structured output only |
| Validation | contents read; checks write separated if possible | none by default | adapter policy; no deploy/external write |
| Fix generation | workspace write only | model credential only | no GitHub write token |
| Fix validation | local workspace | none | no deploy/secrets |
| Fix push | contents write to verified head only | short-lived Fixer App token | no model access |
| Auto-merge | GitHub-native | none | Ruleset-controlled squash |
| Cleanup | actions/contents narrowly scoped | short-lived App token | merged branch/run/artifact only |

Job boundaries必须确保 secret-bearing job 不上传 workspace/transcript 给更宽权限 job，除非 artifact 完整性和 redaction 已验证。

## 3. Event safety

- 使用 `pull_request` / trusted workflow patterns；禁止 `pull_request_target` checkout 或执行 PR head。
- Fork PR 与 unknown actor 只允许无 secret、无 write token 的 deterministic/static inspection；需要模型 credential 时默认不运行并请求 maintainer 路径。
- Caller workflow 本身来自 consumer default branch，但其 PR 修改仍标记 sensitive；required gate 的 producer/runtime pin不能由该 PR 自己选择。
- 使用 concurrency group 绑定 repository/PR；新 SHA 取消旧 run，旧 run 不可发布新 SHA check。
- Checkout 设置 `persist-credentials: false`；push 只在最后独立 step 临时注入 App token。

## 4. Fixer pre-push authorization

最小 push step 必须重新从 GitHub API 获取并比较：

- exact `owner/repository`；
- PR number、open/non-draft state（按 policy）；
- PR 非 fork，head repository 与 target repository 相同；
- actor/author 在 allowlist 或具有规定权限；
- head ref 不是默认分支且与预期 ref 完全一致；
- API head SHA 等于 fixer 输入旧 SHA；
- proposed commit parent 等于旧 SHA，禁止 force/non-fast-forward；
- changed paths 不命中 base policy 的 sensitive paths；
- local validation 已对 proposed tree 成功且结果未过期。

全部通过后才获取短期 Dedicated Fixer App token。App 权限只需同库 contents write/必要 PR metadata read；明确禁止 administration、actions/workflows write、secrets、members 与 default branch push。

默认 `GITHUB_TOKEN` 不用于 fixer push，因为由它产生的事件可能不触发预期后续 workflows。也禁止 PAT。

## 5. Sensitive paths

默认 matcher 至少覆盖：

```text
.github/workflows/**
github/rulesets/** and ruleset/permission configuration
validation adapter entrypoint/manifest
AI gate schema/provider/prompt/control configuration
.agent/bootstrap.yml and bootstrap-managed governance configuration
secret/credential handling
release/deploy/external-write approval configuration
```

具体路径由受信 base policy 展开；consumer 可增加、不可通过 PR head 减少当前 PR 所适用的集合。命中后：只读 AI review、无 secret deterministic checks、`human_required`、no fixer、no auto-merge。

## 6. Review integrity

Schema validator 必须拒绝：未知字段策略不一致、短 SHA、路径越界/绝对路径、repository/PR/SHA mismatch、非法 enum、空 blocking finding fingerprint 和重复冲突记录。Fingerprint 由稳定规范生成，不信任模型随意变化；runtime 可基于 normalized path/summary/category 再计算或验证。

Provider comments 仅供人阅读。Gate producer读取受保护 artifact/check payload并验证 provenance；不得解析评论文字或 reaction 决定 pass。

## 7. Validation safety

Contract tests 证明 adapter：

- 对失败命令传播非零；不吞错、不返回假成功；
- 默认无 consumer/model/App secrets；
- 不执行 deploy、apply、publish 或其他 external write；
- 不读取 PR 提供的替代 entrypoint/gate；
- 对 missing、invalid、stale、digest mismatch、timeout fail closed。

需要服务凭据的项目验证不属于 public default gate；consumer 必须设计单独、人工批准且环境隔离的策略。

## 8. Audit and retention

保留最小审计证据：身份、runtime/adapter SHA、PR/head SHA、classification、check conclusions、repair rounds/fingerprints、push authorization result。Artifacts 有有限 retention；禁止默认持久保存模型全 transcript、raw secrets 或 consumer workspace。Merge 后 branch cleanup 不删除 PR、commit/check/review 记录。

