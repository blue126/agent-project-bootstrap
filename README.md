# Agent Project Bootstrap

面向公共协作的 Agent 项目 bootstrap：为新项目提供跨 Agent policy、模板、显式 workflow 选择，以及保持交互的 Skills 安装。项目自身代码使用 MIT 许可证；bundled third-party 内容保留各自许可证，详见 `THIRD_PARTY_NOTICES.md`。

支持的目标 Agent：

| Agent | 项目级路径 | 用户级路径 |
|---|---|---|
| `codex` | `.agents/skills/` | `~/.codex/skills` |
| `opencode` | `.agents/skills/` | `~/.config/opencode/skills` |
| `claude-code` | `.claude/skills/` | `~/.claude/skills` |

## 安装 Skills

从 public repository 交互安装：

```bash
npx skills add https://github.com/blue126/agent-project-bootstrap
```

开发本仓库时也可从**本地 checkout** 安装：

```bash
npx skills@1.5.23 add /absolute/path/to/agent-project-bootstrap          # 交互选择
npx skills@1.5.23 add /absolute/path/to/agent-project-bootstrap --list   # 只看清单
```

安装器会交互选择 Skill、目标 Agent 和复制/链接方式。除非明确要求，不要使用 `--all`、`-y` 或 `-g`。

把全部 bundled Skills 链到用户级目录：

```bash
./scripts/link-skills.sh                 # 默认 codex + opencode
./scripts/link-skills.sh --agent claude  # 只链 Claude Code
```

## 初始化项目

推荐让用户直接运行交互式命令，不要由 Agent 在聊天中重做一份配置问卷：

```bash
/absolute/path/to/agent-project-bootstrap/scripts/bootstrap.sh --target "$PWD"
```

该命令必须由用户本人在 Terminal.app、iTerm 等普通终端中运行。Agent 进程不能代跑，也不能通过清除 `AI_AGENT` / `CODEX_*` 变量伪造交互环境——`skills` CLI 会检测 Agent 环境并可能退化为非交互安装。

标准流程：

1. 可选进入 Curated Skills 选择器，挑选能力和目标 Agent；`github-workflow` 也在这个目录中。
2. 选择是否为当前项目安装 pinned Understand Anything（只写入项目内）。
3. 激活一个 workflow：`none`、`github-workflow`、`superpowers` 三选一。
4. 只有选择 `superpowers` 时，才进入 pinned Superpowers workflow pack 选择器。

脚本不覆盖已有 policy/template，不假设 Git 或 `origin` 已存在；只有显式传入 `--init-git` 才初始化本地仓库（分支为 `main`）。

初始化后的 governance 状态默认为 `validation: pending`、`auto_merge: disabled`。这允许后续只读 review，但不会生成永远成功的 validator；项目必须显式配置并同步真实 validation adapter 后才能进入 shadow/enforced gates。

项目准备好自己的 adapter manifest 后，可显式绑定并先进入 shadow：

```bash
./scripts/configure-validation.sh \
  --project /path/to/project \
  --manifest .agent/validation/adapter.json \
  --mode shadow
```

公共 runtime 只定义 adapter/review/result schema 与受信 runner，不捆绑 Node、Python、IaC 或其他技术栈实现。`check-governance-readiness.sh` 对 pending、missing、stale 或 SHA mismatch 一律 fail closed。

只有当用户已在自己的请求中明确给出选择时，才能使用非交互参数：

```bash
./scripts/bootstrap.sh --target /path/to/project \
  --workflow github-workflow --skip-skills --skip-understand-anything
```

`--install-skills` 和 `--install-superpowers` 在非 TTY 环境会拒绝执行，避免安装器退化为自动批量安装。启动 Superpowers 前，脚本会把 tag 解引用并验证其仍等于 manifest 中的 known-good commit；tag 漂移或缺失时拒绝安装。

## 升级已 bootstrap 的项目

Bootstrap 会把它写入的每个文件的哈希记进目标项目的 `.agent/bootstrap.yml`。`--update` 只替换仍与该哈希一致的文件（你没动过的），你改过的一律保留并列出：

```bash
/absolute/path/to/agent-project-bootstrap/scripts/bootstrap.sh --target "$PWD" --update
```

