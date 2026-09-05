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

### 准备发布分发物

准备发布 Skills 分发物时，在完成相关本地检查后运行：

```bash
./scripts/package-skills.sh
```

该命令生成被 Git 忽略的 `dist/*.zip`；它不会上传产物、创建发布或修改版本号。普通 PR、文档修改和日常治理脚本修改不需要为了打包而重复执行此命令。

Pull request 应说明行为变化、风险、验证结果和未执行的检查。治理敏感路径不能由自动 fixer 修改或自动合并。
