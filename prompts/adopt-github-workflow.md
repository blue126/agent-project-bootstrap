# Adopt GitHub workflow for an existing project

> Status: proposed adoption prompt. It is not executed by the current bootstrap
> flow.

你正在迁移一个既有 brownfield Git 项目，使其采用以下目标工作流：

- GitHub 上的 `origin/main` 是最终代码权威来源
- 禁止在 `main` 或 `master` 上直接开发
- 每个任务使用独立 branch 和 worktree
- Agent 完成 edit → validate → commit → push → Draft PR
- Agent 永远不得 merge PR

项目路径：`<PROJECT_PATH>`

一次只处理这个项目。不得扫描、修改或批量操作其他项目。

## 授权范围

本提示词明确授权你：

- 读取项目文件和 Git 元数据
- 查询当前 `gh` 登录的 GitHub 用户
- 检查该用户账号下是否存在与项目目录同名的 GitHub repository
- 如果同名 repository 存在且历史兼容，选择它作为项目远端
- 如果同名 repository 不存在，创建同名 private repository
- 在 `origin` 不存在时添加经过验证的 GitHub repository 为 `origin`
- 向全新空 repository 的 `main` 推送一次现有干净基线
- 创建独立迁移 branch/worktree
- 修改迁移工作流直接相关的文件
- 运行无部署副作用的现有验证命令
- 在项目规则允许后 commit、push 并创建 Draft PR

本提示词不授权你：

- 创建名称不同于项目目录 basename 的 GitHub repository
- 未经明确授权选择其他 OWNER 或 GitHub Organization
- 默认创建 public repository
- 替换、重命名或重新指向已有 `origin`
- merge 或关闭 PR
- 在已建立的 `main`/`master` 上直接开发或提交
- force push，包括 `--force-with-lease`
- 删除或重命名已有 branch、tag、remote 或 worktree
- stash、reset、clean、覆盖或提交用户已有改动
- 修改 Git history
- 擅自修改 GitHub 默认分支、Ruleset、branch protection、Actions secrets、Environment 或权限
- 部署、发布、上传镜像、执行 Terraform apply、运行 Ansible deployment，或修改外部生产系统
- 安装依赖、升级工具链或顺手修改无关代码
- 输出凭据或读取与迁移无关的 secret

项目已有的 `AGENTS.md`、`CLAUDE.md`、`KERNEL.md` 和其他权威规则继续有效。如果它们要求额外确认，不得用本提示词绕过。

## 第一阶段：只读预检

任何写操作前：

1. 确认项目路径及真实 Git 根目录。
2. 记录真实项目目录 basename。它是允许使用的 GitHub repository 名称，必须原样保留；不得根据 package name、README 标题或父目录重新命名。
3. 阅读适用的 `AGENTS.md`、`CLAUDE.md`、`KERNEL.md`、`GEMINI.md` 以及 Copilot、Cursor、Codex、Claude 或 OpenCode 规则。
4. 识别生成器托管区、canonical/source-of-truth 引用、提交前确认要求、部署和隐私限制。
5. 检查当前 branch、detached HEAD、working tree、index、已有 worktree、所有 remote、远端默认分支、`origin/main`、`origin/master` 和当前 upstream。
6. 检查现有 CI、构建清单、README 和 Agent 文件中记录的 test、lint、typecheck、build 命令。
7. 区分无副作用 validation 与 deploy、publish、apply、release、镜像推送等操作。

先输出预检摘要和项目分类，再实施迁移。

## 第二阶段：GitHub repository 解析

### 已有 GitHub `origin`

验证其 OWNER、repository 名称和默认分支。

如果 repository 名称与项目目录不同，不要擅自迁移或重命名；报告差异并停止等待确认。

### 没有 `origin`，且没有其他 GitHub remote

1. 使用 `gh` 验证当前登录状态。
2. 获取当前经过认证的 GitHub username。
3. 将候选仓库精确设为 `<authenticated-owner>/<project-directory-basename>`。
4. 不得从缺失 remote 中猜测其他 OWNER。
5. 查询该精确仓库是否存在。

#### 同名仓库已经存在

只可在以下条件下选择：

- 仓库归属经过验证的当前 GitHub 用户，或用户已明确指定该 Organization
- repository 为空，或其 history 与本地历史兼容

选择前检查 repository visibility、默认分支、已有 commit、共同祖先以及是否存在分叉或不相关历史。

如果远端存在不相关历史、双方都有独立提交或默认分支含未知内容，立即停止。不得 force push、覆盖远端或自动合并历史。

兼容时，仅在 `origin` 缺失的情况下将其添加为 `origin`。

#### 同名仓库不存在

允许创建 `<authenticated-owner>/<project-directory-basename>`。

默认 visibility 为 `private`。只有用户明确指定时才能创建 `public` 或 `internal` repository。不得创建不同名称的 repository，不得自动选择 Organization。

#### 初始 main 推送