不需要重复传 `--workflow` 等参数——它们从 `.agent/bootstrap.yml` 回放。`--update` 不重新运行任何安装器。确实要覆盖自己的修改时加 `--force`。

## 新机器上恢复本地产物

已安装的 Skills 和 integration runtime 不入库（由 `.agent/runtime/.gitignore` 和 `.agents/skills/.gitignore` 排除）。clone 之后：

```bash
/absolute/path/to/agent-project-bootstrap/scripts/rehydrate.sh --target "$PWD"
```

它按记录重装 Understand Anything，并打印需要你在终端亲自运行的交互式 Skill 安装命令。

## 创建 GitHub repository

创建远端是独立的显式操作，必须同时指定完整目标和可见性：

```bash
./scripts/bootstrap.sh --target /path/to/project \
  --workflow github-workflow --skip-skills \
  --create-github --github-repo owner/repository --github-visibility private
```

它会初始化本地 Git（如有需要），**只**暂存 bootstrap 管理的文件，创建 `Initialize Agent project` 提交，通过已登录的 `gh` 创建 repository、配置 `origin` 并推送 `main`。发布发生在安装步骤之前：Skills 和 runtime 是本地产物，不进入提交。

已有 `origin`、非 `main` 分支、已有 staged 内容，或 bootstrap 文件之外仍有未提交内容时会拒绝执行。

## 配置 GitHub main 保护

在远端仓库和 `main` 已存在后：

```bash
./scripts/bootstrap.sh --target /path/to/project --configure-github --github-repo owner/repository
./scripts/configure-github.sh --repo owner/repository   # 也可独立重试
```

幂等创建或更新 repository-level `Protect main` Ruleset：Active、空 bypass list、精确匹配 `refs/heads/main`、禁止删除、要求通过 PR 合并、Required approvals 为 0、禁止 force push。脚本不会从 `origin` 猜测仓库；它要求显式目标、已登录的 `gh`、`jq`、现存的 `main`，以及编辑仓库规则的权限（完整 admin 非必需）。

## Policy 模型

- `AGENTS.md`：项目内唯一的跨 Agent policy source。
- `CLAUDE.md`：引用 `AGENTS.md`，只存放 Claude-specific guidance。
- `.agent/policies/`：由 `policies/` 模板初始化的共享规则。
- `.agent/bootstrap.yml`：记录 workflow 选择、managed integration lock 和 managed-file 哈希。

`github-workflow` 和 Superpowers 都是 opt-in 且互斥；安装不等于启用。如果同时被请求，Agent 必须停止 workflow 执行并让用户二选一。

## Managed integrations

**Understand Anything**：固定 `v2.9.0` / immutable commit checkout 放到 `.agent/runtime/understand-anything/repo`，应用项目路径兼容与 Git revision hardening 补丁，在 `.agents/skills/` 创建相对链接。不写入 `~/.agents/skills`、`~/.codex/skills`、`~/.understand-anything` 等用户级目录。只应用于可信代码库；升级必须重新完成安全和项目级兼容验证。

**Superpowers**：`obra/superpowers` 是 managed upstream integration，不 fork、不复制源码。`integrations/superpowers/integration.yml` 固定 known-good tag 与 immutable commit。更新策略是追踪最新稳定 release、完成兼容性验证后通过 PR 手动提升 pin。

两个 workflow pack 同时安装属于高级用法，只有用户明确提出时才使用 `--install-superpowers`；同一任务仍只能激活一个 workflow。

现有第三方 Skills 由 `third-party-sources.yml` 记录来源、许可与本地修改；新 managed integrations 使用 `integrations/<name>/integration.yml`。

`human-3-development-assessor` 的上游未声明许可证，因此不在 public repository 中捆绑、复制、patch、自动下载或一键安装。Catalog 仅提供 `Visit upstream` 记录，由用户自行满足上游访问和许可条件。

## 维护与验证

贡献或维护此仓库时，请参阅[贡献指南的“验证”章节](CONTRIBUTING.md#验证)，按改动范围选择本地检查，了解 CI 对推送提交的独立验证，并在准备发布分发物时执行打包步骤。

不要提交个人数据、对话转录、生成报告、凭据、`.env`、证书或私钥。
