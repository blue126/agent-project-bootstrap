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

```bash
shellcheck -S style scripts/*.sh tests/*.sh
bash -n scripts/*.sh tests/*.sh
./scripts/check-third-party-inventory.sh
for test_file in tests/test-*.sh; do bash "${test_file}"; done
```

Pull request 应说明行为变化、风险、验证结果和未执行的检查。治理敏感路径不能由自动 fixer 修改或自动合并。