只有同时满足以下条件时，才允许向新建或确认为空的 repository 首次推送 `main`：

- working tree 和 index 干净
- 本地已有可验证的 commit
- 远端 repository 为空
- 推送内容仅为当前既有项目基线
- 不需要改写 Git history

这是建立远端基线的一次性例外，不代表以后允许直接 push `main`。不得把未提交文件、未知 staged 内容或迁移中的新修改混入初始基线。

初始推送完成后，后续迁移修改必须通过独立 branch/worktree 和 PR。

### `origin` 已存在但不是 GitHub

不得替换、删除或重命名它。如果另有 GitHub remote，报告两个 remote 及其状态，要求用户决定哪个是权威来源。在得到决定前不得推送或调整 remote。

### 无法验证 GitHub 身份或仓库归属

停止操作，报告缺失条件。不得猜测 OWNER。

## 第三阶段：迁移分类

### A. `origin/main` 已存在

从最新 `origin/main` 创建新的迁移 branch/worktree。不得切换或修改用户当前 checkout。

### B. 当前远端默认分支是 `master`

不得自行修改 GitHub 默认分支。可以准备以 `master` 为 base 的迁移 PR，但必须说明：

- PR 合并前，权威基线仍是 `origin/master`
- GitHub 默认分支人工改名后，`origin/main` 才成为权威来源

列出受改名影响的 workflow、badge、脚本、Jenkins、webhook 和部署集成。对于 deploy/publish workflow，不得自行修改触发分支。

### C. 工作区有未提交改动

不得 stash、reset、clean、checkout、移动或提交这些改动。如果存在可靠远端基线，可从远端 commit 创建独立 worktree；否则停止并报告。

### D. 默认分支或历史兼容性无法可靠判断

停止操作。不得仅凭当前本地 branch 名称作出判断。

## 第四阶段：最小修改

默认允许修改：

- 根目录 `AGENTS.md`
- 已存在的根目录 `CLAUDE.md`
- 必要的独立 PR validation workflow
- 与默认分支名称直接相关的少量配置或文档
- 确有必要且不存在同类工具时的 `scripts/agent-start`

开始编辑前列出拟修改文件。需要扩大范围时停止并请求授权。

### AGENTS.md

如果已存在：

- 保留项目知识、命令、安全规则和编码规范
- 只增量加入 `Git and Pull Request Workflow` 章节
- 不覆盖或重新组织整份文件
- 不降低原有确认、提交、部署、隐私或凭据限制
- 不在生成器托管区内编辑
- canonical 归属不清时停止

如果不存在，创建简短的 `AGENTS.md`，只记录工作流规则和经过验证的项目命令，不得虚构项目事实。

工作流章节至少包含：

- 迁移完成后 `origin/main` 是 source of truth
- 禁止直接在 `main`/`master` 开发、commit 或 push
- 每个任务从最新远端默认分支创建独立 branch/worktree
- 开工前检查 branch、dirty state、upstream 和 worktree 冲突
- 完成顺序：validate → commit → push branch → Draft PR
- Agent 不得 merge、force push、删除 branch/worktree 或清理用户改动

### CLAUDE.md

- 不得覆盖已有内容
- 已使用 `@AGENTS.md` 时保持
- 未引用时可增量加入引用，同时保留 Claude 专属规则
- 未使用 Claude Code 的项目不必强行创建

### CI

- 只使用项目已经定义且能安全运行的检查
- 不得猜测命令或安装新框架
- 不得把 deploy、publish、apply、release 或镜像推送 workflow 直接改成 PR workflow
- 必要时创建独立 validation workflow
- validation 不得访问生产 secrets 或写入外部系统
- 没有安全检查时如实报告，不得创建永远成功的假门禁

## 第五阶段：验证与交付

1. 从确认过的远端基线创建唯一迁移 branch/worktree。
2. branch 或 worktree 名称冲突时选择新的无冲突名称；不得删除旧对象。
3. 只修改已声明文件。
4. 检查最终 diff，确认无业务代码变化、凭据、个人数据、无关格式化、托管内容覆盖、安全规则放宽或 CI 外部副作用。
5. 只运行已确认安全且无需安装依赖的验证命令。
6. 清楚报告未运行检查及原因。
7. 如果项目规则要求提交前确认，必须再次询问。
8. 获得所需授权后，commit 到迁移分支、正常 push，并创建 Draft PR。
9. 创建 Draft PR 后停止。

不得 merge PR，不得删除 branch/worktree，不得修改用户原 checkout。

## 最终报告

- 项目分类
- GitHub 登录 OWNER
- 项目目录 basename
- GitHub repository 是已有选择还是新建
- repository visibility
- 远端和默认分支证据
- 原有 Agent/CI 配置
- 冲突及保留方式
- 修改文件
- 验证结果
- Draft PR URL
- 必须人工完成的 GitHub 步骤
- 未解决问题或停止原因
