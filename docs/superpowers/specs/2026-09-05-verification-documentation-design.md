# 验证与发布前检查文档校准设计

**状态：** 已获得设计批准，待规格审阅。
**日期：** 2026-09-05
**范围：** 仅校准维护文档；不新增验证编排脚本，不修改 CI，不改变发布或治理行为。

## 背景

仓库已有 ShellCheck、Bash 语法检查、ruleset JSON 校验、完整 Shell 测试、第三方来源/许可证一致性检查和 Skills 打包能力。当前 CI 在 Ubuntu 与 macOS 上运行 ShellCheck、Bash 语法检查、ruleset JSON 校验与所有 `tests/test-*.sh`。完整测试中的 `tests/test-public-readiness.sh` 已调用 `scripts/check-third-party-inventory.sh`，因此第三方清单检查已经由 CI 间接覆盖。

README 和贡献指南分别维护验证命令，但两处命令集不同：README 额外列出 Skills 打包，贡献指南额外列出第三方来源检查。此前拟通过新增统一验证脚本消除漂移，但该方案会让本地开发者与 CI 机械重复完整验证，也会增加脚本与测试维护成本。

本设计选择更小的方案：让贡献指南成为唯一的维护者验证说明，README 链接到该说明；按目的区分本地自检、CI 证明与发布前打包。

## 目标

1. 让维护者理解哪些检查适合在本地按改动范围运行，哪些由 CI 对 PR 的准确提交独立执行。
2. 明确 Skills 打包是准备发布分发物时的额外步骤，而不是每个普通 PR 的必经操作。
3. 移除 README 与 CONTRIBUTING 中重复且容易漂移的验证命令清单。
4. 保持当前 CI、测试、打包行为和消费者项目治理状态不变。

## 非目标

- 不新增 `scripts/verify-distribution.sh`、Makefile、GitHub Actions job 或 reusable workflow。
- 不改变 `.github/workflows/ci.yml`。
- 不要求开发者在每次本地修改后运行完整测试。
- 不上传、发布或删除 `dist/` 中的产物；不改版本号或 Release。
- 不修改 GitHub ruleset、远端、权限、消费者项目的 validation mode 或 auto-merge 设置。

## 决策与理由

### CI 与本地检查承担不同责任

本地检查的价值是尽快反馈：维护者可以按照改动范围运行 lint、语法检查或相关测试，必要时再执行完整测试。CI 的价值是对已推送的准确提交，在没有本地缓存、未跟踪文件和个人环境差异的干净环境中提供独立、可审计的证明。CI 当前还覆盖 Ubuntu 和 macOS，而单个维护者通常只在一个系统上开发。

因此，完整 CI 验证不是对本地结果的无意义重复；但也不能把本地完整执行当作每次改动的强制要求。

### 发布前打包是独立阶段

`scripts/package-skills.sh` 生成被 `.gitignore` 忽略的 `dist/*.zip`。它验证的是可分发产物能否被构建，而不是普通源码或文档改动的正确性。打包只应在准备发布分发物时执行；CI 和日常 PR 不新增该步骤。

### CONTRIBUTING 是唯一权威说明

`CONTRIBUTING.md` 已面向贡献者说明开发原则和 PR 验证结果的要求，适合作为准确命令和执行时机的唯一来源。README 的维护章节只保留简短说明和指向贡献指南中验证章节的链接，避免以后两处独立更新命令。

## 文件变更

| 文件 | 变更 | 责任 |
|---|---|---|
| `CONTRIBUTING.md` | 重写“验证”章节，按本地自检、CI 独立证明、发布前打包三个场景说明现有命令与时机。 | 维护者验证的唯一权威说明。 |
| `README.md` | 将“维护与验证”改为简短的维护说明，并链接到 `CONTRIBUTING.md` 的验证章节；不再复制完整命令块。 | 面向读者指向权威维护文档。 |
| `.github/workflows/ci.yml` | 不修改。 | 继续验证 PR 和 main 的准确提交。 |
| `scripts/package-skills.sh` | 不修改。 | 继续在发布准备阶段生成 `dist/*.zip`。 |

## 文档内容要求

### `CONTRIBUTING.md` 的本地自检说明

文档必须说明本地检查是按改动范围选择的快速反馈工具，而不是每次修改都必须完整重复 CI。保留并解释以下现有命令：

```bash
shellcheck -S style scripts/*.sh tests/*.sh
```

用于修改 Shell 脚本时的静态质量检查。

```bash
bash -n scripts/*.sh tests/*.sh
```

用于快速检查 Bash 语法。

```bash
jq empty github/rulesets/protect-main.json
```

用于修改主分支 ruleset JSON 后检查其格式。

```bash
for test_file in tests/test-*.sh; do bash "${test_file}"; done
```

用于准备 PR 或需要完整本地确认时运行仓库测试；文档应鼓励只改动一个功能时优先运行相关测试。

### `CONTRIBUTING.md` 的 CI 说明

文档必须说明：无论本地运行了哪些检查，CI 仍会在干净的 Ubuntu 和 macOS 环境中验证推送到 PR 的实际提交。CI 是评审与合并决策所依赖的独立证据，而不是对开发者本地检查的信任替代。

### `CONTRIBUTING.md` 的发布前打包说明

文档必须将以下命令列在“准备发布分发物”场景下，而不是普通 PR 的检查清单中：

```bash
./scripts/package-skills.sh
```

说明该命令会生成 `dist/*.zip`，目录被 Git 忽略；它不上传、不发布且不改变版本号。

### `README.md` 的维护说明

README 必须不再包含与贡献指南重复的 ShellCheck、Bash、测试和打包命令块。它应以简短中文说明：贡献或维护此仓库时，请参阅 `CONTRIBUTING.md` 的“验证”章节了解按场景选择的检查和发布前打包步骤。

## 验收标准

1. `CONTRIBUTING.md` 是唯一包含完整维护验证命令的文档。
2. README 链接到贡献指南的验证章节，且不重复完整的维护验证命令块。
3. 贡献指南明确指出本地自检按改动范围选择，CI 仍独立验证推送提交。
4. 贡献指南明确把 `scripts/package-skills.sh` 限定为准备发布分发物时的操作。
5. `.github/workflows/ci.yml`、验证脚本和打包脚本在此子项目中没有行为修改。
6. 现有验证基线在文档变更后仍可通过：

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

7. 因为本子项目不改变 CI 或脚本行为，不新增自动化测试；文档链接与场景边界通过人工审阅确认。

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| README 链接与 CONTRIBUTING 标题后来不匹配 | 使用 Markdown 锚点链接，并在变更时人工点击/检查链接。 |
| 维护者误以为本地检查可取代 CI | 贡献指南明确写明 CI 验证已推送提交的独立角色。 |
| 维护者误以为每个 PR 都必须打包 | 将打包移到单独的“准备发布分发物”小节，并说明普通 PR 不需要它。 |
| 文档变更意外影响命令示例 | 在变更后运行现有 ShellCheck、语法检查、第三方来源检查和全部测试。 |

## 实施后检查

1. 阅读 README 和 CONTRIBUTING 的最终 Markdown，确认两者没有冲突的命令清单。
2. 从 README 的链接进入 CONTRIBUTING 的验证章节，确认锚点有效。
3. 运行验收标准中的既有验证命令。
4. 查看 `git diff --check`，确认没有空白错误。
5. 查看 `git diff -- .github/workflows/ci.yml scripts/`，确认本子项目没有改变 CI 或脚本行为。
