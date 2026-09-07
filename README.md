# Agent Project Bootstrap

面向公共协作的 Agent 项目 bootstrap：为新项目或已有代码库提供可恢复的引导式初始化、跨 Agent policy、模板和显式组件安装。这里是分发源码，不代表当前 checkout 已安装或启用了这些组件。项目自身代码使用 MIT 许可证；bundled third-party 内容保留各自许可证，详见 `THIRD_PARTY_NOTICES.md`。

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

只传 `--target` 就会进入 onboarding，不需要先整理一串参数。向导需要 Bash、Git、jq 和 Python 3.9+；GitHub 阶段另需已登录的 `gh`，组件安装按各自要求使用 Node/npx。缺依赖会明确提示，不自动安装到全局环境。

开场先显示六张 `[n/6]` 总览卡片；输入 `i` 可打开完整说明页。详情页对每个阶段分别解释 **检查 / 可能改变 / 不会**，按 Enter 返回开始菜单。说明页纯展示，不启动安装或写入项目。流程再逐步选择：

**完整向导只在真实交互终端运行；重定向输出不会进入纯文本 wizard。** 颜色不可用时，编号、标题、标签、缩进和空行仍保留全部含义。

1. **认识项目与 workflow**：只检测 `github-workflow`、`superpowers`、`bmad`。发现已有 workflow 就保留，不激活、不重装、不覆盖；没有发现时，选择安装其中一个或“不安装”。不要求你给未知规则贴上 custom 标签，跳过也不会停用它们。
2. **普通 Skills**：独立选择能力和目标 Agent，选择后立即安装，而不是留到所有问题结束后。安装 workflow 与启用 workflow 是两回事，bootstrap 不会同时激活多个框架。
3. **Understand Anything**：可选、仅限当前项目。已有代码库可用它建立理解代码的地图；空项目可以先跳过，等有代码后再用。安装不等于已经分析代码或生成知识图谱。
4. **Policy 与 Git/GitHub**：保留已有指令，选择是否初始化本地 Git、创建或连接明确的远端。引导模式只创建/连接，**不暂存、不提交、不推送**。
5. **验证与保护**：区分本地检查、远端 CI、review 与分支保护；需要远端授权的操作会单独说明。缺少远端分支或证据时显示下一步，不假装已验证。最后汇总本次实际验证与本次未选择的能力。

向导不保存“做到第几题”的进度。中断、退出或外部操作完成后，直接重新运行同一条命令；它会重新检查真实项目状态，保留已有配置，并再次提供尚未配置的能力。空输入和格式错误只会在当前问题重试，不会永久跳过 GitHub、CI 或其他阶段。

连接 GitHub 后，Claude Auto Review 是可选接续任务：用户在项目会话完成官方 `/install-github-app`，然后重新运行 bootstrap，向导会核实实际审查反馈。选择引导不安装 GitHub App、Claude Code Action、认证或 secret，也不创建 workflow、启用 AI gate、Auto Fixer 或 Auto Merge。已声明的安装和审查反馈均不代表代码获得合并批准。

当本地验证需要项目 Agent 协助时，用户明确选择后会在已忽略的 `.agent/runtime/onboarding/` 得到一份结构化任务文件。它只列出受限的文件/配置事实、交付物和授权边界；不是向导进度，也不会让下一次 bootstrap 跳过验证。Agent 完成调查或实际验证后，重新运行同一 bootstrap 命令即可重新检查结果。

脚本不覆盖已有 policy/template，不假设 Git 或 `origin` 已存在，不会凭空补造远端。新手可继续阅读[简明 onboarding 指南](examples/onboarding.md)。

初始化后的 governance 状态默认为 `validation: pending`、`auto_merge: disabled`。这允许后续只读 review，但不会生成永远成功的 validator；项目必须显式配置并同步真实 validation adapter 后才能进入 shadow/enforced gates。

项目准备好自己的 adapter manifest 后，可显式绑定并先进入 shadow：

```bash
./scripts/configure-validation.sh \
  --project /path/to/project \
  --manifest .agent/validation/adapter.json \
  --mode shadow
```

公共 runtime 只定义 adapter/review/result schema 与受信 runner，不捆绑 Node、Python、IaC 或其他技术栈实现。`check-governance-readiness.sh` 对 pending、missing、stale 或 SHA mismatch 一律 fail closed。

### 保留的显式参数入口

只有当用户已在自己的请求中明确给出选择时，才能使用旧的有界参数入口；它不是默认 wizard，也不能让 Agent 为绕过交互而索要一串配置：

```bash
./scripts/bootstrap.sh --target /path/to/project \
  --workflow github-workflow --skip-skills --skip-understand-anything \
  --skip-claude-auto-review
```

非交互的 `github-workflow` bootstrap 必须使用 `--select-claude-auto-review` 或 `--skip-claude-auto-review` 之一明确选择。

`--install-skills` 和 `--install-superpowers` 在非 TTY 环境会拒绝执行，避免安装器退化为自动批量安装。启动 Superpowers 前，脚本会把 tag 解引用并验证其仍等于 manifest 中的 known-good commit；tag 漂移或缺失时拒绝安装。

## 升级已 bootstrap 的项目

Bootstrap 会把它写入的每个文件的哈希记进目标项目的 `.agent/bootstrap.yml`。`--update` 只替换仍与该哈希一致的文件（你没动过的），你改过的一律保留并列出：

