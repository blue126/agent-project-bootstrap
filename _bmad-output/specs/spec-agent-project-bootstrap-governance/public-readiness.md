# Public readiness

## 1. Current assessment

状态：**NOT READY FOR PUBLICATION**。

已验证的正向基础：

- 当前 bootstrap/update、GitHub create/configure、pins、policy 与 integration tests 全部通过。
- 基础 tracked-file 高风险 literal scan 未发现常见 private-key/token pattern；这不等于完整审计。
- repository mutation 要求显式 target；Ruleset reconcile 幂等；integration refs immutable。

阻塞项：

| ID | Finding | Required disposition |
|---|---|---|
| PUB-001 | 根目录无 MIT `LICENSE` | sanitized snapshot 添加 MIT，确认 copyright holder/year |
| PUB-002 | 无 `THIRD_PARTY_NOTICES.md` | 从审计后的 third-party inventory 生成并由 CI 验证 |
| PUB-003 | Human 3.0 未声明许可却 bundled/tracked | 从 public snapshot 完全移除内容，仅 external catalog record |
| PUB-004 | `MIT + Commons Clause` bundled policy | Closed 2026-09-04：maintainer 明确接受销售限制；保留完整许可证、inventory acceptance 与 prominent notice |
| PUB-005 | 缺 CONTRIBUTING/SECURITY/CODE_OF_CONDUCT 与 public support policy | 发布前添加并校验 links/contact 不泄露个人信息 |
| PUB-006 | README/scripts 含 private source/current-checkout 假设 | 重写 public installation/distribution 文案并保持 local checkout support |
| PUB-007 | 旧 private Git history 未完成 secret/PII/internal URL/private dependency/license audit | 对 full history 与 sanitized tree 分别审计并保存非敏感 evidence |
| PUB-008 | 新 public snapshot/无 ancestry 流程尚未演练 | fixture 验证 orphan/snapshot 与 archive/public repo 边界 |
| PUB-009 | Public governance runtime/schema/tests 尚不存在 | 按 Contract–Protect 阶段实施后再 enforce |

## 2. Migration boundary

不得直接将当前 private repository 改为 public。后续经单独授权执行：

1. 把现有 private repository 重命名为 `agent-project-bootstrap-private-archive`，保持 private。
2. 冻结迁移基线，审计 current tree 和完整 history。
3. 生成 sanitized staging tree；删除 private-only/unlicensed/internal/consumer-specific 内容。
4. 在 staging tree 运行测试、secret/PII/URL/dependency/license scanners 与人工抽查。
5. 从 staging tree 创建无旧 history 的新 root commit/snapshot。
6. 另行明确授权创建新的 public `blue126/agent-project-bootstrap`。
7. 开启 public CI、贡献治理与 release 流程；仅发布审计通过的 runtime SHA。

本 SPEC 不执行上述任何 GitHub 外部变更。

## 3. Sanitization checklist

- Secret：current tree、full history、tags、large files、patches、fixtures、docs examples。
- Personal data：姓名、email、路径/usernames、assessment/memory/transcripts、screenshots/metadata。
- Network identifiers：internal/private URLs、hosts、IPs、cloud account/tenant/repository identifiers。
- Dependencies：private repos/registries/packages/submodules、credentials-required install paths。
- Consumer content：consumer-specific adapter、secret names/values、infrastructure topology、deployment commands。
- Licensing：每个 bundled file/source 的 source/ref/license/copyright/local modifications。
- Documentation：public URLs、neutral examples、safe contact/security reporting path。

扫描“未命中”只是一项 evidence；许可归属、语义性内部信息和图片/二进制必须人工复核。

## 4. Licensing policy

- Public root code/documentation默认 MIT，除明确标记第三方内容。
- Third-party content 保留原 LICENSE/copyright，不用 root MIT 覆盖。
- `third-party-sources.yml` 继续作为 source/ref/license/modifications inventory，并新增 bundled/availability/automated/action 等字段。
- CI 对所有 bundled third-party entries 要求可接受的明确许可证、对应 notice 与实际文件一致。
- `undeclared`、unknown 或不在 allowlist 的内容不得 bundled；只能在合法且不误导时作为 external link/catalog。
- `pre-mortem` 的 Commons Clause 销售限制已由 maintainer 于 2026-09-04 明确接受；该例外必须在 allowlist、inventory 与 notices 中保持一致。

## 5. Human 3.0 disposition

Public tree 删除 `skills/human-3-development-assessor/**` 的所有内容、patch、installer 与 package entry。允许的唯一记录：

```yaml
id: human-3-development-assessor
upstream: chengjialu8888/Human-3.0
availability: private_only
license: undeclared
bundled: false
automated: false
action: Visit upstream
```

不得自动下载、安装、复制、patch 或暗示 public project 已获授权。用户自行访问上游并满足访问/许可条件。

## 6. Public project baseline

首次 public snapshot 至少包含：MIT LICENSE、README、CONTRIBUTING、SECURITY、CODE_OF_CONDUCT、THIRD_PARTY_NOTICES、third-party inventory、release/security policy、CI status，以及可重现的 sanitized snapshot provenance。Issue/PR templates 不得索取 secrets 或 private logs。

外部贡献默认不能直接成为 consumer runtime：先通过 CI/review，进入 public main，再由 maintainer 发布 tested immutable SHA，最后由 consumer 的 governance-sensitive upgrade PR 采用。

## 7. Publication gates

只有全部满足才可请求创建 public repository：

- PUB-001–009 closed 或由 maintainer书面接受明确 residual risk；
- full-history audit 与 sanitized-tree audit 均有 evidence；
- public snapshot 无父提交指向 private history；
- license/notice CI、secret/PII/URL scan 与全测试通过；
- private archive 保持 private，名称/remote plan 已核对；
- public name/visibility/create action 获得新的显式授权。
