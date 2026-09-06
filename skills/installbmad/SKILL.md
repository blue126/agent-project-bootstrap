---
name: installbmad
description: 安装、更新或修复 BMAD Method 的项目集成。用于安装 BMAD、为已有安装新增模块、修复 bmad-help 无法加载；不用于执行已安装的 BMAD 业务工作流。
argument-hint: "[project-directory]"
---

# 安装 BMAD Method

使用官方 CLI 安装，用随 skill 分发的 [只读辅助脚本](scripts/installbmad.py) 生成非交互参数和验收文件。脚本不安装、不修改目标、不验证会话加载。本文的 `/absolute/project/path`、`/absolute/skill/path` 和记录文件路径均须替换为实际绝对路径；skill 路径不是目标项目路径。

## 1. 确认目标与模式

- 确认用户授权的目标绝对路径和交互/非交互模式，不默认使用当前目录。交互模式把模块、工具与配置选择交给真实终端中的安装器；非交互模式必须已有明确选择及接受默认配置的授权。
- Git 项目先检查检出位置与 `_bmad/`、`.claude/skills/` 的忽略规则，命令见 [worktree 检查](references/installation.md#worktree-检查)。若原项目的本地安装未进入新 worktree，或安装位置与用户目标不一致，展示两个路径并告知“安装只作用于该 worktree，不会配置主检出”，让用户选择：当前 worktree／明确授权主检出／取消。主检出操作仍须符合仓库政策；改变目标后重新检查。
- 不自动复制配置、切换检出或修改 `.gitignore`。已有 `_bmad/` 却无法读取有效 manifest 时停止，不能当作新项目。保留模块不等于保留自定义文件内容，更新前确认本地修改的备份/保留方案。

## 2. 确认版本与依赖

先探测当前 Node.js、网络和缓存状态，不沿用历史环境结论。选择并记录具体安装器版本，探测与安装使用同一个版本；6.12.0 要求 Node.js >=20.12.0。仅在用户明确要求时选择预发布版本。

辅助脚本目前覆盖 **6.12.0**，不是“永远使用旧版”的策略：其他版本须先核对并更新脚本契约和测试，或交还官方交互路径；不为使用脚本而降级现有安装。Python 3.11+、PyYAML 隔离环境及 uv 缓存排错见 [依赖与版本](references/installation.md#依赖与版本)。这些是辅助工具依赖，不是 BMAD 文件安装的硬前置。

## 3. 安装

### Agent 非交互路径

在已准备好的隔离 Python 环境中运行下例；模块、工具按用户请求填写，记录保存到 `$TMPDIR` 内的专用绝对路径，不写进项目或覆盖已有记录。

```bash
python3 "/absolute/skill/path/scripts/installbmad.py" preflight --target "/absolute/project/path" --installer-version 6.12.0 --modules bmm --tools claude-code > "/absolute/temporary/path/bmad-before.json"
```

仅退出码 0 且 `status=planned` 才继续。检查输出的 canonical `target`、`existing`、`requested`、`expected` 和 `argv`：

- 新项目不传 action；已有安装使用 `--action update`。脚本将已有模块/工具与请求集合取并集；`core` 自动保留。不提供移除功能。
- `--modules`、`--tools` 是完整集合，不是追加参数。未知/外部条目保留在计划中，但可用性与来源须按所选版本核实；不可用时停止，不能删除条目后重试。
- 执行授权范围内的 `argv`，使用参数数组或正确的 shell 引号，**不要 `eval` JSON**。所有写入命令必须包含明确的 `--directory`；不要改成 `$PWD`。如用户指定语言等配置，追加已核对的官方配置选项，不替换目标、版本或集合。

安装前若目标状态已改变，重新生成记录。记录退出状态和警告；仍出现目录提示时终止本次安装进程并核对参数，不无限等待、注入回车或同时启动第二次安装。安装器退出成功不能替代下一步验收。

### 人工交互路径

让用户在真实终端执行 `npx bmad-method@已选具体版本 install --directory "已确认绝对路径"`，模块和配置由官方提示收集。不要在非 TTY agent shell 中启动此路径。已有安装选择 Modify BMAD Installation 并保留需要的模块/工具；安装前记录原集合，安装后按同样标准比较。[CLI 陷阱](references/installation.md#cli-陷阱) 说明为何 `--yes`、`update` 和 `quick-update` 不能互换。

## 4. 验收文件

对非交互路径，用安装前保存的原始 JSON 验收同一目标：

```bash
python3 "/absolute/skill/path/scripts/installbmad.py" verify --target "/absolute/project/path" --before "/absolute/temporary/path/bmad-before.json"
```

仅退出码 0 且 `status=files_verified` 表示文件验收通过。脚本比较版本、模块/工具保留情况，解析 `bmad-help.csv`，检查 BMM 的 PRD/Architecture/Build 标识及 Claude 对应可读 `SKILL.md` 入口；数量只作诊断。其他 AI 工具仍需分别验证其集成，Python 配置解析另见 [运行验证](references/installation.md#运行验证)。非零退出时报告诊断，不伪造缺失文件。

## 5. 验证新会话并报告

当前会话不保证重新索引新 skills。让用户在**同一目标目录的新会话**调用 `/bmad-help`，并明确要求：

> 请检查已安装的 BMM 中 PRD、Architecture、Build 三个入口是否可用，列出对应 skill 名称；不启动工作流。

默认帮助只推荐当前阶段内容，不要求它无条件列出全部入口。只有取得实际新会话结果才报告加载通过；否则报告“文件已安装，新会话加载待验证”。最终简报包含目标及 worktree/主检出范围、模块/工具变化、文件验收、运行/加载状态和警告，不能把 worktree 成功说成主检出已配置。