```bash
/absolute/path/to/agent-project-bootstrap/scripts/bootstrap.sh --target "$PWD" --update
```

不需要重复传 `--workflow` 等参数——现有选择与 metadata 会保留。`--update` 不重新运行任何安装器，拒绝混用安装或 Git mutation 参数，也不重新开始 onboarding。若确实需要覆盖自己的修改，先检查差异，再由用户明确决定是否使用 `--force`；Agent 不得自行用它解决冲突。

## 新机器上恢复本地产物

已安装的 Skills 和 integration runtime 不入库（由 `.agent/runtime/.gitignore` 和 `.agents/skills/.gitignore` 排除）。clone 之后：

```bash
/absolute/path/to/agent-project-bootstrap/scripts/rehydrate.sh --target "$PWD"
```

它按记录重装 Understand Anything，并打印需要你在终端亲自运行的交互式 Skill 安装命令。

## 创建 GitHub repository

默认 onboarding 的 Git/GitHub 阶段只负责创建或连接，不发布代码。底层对应以下显式模式（先看 `scripts/create-github.sh --help`）：

```bash
./scripts/create-github.sh --source /path/to/project \
  --repo owner/repository --visibility private --create-only
```

```bash
./scripts/create-github.sh --source /path/to/project \
  --repo owner/existing-repository --attach-only
```

创建必须明确指定 `OWNER/REPOSITORY` 和可见性；连接必须明确指定现存目标。二者都不暂存、不创建提交、不推送，也不覆盖一个冲突的 `origin`。没有已发布分支时，CI 或保护验证可能仍然阻塞；之后发布代码需要独立授权。

**旧的发布模式仍保留，不能与上述模式混淆。** 只有用户明确要求创建提交并推送时，才使用：

```bash
./scripts/bootstrap.sh --target /path/to/project \
  --workflow github-workflow --skip-skills --skip-understand-anything \
  --skip-claude-auto-review \
  --create-github --github-repo owner/repository --github-visibility private
```

这个旧入口会初始化本地 Git（如有需要），只暂存 bootstrap 管理的文件，创建 `Initialize Agent project` 提交，通过已登录的 `gh` 创建 repository、配置 `origin` 并推送 `main`。Skills 和 runtime 是本地产物，不进入该提交。已有 `origin`、非 `main` 分支、已有 staged 内容，或 bootstrap 文件之外仍有未提交内容时会拒绝执行。

## 配置 GitHub main 保护

在远端仓库和 `main` 已存在后：

```bash
./scripts/configure-github.sh --repo owner/repository
```

幂等创建或更新 repository-level `Protect main` Ruleset：Active、空 bypass list、精确匹配 `refs/heads/main`、禁止删除、要求通过 PR 合并、Required approvals 为 0、禁止 force push。脚本不会从 `origin` 猜测仓库；它要求显式目标、已登录的 `gh`、`jq`、现存的 `main`，以及编辑仓库规则的权限（完整 admin 非必需）。

## Policy 模型

- `AGENTS.md`：项目内唯一的跨 Agent policy source。
- `CLAUDE.md`：引用 `AGENTS.md`，只存放 Claude-specific guidance。
- `.agent/policies/`：由 `policies/` 模板初始化的共享规则。
- `.agent/bootstrap.yml`：记录 workflow 选择、managed integration lock 和 managed-file 哈希。

`github-workflow`、`superpowers` 和 `bmad` 都是 opt-in，单个任务的激活模式互斥；检测到或安装了组件不等于启用。请求执行多个框架时，Agent 必须停止并让用户选择一个。`none` 表示没有选中这些已知 workflow，不代表删除或停用项目已有的未知规则。

## Managed integrations

**Understand Anything**：固定 `v2.9.0` / immutable commit checkout 放到 `.agent/runtime/understand-anything/repo`，应用项目路径兼容与 Git revision hardening 补丁，在 `.agents/skills/` 创建相对链接。不写入 `~/.agents/skills`、`~/.codex/skills`、`~/.understand-anything` 等用户级目录。只应用于可信代码库；升级必须重新完成安全和项目级兼容验证。

**Superpowers**：`obra/superpowers` 是 managed upstream integration，不 fork、不复制源码。`integrations/superpowers/integration.yml` 固定 known-good tag 与 immutable commit。更新策略是追踪最新稳定 release、完成兼容性验证后通过 PR 手动提升 pin。

**BMAD**：`bmad` 是已知 workflow 选项；安装方式和检查结果由对应安装入口说明。安装 BMAD 不会自动运行它的分析、规划或开发流程。

默认 wizard 不并行安装多个 workflow pack。已有 pack 会保留；需要额外安装其他 pack 的高级用法必须另行明确提出，同一任务仍只能激活一个 workflow。

现有第三方 Skills 由 `third-party-sources.yml` 记录来源、许可与本地修改；新 managed integrations 使用 `integrations/<name>/integration.yml`。

`human-3-development-assessor` 的上游未声明许可证，因此不在 public repository 中捆绑、复制、patch、自动下载或一键安装。Catalog 仅提供 `Visit upstream` 记录，由用户自行满足上游访问和许可条件。

## 维护与验证

贡献或维护此仓库时，请参阅[贡献指南的“验证”章节](CONTRIBUTING.md#验证)，按改动范围选择本地检查，了解 CI 对推送提交的独立验证，并在准备发布分发物时执行打包步骤。

不要提交个人数据、对话转录、生成报告、凭据、`.env`、证书或私钥。
