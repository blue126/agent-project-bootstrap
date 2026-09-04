# Backlog

## Adopt an existing project

**Status:** Proposed

为已有 brownfield 项目提供独立的 adoption 流程，使其安全采用本项目的
Agent policy、GitHub `origin/main`、branch/worktree 和 Pull Request 工作流。

该能力与新项目 bootstrap 分离：`bootstrap.sh` 继续负责可控初始状态下的
确定性初始化；adoption 负责分析和增量迁移已有项目。

### Scope

- 提供独立入口，例如 `scripts/adopt.sh`。
- 提供可交给 Coding Agent 执行的 brownfield migration prompt；当前草案见
  [`prompts/adopt-github-workflow.md`](prompts/adopt-github-workflow.md)。
- 只读检查现有 Agent 文件、Git 状态、remote、默认分支、worktree、CI 和验证命令。
- 增量合并现有 `AGENTS.md`、`CLAUDE.md` 和项目规则，禁止覆盖或削弱原有约束。
- 允许选择或创建与项目目录同名的 GitHub repository；OWNER 必须经过验证。
- 使用独立 branch/worktree 提交 Draft PR；Agent 不得 merge、force push 或清理用户改动。
- 将部署、发布和其他有副作用的 CI 与 PR validation 分开处理。

### Non-goals

- 不把 brownfield adoption 作为 `bootstrap.sh` 的隐式模式。
- 不用确定性 shell 脚本自动合并已有项目规则或修改 CI。
- 不自动替换 remote、重写 Git history、改名默认分支或配置 GitHub 权限。

### Acceptance criteria

- 新项目 bootstrap 的现有行为保持不变。
- Adoption 必须由用户显式选择，并一次只处理一个项目。
- 已有项目文件和未提交改动默认得到保留。
- 缺少或冲突的 GitHub/Git 信息会形成明确停止条件，而不是被猜测。
- 成功路径停在经过验证的 Draft PR，并列出仍需人工完成的 GitHub 步骤。
