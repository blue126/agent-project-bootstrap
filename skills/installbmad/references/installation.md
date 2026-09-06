# 安装参考

只在对应分支或错误发生时读取。本文件不替代 [主流程](../SKILL.md) 的目标授权与验收。

## 依赖与版本

BMAD 文件安装需要符合所选版本要求的 Node.js；本辅助脚本需要 Python 3.11+ 与 [requirements.txt](../requirements.txt) 中的 PyYAML。脚本不安装依赖，不执行目标项目代码，缺依赖会以退出码 2 结束。

允许获取依赖后，在 `$TMPDIR` 下选择一个未占用的专用目录，准备隔离环境（所有绝对路径均为占位符）：

```bash
python3 -m venv "/absolute/new/temporary/helper-venv"
```

```bash
"/absolute/new/temporary/helper-venv/bin/python" -m pip install --disable-pip-version-check --no-cache-dir -r "/absolute/skill/path/requirements.txt"
```

```bash
source "/absolute/new/temporary/helper-venv/bin/activate"
```

随后主文中的 `python3` 必须指向这个环境，不在全局 Python 中安装依赖。若已有 uv，也可在用户授权依赖获取后用 `UV_CACHE_DIR="$TMPDIR/uv-cache" uv run --no-project --with-requirements "/absolute/skill/path/requirements.txt" python …` 调用脚本，不加载目标项目的 Python 依赖。uv 缺失不妨碍原生 BMAD 交互安装。

先运行 `node --version`。版本确定后，探测与实际安装均使用同一具体包版本；以下 6.12.0 是已核对的版本，不是最新版本声明：

```bash
npx --yes bmad-method@6.12.0 install --help
```

```bash
npx --yes bmad-method@6.12.0 install --list-tools
```

`npx --yes` 只跳过 npm 包获取确认；`install --yes` 接受 BMAD 默认配置并跳过部分提示，两者不能互相替代。不要用移动标签替代脚本要求的具体版本。新版本需要先核对 CLI、manifest 和入口名称，扩展脚本的版本契约及测试；不自动降级现有安装来适配旧契约。

## worktree 检查

仅 Git 项目执行；下面的目标须换成已授权绝对路径：

```bash
git -C "/absolute/project/path" rev-parse --show-toplevel --git-dir --git-common-dir
```

```bash
git -C "/absolute/project/path" worktree list --porcelain
```

```bash
git -C "/absolute/project/path" check-ignore -v -- _bmad/ _bmad/_config/manifest.yaml .claude/skills/ .claude/skills/bmad-help/SKILL.md
```

`check-ignore` 无匹配返回 1；其他错误需处理。Git 忽略的本地配置不会被复制到新 worktree。先获得必要的目录访问授权，再比较原项目与目标的安装状态；只读 helper 仅检查传入目标，不会代替 agent 判断用户意图，也不会自动读取主检出。helper 发现目标内部链接指向外部位置会停止，不能通过删除链接或复制配置绕过。

## CLI 陷阱

以下行为来自 BMAD 6.12.0 发布源码核对，目录提示、已有模块和 uv 缓存问题也有使用反馈佐证；不代表任意版本都已实测。

| 情况 | 正确处理 |
| --- | --- |
| `--yes` 仍显示 `Installation directory:` | 必须显式传入已确认的绝对 `--directory`；终止仍等待输入的安装进程后再排查 |
| 已有安装传 `--action install` | 6.12.0 虽在帮助里列出 install，已有安装实际上只接受 update/quick-update |
| 已有安装仅加 `--yes --modules bmm` | 可能默认 quick-update；新增模块必须显式 update |
| 使用 quick-update 新增 BMM | 它只刷新原安装，不进入新增模块路径 |
| update 只列 bmm 或 claude-code | 完整选择集合会触发移除未选项；用 helper 生成并集，不手工缩减 |
| 源码/工具不可用 | 保留未知标识并停止说明，不能丢弃后续装；移除或自定义来源处理不属于本 helper 的自动路径 |
| registry 或缓存报错 | 报告实际请求和错误；npx 成功可能来自缓存，不能推出网络一定可达，也不沿用历史封禁断言 |

脚本 `preflight` 的退出码：0 表示生成了计划，2 表示输入/依赖/安装状态不支持。JSON 的 `argv` 是参数数组，不是要交给 `eval` 的字符串。计划不包含文件内容备份，也不保证更新不改变保留模块的版本或配置。

脚本 `verify` 的退出码：0 表示文件验收通过，1 表示文件验收不通过，2 表示目标、记录或 manifest 无法安全读取。它检查 6.12.0 的 `bmad-prd`、`bmad-architecture`、`bmad-build` 标识，而非模糊显示名称；Claude 数量仅统计目标内可读的直接 skill 入口，外部/损坏的无关 skills 不计入。其他工具的 manifest 记录通过不等于其运行集成已验证。

## 运行验证

`uv --version` 只能证明 uv 可调用。若要验证 BMAD 配置解析，确认目标脚本存在、`$TMPDIR` 已设置且可写，再经用户授权执行；这会运行目标代码并可能下载 Python，因此不在只读 helper 内执行：

```bash
UV_CACHE_DIR="$TMPDIR/uv-cache" uv run --no-project "/absolute/project/path/_bmad/scripts/resolve_config.py" --project-root "/absolute/project/path"
```

缓存权限错误不是 uv 缺失。设置临时缓存仍失败时，报告实际错误，不绕过沙箱。配置解析成功也不证明新会话已索引 skills；新会话查询方式见主文。

## 维护者验证

离线测试使用仓库的 `tests/test-installbmad.sh`，覆盖两种 manifest、模块/工具并集、坏输入、文件验收和只读性，不调用包管理器。默认 CI 只运行这些离线用例，依赖由独立准备步骤提供。

[可选 live smoke](../scripts/smoke.py) 必须显式运行，且不接受用户项目目录：

```bash
python3 "/absolute/skill/path/scripts/smoke.py" --run
```

它在新建的 `$TMPDIR` 子目录隔离 HOME、缓存和项目，用 6.12.0 实际执行全新 BMM、全新 core-only、core-only 新增 BMM 三次安装；关闭 stdin 并设置进程组时限，保存日志路径供诊断。它还实际调用配置解析器（需要 uv）。失败不退回 fixture 冒充成功。外部 `bmb/cis` 的保留仅由离线用例验证；live smoke 和文件 helper 都不验证新会话加载。

核对来源：[BMAD 6.12.0 npm 元数据](https://registry.npmjs.org/bmad-method/6.12.0)，主要依据发布包的 `tools/installer/ui.js`、`core/installer.js` 和 `src/core-skills/bmad-help/SKILL.md`。
