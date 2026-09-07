# 从这里开始

Bootstrap 为项目放好 Agent 共享规则，并按你的选择安装能力、连接 GitHub 和检查准备情况。**它不是开始开发，也不会因为发现某个 workflow 就运行它。** 本仓库是分发源码；看到组件目录不等于组件已在你的项目安装。

## 一个入口，随时重新检查（无状态向导）

先进入你要初始化的项目目录，在 Terminal.app、iTerm 等普通终端亲自运行：

```bash
/absolute/path/to/agent-project-bootstrap/scripts/bootstrap.sh --target "$PWD"
```

不要让 Agent 代跑交互安装、开一个工具 PTY 冒充你的终端，或清除 `AI_AGENT` / `CODEX_*` 变量。没有明确要求时，也不要加 `--all`、`-y`、`-g` 来批量或全局安装。

中断、退出、输入错误或完成外部步骤后，重新运行同一条命令：

```bash
/absolute/path/to/agent-project-bootstrap/scripts/bootstrap.sh --target "$PWD"
```

向导不保存“做到第几题”的进度。它每次检查真实文件、Git、origin、CI、审查和保护状态：已有配置保留，尚未配置的能力再次提供选择。项目内 `.agent/bootstrap.yml` 仍记录受管文件和明确配置，但不记录向导光标、临时输入或授权。空输入不会永久跳过阶段。

当你明确选择“让项目 Agent 协助”时，向导会在已忽略的 `.agent/runtime/onboarding/` 写入一份阶段任务 Markdown。它列出受限事实扫描、Agent 交付物、授权边界和实际 evidence 要求；它不是 resume 状态，重跑 bootstrap 时不会让向导跳过任何阶段。Agent 完成工作后，重新运行同一命令，让向导重新检查真实结果。

## 先看总览，再看详情

开场页会以 `[1/6]` 至 `[6/6]` 的纵向卡片展示整个接入路径。每张卡片只回答“这一阶段会得到什么”，避免把所有选项和内部参数一次塞给新用户。

输入 `i` 可打开完整说明页。六个阶段均按 **检查 / 可能改变 / 不会** 说明影响；这是纯信息页，不执行安装或修改项目。按 Enter 或输入 `b` 返回开始菜单，输入 `q` 结束本次运行。

- GitHub 仓库名必填，格式为 `OWNER/REPOSITORY`，例如 `your-account/your-project`。空值、格式错误和无效选项会就地提示并重试，不会退出或交接给 Agent。
- 在仓库名输入处按 `b` 返回接入方式，可从“连接已有仓库”改选“创建”；可见性和执行确认处也提供返回入口。未确认执行前，不会创建仓库或修改 origin。
- `q` 结束本次运行；输入错误、返回或不确认执行，不等于发生了安装/远端操作失败。下一次运行会重新检查项目；真实网络或权限错误会显示原因和下一步。
- 标题、编号、标签、缩进和空行承担信息层级；交互终端支持时的粗体和轻量颜色只是增强。`NO_COLOR=1` 或 `TERM=dumb` 仍可读。向导要求真实交互终端，重定向输出不会启动交互流程。

## 六个阶段

1. **开发工作流**：检查 `github-workflow`、`superpowers`、`bmad`；已有则保留，不激活、不重装、不覆盖。未发现时可安装一种或不安装；未知流程不分类、不修改。
2. **普通 Skills 与 Understand Anything**：普通 Skills 经原生选择器立即安装。UA 是项目级代码理解工具，写入 `.agent/runtime/` 和 `.agents/skills/`，不写用户级插件目录；安装不等于已分析代码。
3. **项目规范**：初始化跨 Agent 规则与管理记录，保留现有指令；冲突不强制覆盖。
4. **Git/GitHub**：可选初始化 Git、创建或连接明确的 repository。引导使用 create-only/attach-only，不暂存、不提交、不推送，不覆盖冲突的 `origin`。
5. **验证、CI、审查与保护**：分开查看本地验证、CI、review 和分支保护。远端配置需要明确目标和单独授权；只有实际结果才能成为证据。
6. **总体验收**：列出实际已验证和本次未选择的能力，不把选择完成当作安装或治理已经验证。

### 我该选哪种 workflow？

- `github-workflow`：围绕分支、PR 与评审的协作流程。
- `superpowers`：结构化的开发工作流工具包。
- `bmad`：提供分析、规划和开发流程的 BMAD 方法。
- 暂时不知道：跳过安装即可，不必为了继续而承诺一种方法。

这些是安装选项，不是同时启用的开关。真正执行任务时仍需明确选择一个 workflow；已有项目规则继续有效。选择 Claude Auto Review 后，向导会交接你在项目会话完成官方 `/install-github-app`，恢复后检查实际审查反馈。选择本身不代表已经装好 App、认证、secret 或自动合并；审查反馈可用也不等于代码已获批准合并。

### Understand Anything：已有项目和空项目有什么不同？

**已有代码库（brownfield）**：理解模块、依赖和调用关系通常更有价值。你可以选择安装，再在需要时明确发起代码分析；安装成功本身不代表已经有了知识图谱。

**空项目（greenfield）**：目前没有足够代码可分析，可以先跳过，等结构成形再安装或分析。不会为了完成引导而制造空的分析结果。只在可信代码库使用此集成。

## 完成引导不等于已经可合并

创建空的 GitHub repository 不会自动产生远端分支、CI 结果或评审。没有这些证据时，保持 pending/blocked 是正常结果；之后提交与推送仍需独立授权。项目 validation 初始为 `pending`，auto-merge 为 `disabled`，真实 adapter 和检查不能被一个“成功”占位符代替。

证据检查的具体参数以 `scripts/check-bootstrap-evidence.sh --help` 为准。本仓库的 `--profile self` 只适用于 `blue126/agent-project-bootstrap/main`，不是下游默认保护；敏感治理改动仍由人工处理。

只更新托管文件时使用 `bootstrap.sh --target "$PWD" --update`：保留 metadata 和本地改动，不重跑安装，不混用安装或 Git mutation 参数。旧的显式发布入口会提交和推送，与这里的 create/connect-only 引导不同，详见 [README](../README.md#创建-github-repository)。
