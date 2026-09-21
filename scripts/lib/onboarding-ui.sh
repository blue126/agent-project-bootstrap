#!/usr/bin/env bash
# Shared human-terminal presentation and input primitives for onboarding.

ui_init() {
  ui_reset='' ui_bold='' ui_heading_color='' ui_muted='' ui_warning_color=''
  if [[ -t 1 && "${TERM:-dumb}" != dumb && -z "${NO_COLOR:-}" ]]; then
    ui_reset=$'\033[0m'
    ui_bold=$'\033[1m'
    ui_heading_color=$'\033[1;36m'
    ui_muted=$'\033[2m'
    ui_warning_color=$'\033[1;33m'
  fi
}

ui_heading() {
  printf '\n%s%s%s\n' "${ui_heading_color:-}" "$1" "${ui_reset:-}"
  printf '%s%s%s\n\n' "${ui_muted:-}" '────────────────────────────────────────────────────────' "${ui_reset:-}"
}

ui_section() { printf '\n  %s%s%s\n\n' "${ui_bold:-}" "$1" "${ui_reset:-}"; }
ui_text() { printf '  %s\n' "$@"; }
ui_note() { printf '  %s%s%s\n' "${ui_muted:-}" "$1" "${ui_reset:-}"; }
ui_warning() { printf '\n  %s! %s%s\n' "${ui_warning_color:-}" "$1" "${ui_reset:-}"; }

ui_install_briefing() {
  ui_note '接下来是原生安装界面，它会依次询问：装哪些条目、装到哪些客户端、作用域（Project/Global）、以及复制还是链接。'
  ui_text '作用域选 Project：写入本项目目录，能被所选客户端发现，并随 Git 提交。' \
    'Global 写入用户主目录，本项目不算就绪，也会影响你的其他项目。' \
    '复制留下可提交的项目资产；链接指向本机路径，只有可复现时才应提交。' \
    '不确定就选 Project + 复制；安装可以重来，重跑本命令即可重新检查。'
}

ui_stage_card() {
  printf '\n  %s[%s/5] %s%s\n' "${ui_bold:-}" "$1" "$2" "${ui_reset:-}"
  printf '      %s\n' "$3"
}

ui_overview() {
  ui_heading 'Agent 项目接入向导'
  ui_section '目标项目'
  ui_text "$1" '向导会根据项目当前状态协调能力，而不是只安装技能。'
  ui_section '接入路径'
  ui_stage_card 1 'Agent 客户端' '明确选择项目使用的客户端；后续安装复用本次选择。'
  ui_stage_card 2 '工作方式' '保留已有方法，或采用一种内置工作流；不会自动运行任务。'
  ui_stage_card 3 'Skills 与可选能力' '原生搜索、多选和安装界面；已有 Skills 也能继续添加。'
  ui_stage_card 4 '项目规范与本地 Git' '建立规则、审阅忽略差异、初始化本地 Git，不提交或推送。'
  ui_stage_card 5 '开始工作' '检查本地入口，说明待确认项，并给出首个任务的起步方式。'
  ui_note '基础流程完成后，可选择建立 GitHub CI 与协作保障；也可以直接开始本地工作。'
  ui_section '重要边界'
  ui_text '• 每次运行重新检查真实项目状态；中断后直接重跑同一命令。' \
    '• 外部写入、发布、权限与覆盖操作都会在执行前单独确认。' \
    '• 不会自动提交、推送、创建 PR 或合并代码。'
}

