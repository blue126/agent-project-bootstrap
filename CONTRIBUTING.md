# Contributing

欢迎通过 GitHub issue 和 pull request 参与改进。

## 开发原则

- 先阅读 `AGENTS.md`；它是跨 Agent 的项目规则。
- 从远端默认分支创建独立 branch/worktree，不直接修改默认分支。
- 保持 public core 技术栈无关；项目专属 validation 放在 consumer adapter。
- 新第三方内容必须记录 source、immutable ref、license、copyright 和本地修改。
- 不提交 secret、个人资料、内部 URL、consumer 配置、对话转录或持久 memory。
- 外部 mutation、release 和 GitHub 设置变更必须获得单独明确授权。

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

### 本仓库的 CI 合并门槛

通用 `Protect main` 只管理 bootstrap 基础保护。本仓库另用独立的 `Self CI gates` 强制要求 `shellcheck`、`bootstrap-validation (ubuntu-latest)`、`bootstrap-validation (macos-latest)`，绑定 GitHub Actions App `15368`，并要求分支基于最新 main。重命名这些 CI 检查时，必须同步更新 `github/rulesets/self-ci-gates.json`，避免 PR 一直等待旧名称。

此 profile **仅适用于 `blue126/agent-project-bootstrap/main`**，不应用于下游项目，不改写原 `Protect main`、审批数量或 `.agent/bootstrap.yml` 的 adapter/AI 治理状态。观察型 `governance-observe` 不是硬门槛。

先检查计划（允许远端读取，不会写 GitHub；不是离线模式）：

```bash
./scripts/configure-github.sh --repo blue126/agent-project-bootstrap --profile self --native-auto-merge enable --dry-run
```

获得本次 GitHub 设置变更的单独授权后应用；先保存远端原配置到不提交的临时文件。配置器回读验证门槛有效后才开启仓库原生 Auto-merge，重复执行不应产生多余写入：

```bash
./scripts/configure-github.sh --repo blue126/agent-project-bootstrap --profile self --native-auto-merge enable
```

仓库能力开启不代表任何 PR 已自动入队。非治理敏感 PR 仍须获得逐 PR 授权，再在 GitHub 或 agent 中启用原生自动合并；治理敏感改动由人工处理，不能交给自动 fixer 或自动合并。CI 负责验证，agent 负责修复和协调，GitHub 负责强制检查与最终合并，不在 CI 中添加合并机器人或扩大写权限。

需要暂停能力时，只关闭原生 Auto-merge，保留所有检查和 Ruleset（即使门槛损坏也可执行）。这不是撤销已合并 PR，也不是完整配置快照恢复：

```bash
./scripts/configure-github.sh --repo blue126/agent-project-bootstrap --profile self --native-auto-merge disable
```

profile 拒绝不明 bypass、模糊范围或冲突的检查生产者；应先人工核对，不用关闭检查、管理员绕过或 `--enforcement disabled` 来解决。

### 准备发布分发物

准备发布 Skills 分发物时，在完成相关本地检查后运行：

```bash
./scripts/package-skills.sh
```

该命令生成被 Git 忽略的 `dist/*.zip`；它不会上传产物、创建发布或修改版本号。普通 PR、文档修改和日常治理脚本修改不需要为了打包而重复执行此命令。

Pull request 应说明行为变化、风险、验证结果和未执行的检查。治理敏感路径不能由自动 fixer 修改或自动合并。
