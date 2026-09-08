# Agent Project Bootstrap

[English](README.md) | **简体中文**

**为你的项目准备一套可以开始工作的 Agent 开发环境。**

选择 Agent 客户端、工作流和 Skills，建立项目规范与本地 Git，然后在所选客户端开始第一个任务。新项目和已有项目都可使用；已有配置会保留，必要变更先说明，**不自动提交或推送**。GitHub、CI 和自动审查是后续可选能力，不是本地开工的前置条件。

**第一次使用？从下面的「快速开始」走完整流程。** 只想添加几个技能、不需要项目初始化时，再看[只安装 Skills](#只想安装-skills)。

## 快速开始：初始化项目

使用 macOS/Linux 的普通终端。基础向导需要 **Bash、Git、jq、Python 3.9+**；选择安装 Skills/工作流时还需要相应的 Node.js/npm/npx 环境。GitHub 续程才需要已登录的 `gh`。缺少依赖会明确停止或提示，不会自动安装到你的全局环境。

请由你本人在 Terminal.app、iTerm 等终端运行。不要让 Agent 用工具 PTY 代跑真实安装器，也不要清除 `AI_AGENT`、`CLAUDECODE`、`CODEX_*` 等检测变量来绕过限制。

### 1. 获取 bootstrap 工具

以下示例把**工具仓库**放在你的主目录下；这一步只是下载工具，还没有初始化你的项目：

```bash
git clone https://github.com/blue126/agent-project-bootstrap.git "$HOME/agent-project-bootstrap"
```

如果这个目录已经存在，先确认它是不是你原有的工具 checkout；可以直接复用，不要覆盖或删除。若工具放在其他位置，后面把启动脚本的路径换成它的实际位置即可。

### 2. 进入你自己的项目目录

**新项目**可以先建一个空目录。`my-agent-project` 是示例项目名，可以换成你想用的名称；如果目录已存在，按已有项目处理，不要清空它：

```bash
mkdir "$HOME/my-agent-project"
```

```bash
cd "$HOME/my-agent-project"
```

**已有项目**不需要新建目录，只需进入它的项目根目录；把下面的路径替换成你的真实项目路径：

```bash
cd "/path/to/your/project"
```

> **工具目录和项目目录不是一回事。** 不要因为刚下载了工具，就在 `agent-project-bootstrap` 仓库里启动初始化。先进入真正要开发的项目；已有 Git 项目应进入 Git 根目录，不是其中的子目录。

### 3. 在当前项目启动向导

```bash
"$HOME/agent-project-bootstrap/scripts/bootstrap.sh"
```

**无需传目录参数：默认目标就是当前工作目录。** 开场会显示目标项目的实际路径，先核对它，再选择开始。这里只运行位于工具仓库里的脚本，不会把当前目录切换回工具仓库。

向导需要真人交互终端；客户端多选使用方向键、空格和 Enter，`q` 可取消。原生 Skills 安装器保留搜索、多选、安装作用域和复制/链接选择，推荐项目级 `Project`。不使用 `--all`、`-y` 或 `-g` 替你省略这些决定。

### 4. 完成后开始工作

向导会显示客户端、工作方式、实际 Skill 入口、项目规则与 Git 状态，以及第一个任务的起步指引。

在**所选客户端的新会话**中打开这个项目，先确认 Agent 读取到项目规则和 Skills，再授权第一项开发任务。文件安装成功不等于客户端已经加载；尚未提交的资产也会明确标为只在本地。第一次提交仍需审阅文件范围与敏感信息。

不需要 GitHub 时，在最后选择结束即可。以后想添加客户端、Skills 或协作能力，在同一项目目录重新运行上面的命令；已有内容重新检查，不恢复某个“做到第几题”的隐藏进度。

## 向导中会发生什么

| 阶段 | 你要决定什么 | 项目会得到什么 |
|---|---|---|
| 1. Agent 客户端 | Claude Code、Codex、OpenCode 或 Universal，可多选 | 明确的项目安装目标；已有记录只预选，不替你确认 |
| 2. 工作方式 | 保留现有方法，或明确采用 github-workflow、Superpowers、BMAD | 一套选定的方法；检测或安装不自动执行任务 |
| 3. Skills 与可选能力 | 安装工作流所需内容、添加普通 Skills、可选 Understand Anything | 客户端可发现的项目入口；已有 Skill 也能继续添加 |
| 4. 项目规范与本地 Git | 确认必要配置、忽略规则差异，以及是否初始化本地 Git | 共享 Agent 规范、Git 资产政策和本地仓库；不提交、不推送 |
| 5. 本地总结 | 核对就绪和待处理项，决定是否继续 GitHub | 首个任务指引；无需先配置 CI 才能结束基础流程 |

开场 `i` 可以查看完整的 **检查 / 可能改变 / 不会** 说明。说明页不启动安装或写入项目。`NO_COLOR`、窄终端和 `TERM=dumb` 提供可读回退，但不会让非交互 Agent 进程变成人类终端。目前向导提示使用中文；切换 README 语言不会改变终端界面语言。

- **客户端选择每次都出现**。后续 Skills 调用复用你选择的 `--agent`，原生 scope/method/确认仍可能按每次安装分别出现。当前 `skills@1.5.23 add` 没有 `--project` 参数；不能靠 `-y/--all` 强行隐藏提问。选择 Global 不代表项目入口就绪。
- **工作流只采用一种**。`github-workflow` 适合 Git 分支/审阅与之后的 GitHub 协作；Superpowers 适合功能设计、实现和验证；BMAD 适合需求、架构和系统性迭代。保留现有方法不会停用未知规则，也不要求你为未知框架分类。
- **Understand Anything 可跳过**。已有代码库（brownfield）通常更能受益，空项目（greenfield）可以等有代码后再用。它安装固定版本 runtime 和项目链接，不装全局插件、不自动分析；后续分析可能产生模型费用。
- **先本地、后协作**。本地总结后才询问 GitHub；拒绝后没有 CI/Review/Ruleset 问卷。即使已有 GitHub origin，此前也不调用 `gh` 访问它。

客户端路径与兼容范围：

| 客户端/模式 | 项目 Skill 路径 | 说明 |
|---|---|---|
| Claude Code | `.claude/skills/` | 通过 `CLAUDE.md` 引用共享 `AGENTS.md` |
| Codex | `.agents/skills/` | 使用项目共享 Skill 目录 |
| OpenCode | `.agents/skills/` | BMAD 还需 `.opencode/commands` pointers |
| Universal | `.agents/skills/` | 共享目录模式，不是客户端应用，也不是安装全部客户端；BMAD 6.12.0 不支持此 tool ID |

更多交互和已有项目说明见[起步指南](examples/onboarding.md)。

## 只想安装 Skills？

**这是独立的 Skills-only 入口，不会建立完整的项目规范或 Git 环境。** 如果想 bootstrap 一个项目，使用上面的[快速开始](#快速开始初始化项目)。

先进入希望安装 Skills 的项目，再运行：

```bash
npx skills add https://github.com/blue126/agent-project-bootstrap
```

不必先 clone 工具仓库。原生安装器负责 Skill、客户端、作用域和安装方式；它可能根据环境省略不适用的问题。不要把 Skills 安装结束当成整个项目初始化完成。

<details>
<summary>维护者：从本地 checkout 安装、列出或链接 Skills</summary>

以下假设工具已按快速开始下载到主目录。安装仍从目标项目运行：

```bash
npx skills@1.5.23 add "$HOME/agent-project-bootstrap"
```

```bash
npx skills@1.5.23 add "$HOME/agent-project-bootstrap" --list
```

只有明确要创建用户级链接时才使用下面的工具；它不是默认项目 bootstrap 路径：

```bash
"$HOME/agent-project-bootstrap/scripts/link-skills.sh"
```

```bash
"$HOME/agent-project-bootstrap/scripts/link-skills.sh" --agent claude
```

</details>

## 更新与恢复

### 升级已 bootstrap 的项目

仍然先进入目标项目目录。只刷新没有被你修改过的受管文件：

```bash
"$HOME/agent-project-bootstrap/scripts/bootstrap.sh" --update
```

Bootstrap 在目标 `.agent/bootstrap.yml` 记录受管文件哈希。你修改过的文件会保留并列出；客户端偏好、现有选择与未知 metadata 也保留。`--update` 不重跑安装器，不开始向导，不授权 Git 或远端操作。需要覆盖自己的修改时，先看 diff，再由用户明确决定是否使用 `--force`；它也不会悄悄打开旧 Skills 的忽略边界。

### 新机器上恢复本地产物

项目自有/定制 Skills 应经审阅提交；第三方内容可以按许可选择提交，或通过固定版本、可验证的流程复现。不是所有已安装 Skills 都属于应忽略的临时产物。

获取工具、clone 你的项目并进入项目目录后：

```bash
"$HOME/agent-project-bootstrap/scripts/rehydrate.sh"
```

工具按记录重建可恢复的 Understand Anything runtime/客户端入口，打印需要你在普通终端执行的 Skills/Superpowers 命令，并如实列出 BMAD 等人工待办。安装事实、版本来源和新会话加载不能仅凭一条安装记录推断。

## 下游项目的版本控制规范

`policies/git.md` 会分发为下游 `.agent/policies/git.md`，由项目 `AGENTS.md` 要求 Agent 在初始化、暂存、提交、修改忽略规则或清理前读取；无需另装一个 Skill。

- **项目能力进 Git**：共享配置、Skills、agents、commands、hooks、工作流、依赖锁文件，以及正式需求/设计/研究/脱敏验证记录。提交前检查敏感信息、可移植性和许可；共享自动化按代码审查。
- **个人状态留本机**：凭据、个人覆盖、会话、缓存和嵌套 worktree。runtime 使用局部忽略规则，已确认可重建的链接按精确路径提出排除建议。
- **已有规则保留**：缺少根 `.gitignore` 时生成最小规则；已有文件只追加经确认的内容。过宽规则遮蔽资产时报告，不自动删除规则或取消跟踪；`.gitignore` 不是敏感信息扫描器。
- **旧 Skills 边界另行迁移**：`--update`（包括 `--force`）保留已有不同内容的 Skills 忽略文件。向导单独显示旧整目录忽略的迁移及受影响候选，再确认应用；自定义内容不自动迁移。
- **验收分开**：政策安装、规则应用、客户端加载、首次提交验证和远端发布是不同状态。完整政策见 [Git 政策](policies/git.md)。

<details>
<summary>高级：单独预览或应用忽略规则</summary>

```bash
python3 "$HOME/agent-project-bootstrap/scripts/configure-git-ignore.py" --project "$PWD"
```

确认精确 diff 后，用输出的 snapshot token 替换 `TOKEN` 才能应用。过期快照会拒绝写入：

```bash
python3 "$HOME/agent-project-bootstrap/scripts/configure-git-ignore.py" --project "$PWD" --apply --expect TOKEN
```

旧 Skills 迁移须在预览和应用两步都显式加 `--migrate-skills`。这个专用 helper 的 `--project` 不同于主向导可省略的 `--target`。

</details>

## 可选 GitHub 协作

基础总结之后可以继续创建/连接 GitHub，再按需要准备本地验证、CI、自动审查和合并保护。没有远端分支或真实证据时保留 pending/blocked，不用“成功”占位符替代测试。

Claude Auto Review 需要用户在项目的 Claude Code 会话运行官方 `/install-github-app`。选择引导不授权 Agent 安装 App、设置认证/secret、启用自动合并或批准代码。治理敏感改动由人工处理。

已有审查结果时，输入明确的 PR 编号验证当前版本的 bot 反馈，验证通过后可继续保护步骤，不会反复要求安装。这个结果只证明自动审查反馈可用，不代表合并批准，也不证明反馈来自特定 Claude App；没有 PR 时可选择查看安装指引或暂不验证。

如果用户明确请求项目 Agent 协助准备验证，才在 `.agent/runtime/onboarding/` 生成结构化 handoff。它是任务文件，不是 resume 状态或执行授权；完成外部工作后重新运行主入口，根据实际证据继续。

### 创建 GitHub repository

默认向导只创建或连接，不发布代码。需要单独调用底层工具时，明确项目与仓库：

```bash
"$HOME/agent-project-bootstrap/scripts/create-github.sh" --source "$PWD" --repo owner/repository --visibility private --create-only
```

```bash
"$HOME/agent-project-bootstrap/scripts/create-github.sh" --source "$PWD" --repo owner/existing-repository --attach-only
```

两种模式都不暂存、不提交、不推送，不替换冲突的 `origin`。仓库名、创建可见性和实际操作要明确确认；之后发布代码仍需独立授权。

### 配置 GitHub main 保护

在项目远端与分支已存在，且已授权这一远端变更时：

```bash
"$HOME/agent-project-bootstrap/scripts/configure-github.sh" --repo owner/repository
```

幂等配置 Protect main 基础 Ruleset，要求 PR、解决审查线程并采用 squash，不要求正数审批票。项目 CI gates 基于下游自己的实际 evidence；本仓库的 self profile 不是下游默认设置。初始 governance 为 `validation: pending`、`auto_merge: disabled`，不会默认开启自动合并。

<details>
<summary>高级：显式参数、其他目标目录与旧发布入口</summary>

**只有操作当前目录之外的项目，才需要主入口的 `--target`：**

```bash
"$HOME/agent-project-bootstrap/scripts/bootstrap.sh" --target "/path/to/another/project"
```

只有用户已经明确给出全部选择时，才使用有界参数入口；Agent 不应为绕过交互而索要配置字符串：

```bash
"$HOME/agent-project-bootstrap/scripts/bootstrap.sh" --workflow github-workflow --skip-skills --skip-understand-anything --skip-claude-auto-review
```

`--install-skills` / `--install-superpowers` 要求真实交互终端，Superpowers 安装前验证固定 tag 对应 known-good commit。明确配置项目 adapter 时，使用项目自己的验证入口；公共 runtime 不捆绑技术栈适配器，也不接受口头结果替代 evidence：

```bash
"$HOME/agent-project-bootstrap/scripts/configure-validation.sh" --project "$PWD" --manifest .agent/validation/adapter.json --mode shadow
```

**旧发布模式会创建提交并上传代码，不是基础向导。** 仅在用户明确授权这些行为、审阅文件范围并完成发布前检查后才使用：

```bash
"$HOME/agent-project-bootstrap/scripts/bootstrap.sh" --workflow github-workflow --skip-skills --skip-understand-anything --skip-claude-auto-review --create-github --github-repo owner/repository --github-visibility private
```

它仅自动暂存 bootstrap 骨架（含已审阅的根 `.gitignore`），拒绝未审阅的其他改动或已有暂存内容。发布前用临时 index 检查候选树，拒绝不安全链接/嵌套仓库、超过 10 MiB 的当前文件以及无效 JSON/YAML/TOML/Shell 语法；YAML 需 PyYAML，TOML 需 Python 3.11+。本地 Gitleaks 8.19+ 必须扫描候选内容及已有 main 历史；缺扫描器、浅历史、扫描失败均停止，不自动安装依赖。

不允许通过项目 ignore/allow 注释静默缩减该扫描；活动 hooks 需走项目正常发布路径，不为了发布绕过 hooks。检查失败不改变真实 index，检查通过也不等于证明不存在秘密或完成应用 schema/业务验证。

</details>

## 项目结构与维护

- `AGENTS.md` 是共享政策入口；选择 Claude 时用 `CLAUDE.md` 引用它。
- `.agent/policies/` 放下游项目规范，`.agent/bootstrap.yml` 记录明确偏好、受管文件哈希与可验证的安装信息，不存向导进度或授权。
- Understand Anything 使用固定 `v2.9.0` / immutable ref 的项目 runtime 和兼容补丁；Superpowers 使用受管的 `v6.3.0` / immutable ref；BMAD 安装和工作流执行分开。
- 其他第三方来源、许可和定制见 `third-party-sources.yml`；受管集成见 `integrations/`。`human-3-development-assessor` 无上游许可证，只提供 `Visit upstream`，不捆绑、复制、patch、自动下载或一键安装。

本仓库是工具分发源码，不代表本 checkout 已安装或启用了组件。自身代码使用 MIT；bundled third-party 内容保留原许可证，见 [第三方声明](THIRD_PARTY_NOTICES.md)。维护、测试与打包见[贡献指南](CONTRIBUTING.md)。不要提交凭据、个人状态或私密转录；正式项目报告应经审阅、脱敏和许可检查后保留。
