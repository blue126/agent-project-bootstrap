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
  ui_note '基础流程完成后，可选择继续 GitHub、CI、审查和保护；也可以直接开始本地工作。'
  ui_section '重要边界'
  ui_text '• 每次运行重新检查真实项目状态；中断后直接重跑同一命令。' \
    '• 外部写入、发布、权限与覆盖操作都会在执行前单独确认。' \
    '• 不会自动提交、推送、创建 PR 或合并代码。'
}

ui_detail_stage() {
  ui_section "[$1/5] $2"
  ui_label '检查：' "$3"
  ui_label '可能改变：' "$4"
  ui_label '不会：' "$5"
}

ui_details() {
  ui_heading '项目接入 · 完整说明'
  ui_note '这是说明页，不会写入项目、启动安装器或改变任何配置。'
  ui_detail_stage 1 'Agent 客户端' \
    '已有项目偏好与入口；检测不等于安装，也不会自动代选。' \
    '本次明确选择安装目标；到基础配置确认时才保存项目偏好。' \
    '不自动安装或登录客户端；Universal 不是安装所有客户端。'
  ui_detail_stage 2 '工作方式' \
    'github-workflow、Superpowers、BMAD 的实际入口与已采用配置。' \
    '明确选择采用一种方法，稍后安装缺失内容。' \
    '不因发现文件或普通 Skills 安装而自动激活，不并行运行多个框架。'
  ui_detail_stage 3 'Skills 与可选能力' \
    '所选客户端需要的入口；已有 Skills 不会关闭添加入口。' \
    '进入原生安装器，复用客户端选择；可选 Understand Anything。' \
    '不使用 --yes/--all 省略授权，不截取原生 TUI，不自动分析代码。'
  ui_detail_stage 4 '项目规范与本地 Git' \
    'Agent 规则、忽略边界、Git root 与现有用户改动。' \
    '确认后写入必要配置，审阅精确 ignore 差异，按需初始化本地 Git。' \
    '不覆盖原文，不暂存提交、不推送；旧 Skills 忽略迁移另行确认。'
  ui_detail_stage 5 '开始工作' \
    '实际本地文件与 Git；客户端加载和首次提交另行验证。' \
    '汇总就绪/待处理项，给出首个任务入口，再询问可选 GitHub 协作。' \
    '不因缺少 CI 阻塞本地起步，不把文件存在当作客户端已加载。'
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
