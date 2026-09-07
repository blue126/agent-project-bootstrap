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
ui_label() { printf '    %s%s%s %s\n' "${ui_bold:-}" "$1" "${ui_reset:-}" "$2"; }

ui_stage_card() {
  printf '\n  %s[%s/6] %s%s\n' "${ui_bold:-}" "$1" "$2" "${ui_reset:-}"
  printf '      %s\n' "$3"
}

ui_overview() {
  ui_heading 'Agent 项目接入向导'
  ui_section '目标项目'
  ui_text "$1" '向导会根据项目当前状态协调能力，而不是只安装技能。'
  ui_section '接入路径'
  ui_stage_card 1 '开发工作流' '检查并保留已有方法；未发现时可安装一种内置工作流。'
  ui_stage_card 2 '技能与可选工具' '原生 Skills 选择器会立即打开；可按需安装 Understand Anything。'
  ui_stage_card 3 '项目规范' '建立或更新 Agent 规则；已有文件不会被直接覆盖。'
  ui_stage_card 4 'Git / GitHub' '检查或连接仓库；创建/连接不提交、不推送代码。'
  ui_stage_card 5 '验证、CI、审查与保护' '仅以实际运行和远端证据确认项目协作能力。'
  ui_stage_card 6 '总体验收' '区分已验证、本次未选择与仍需处理的能力。'
  ui_section '重要边界'
  ui_text '• 每次运行重新检查真实项目状态；中断后直接重跑同一命令。' \
    '• 外部写入、发布、权限与覆盖操作都会在执行前单独确认。' \
    '• 不会自动提交、推送、创建 PR 或合并代码。'
}

ui_detail_stage() {
  ui_section "[$1/6] $2"
  ui_label '检查：' "$3"
  ui_label '可能改变：' "$4"
  ui_label '不会：' "$5"
}

ui_details() {
  ui_heading '项目接入 · 完整说明'
  ui_note '这是说明页，不会写入项目、启动安装器或改变任何配置。'
  ui_detail_stage 1 '开发工作流' \
    '项目内是否已有 github-workflow、Superpowers 或 BMAD。' \
    '仅在你选择后安装一项缺失的内置工作流。' \
    '不执行工作流任务、不切换已有工作流、不判断未知流程。'
  ui_detail_stage 2 '技能与可选工具' \
    '项目内已有 Skills，以及 Understand Anything runtime 是否存在。' \
    '打开官方 Skills 选择器；按确认安装项目级 Understand Anything。' \
    '不在 Agent PTY 中代跑选择器，不自动分析代码或安装全局插件。'
  ui_detail_stage 3 '项目规范' \
    'AGENTS.md、CLAUDE.md、.agent 与受管文件的实际状态。' \
    '经确认后创建或更新未修改的受管规则和配置记录。' \
    '不直接覆盖用户文件、不生成业务代码、不提交或发布项目。'
  ui_detail_stage 4 'Git / GitHub' \
    '本地 Git、origin、仓库身份和可访问性。' \
    '经确认后初始化 Git，或创建/连接一个明确的 GitHub 仓库。' \
    '不暂存、不提交、不推送、不替换冲突的 origin。'
  ui_detail_stage 5 '验证、CI、审查与保护' \
    '实际本地验证、CI run、审查反馈和现有合并规则。' \
    '在真实证据存在且你确认后，配置项目 CI 门槛或相关保护。' \
    '不猜测测试命令、不把配置文件当通过、不自动批准或合并 PR。'
  ui_detail_stage 6 '总体验收' \
    '前五阶段留下的实际项目和远端证据。' \
    '只汇总本次已经验证的能力和你明确未选择的能力。' \
    '不把一次选择、旧记录或口头完成描述为已验证。'
  ui_section '返回'
  ui_text '按 Enter 或输入 b 返回开始菜单；输入 q 结束本次运行。'
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