ui_details() {
  ui_heading '开始前，先了解这趟流程'
  ui_text '目标很简单：让当前项目具备一套可以开始工作的 Agent 开发环境。' \
    '你会依次选客户端、工作方式和 Skills，再建立项目规则与本地 Git。' \
    '每次准备写文件或连接外部服务前，向导都会说明影响并再次询问。'
  ui_note '现在只是查看说明；不会写项目、启动安装器或连接 GitHub。'

  ui_section '第 1 步 · 选择你实际使用的 Agent'
  ui_text '可以选择 Claude Code、Codex、OpenCode，也可以多选。已有配置只用于预选，最终仍由你确认。' \
    '这个选择决定 Skills 应放到哪些项目目录；它不会替你安装客户端、登录账号或修改全局配置。'
  ui_note 'Universal 只是共享 .agents/skills 目录模式，不等于安装了所有客户端。'

  ui_section '第 2 步 · 选择 Agent 怎样开展任务'
  ui_text '工作方式回答的是：Agent 接到需求后，应该按哪套方法分析、实现和验证。' \
    'github-workflow 偏 Git/PR 协作，Superpowers 偏功能开发，BMAD 偏需求与架构；也可以保留现有方法。' \
    '向导只保存你明确采用的一种方式。选择或安装完成都不会自动开始任务。'

  ui_section '第 3 步 · 补充项目需要的 Skills'
  ui_text '工作流自带的 Skills 和本仓库提供的额外 Skills 会分开处理，已有 Skills 也可以继续补充。' \
    '真正的搜索、多选、作用域和复制/链接方式由原生 Skills 界面完成，bootstrap 不会代替它做决定。' \
    '原生列表的空圆圈只表示“这次没有选”，不代表尚未安装；向导会在进入前列出已检测到的本仓库 Skills。'
  ui_note 'Understand Anything 更适合已有代码库，可以跳过；安装它不会立即分析代码。'

  ui_section '第 4 步 · 建立项目规则和本地 Git'
  ui_text '向导会准备 AGENTS.md、客户端入口和 Git 资产规则；已有文件会保留，不会直接覆盖。' \
    '如果需要调整 .gitignore，会先展示精确 diff。你还可以选择初始化本地 Git。' \
    '这一步不会暂存、提交或推送代码，也不会设置全局 Git 身份。'

  ui_section '第 5 步 · 确认可以从哪里开始'
  ui_text '最后会分别告诉你：哪些文件已经就绪、哪些仍需客户端新会话确认，以及项目是否尚未提交。' \
    '向导会给出第一个任务的起步建议。本地配置完成后，你可以直接结束，也可以继续建立 GitHub CI。' \
    '没有 CI 不会阻止本地起步；空项目可先放入待补全 CI 骨架，真实检查成功后才会进入审查与保护。'

  ui_section '你始终拥有控制权'
  ui_text '任何时候输入 q 都可以退出。已经完成的安全步骤会保留，未确认的操作不会执行。' \
    '以后重新运行同一命令，向导会检查项目的真实状态，而不是从某个问题编号继续。'
  ui_note '按 Enter 或输入 b 返回开始菜单。'
}

ui_return_from_details() {
  while :; do
    ask 'Enter 返回开始菜单，b 返回，q 结束本次运行:'
    case "${reply}" in
      ''|b|B|back|BACK) return 0 ;;
      *) ui_warning '请直接回车或输入 b 返回；输入 q 可结束本次运行。' ;;
    esac
  done
}

ask() {
  local prompt="$1"
  printf '\n  %s> %s%s ' "${ui_bold:-}" "${prompt}" "${ui_reset:-}"
  if ! IFS= read -r reply; then
    echo '接入已结束。以后重新运行同一命令，向导会根据项目实际状态继续。' >&2
    exit 3
  fi
  reply="${reply#"${reply%%[![:space:]]*}"}"
  reply="${reply%"${reply##*[![:space:]]}"}"
  if [[ "${reply}" == q || "${reply}" == Q ]]; then
    echo '接入已结束。未确认的操作没有执行；以后重新运行同一命令即可。'
    exit 3
  fi
}

confirm() {
  while :; do
    ask "$1 [y/N，q 退出]:"
    case "${reply}" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO|'') return 1 ;;
      *) ui_warning '请输入 y 确认、n 不执行，或 q 退出。' ;;
    esac
  done
}

pause_for_agent() {
  local task="$1"
  ui_heading '需要项目 Agent 协助'
  ui_text "下一步：${task}"
  ui_note '请在目标项目的 Agent 会话中完成必要工作。运行代码、下载依赖、覆盖文件、提交、推送或修改远端前，分别取得授权。'
  ui_note '完成后重新运行同一 bootstrap 命令；向导会重新检查实际结果。'
  exit 3
}
