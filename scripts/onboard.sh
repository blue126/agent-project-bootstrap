#!/usr/bin/env bash
# shellcheck disable=SC2154
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="$(pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) [[ $# -ge 2 ]] || exit 2; target_dir="$2"; shift 2 ;;
    --onboard) shift ;;
    -h|--help) printf '%s\n' 'Usage: onboard.sh [--target DIR]'; exit 0 ;;
    *) echo "Unknown onboarding argument: $1" >&2; exit 2 ;;
  esac
done
# shellcheck disable=SC1091
source "${repo_root}/scripts/lib/agent-environment.sh"
if is_agent_environment; then
  echo 'An Agent process cannot host the interactive bootstrap selectors.' >&2
  echo '请由用户在普通终端运行；不要清除 Agent 检测变量或使用 Agent PTY。' >&2
  exit 2
fi
[[ -t 0 && -t 1 && -t 2 ]] || { echo '基础接入需要真实交互终端。' >&2; exit 2; }
for variable in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE; do
  [[ -z "${!variable:-}" ]] || { echo "请先检查 Git 路径重定向：${variable}；未执行接入。" >&2; exit 2; }
done
for tool in jq git python3; do
  command -v "${tool}" >/dev/null || { echo "${tool} is required; no dependency was installed" >&2; exit 2; }
done
target_dir="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${target_dir}")"
[[ ! -e "${target_dir}" || -d "${target_dir}" ]] || { echo '目标不是目录' >&2; exit 2; }
git_probe="${target_dir}"
while [[ ! -d "${git_probe}" ]]; do git_probe="$(dirname "${git_probe}")"; done
git_root="$(git -C "${git_probe}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "${git_root}" && "$(cd "${git_root}" && pwd -P)" != "${target_dir}" ]]; then
  echo "目标位于另一个 Git 仓库内，请先确认项目边界：${git_root}" >&2
  exit 2
fi
# shellcheck disable=SC1091
source "${repo_root}/scripts/lib/onboarding-ui.sh"
# shellcheck disable=SC1091
source "${repo_root}/scripts/lib/onboarding-git-assets.sh"
ui_init
project_info() { python3 "${repo_root}/scripts/lib/onboarding-project.py" --project "${target_dir}" "$@"; }
run_installer() { (cd "${target_dir}" && "$@"); }
choose() { python3 "${repo_root}/scripts/lib/onboarding-select.py" "$@"; }
bmad_fresh_preflight() {
  python3 -B - "${repo_root}" "${target_dir}" <<'PY'
import importlib.util
from pathlib import Path
import sys
sys.dont_write_bytecode = True
source, project = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location('project', source / 'scripts/lib/onboarding-project.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
try:
    for legacy in ('_bmad', 'bmad'):
        path = helper.path_in(project, legacy)
        if path.exists() or path.is_symlink():
            raise ValueError('Existing or legacy BMAD requires explicit installation review')
    clients = helper.clients_manifest()
    roots = {record['project_path'] for record in clients.values()}
    roots.update(record['bmad_commands'] for record in clients.values() if 'bmad_commands' in record)
    for relative in roots:
        path = helper.path_in(project, relative)
        if any(path.glob('bmad-*')):
            raise ValueError('Residual BMAD client entries require installation review')
except (OSError, ValueError, RuntimeError) as error:
    raise SystemExit(str(error)) from None
PY
}

ui_overview "${target_dir}"
while :; do
  ask '开始接入？[y 开始，i 查看完整说明，n 退出]:'
  case "${reply}" in
    y|Y|yes|YES) break ;;
    i|I) ui_details; ui_return_from_details ;;
    n|N|no|NO) exit 0 ;;
    *) ui_warning '请选择 y 开始、i 查看完整说明、n 退出，或 q 结束本次运行。' ;;
  esac
done
state="$(project_info clients)" || exit 1
ui_heading '阶段 1/5 · Agent 客户端'
ui_text '选择这个项目使用的客户端，可多选；已有配置只作为预选，不代替你的确认。' \
  'Universal 是 .agents/skills 共享目录模式，不代表安装了所有客户端。'
selector=(--title '选择项目 Agent 客户端' --multi
  --option claude-code 'Claude Code'
  --option codex 'Codex'
  --option opencode 'OpenCode'
  --option universal 'Universal · 通用共享目录')
while IFS= read -r client; do
  [[ -z "${client}" ]] || selector+=(--selected "${client}")
done < <(printf '%s' "${state}" | jq -r 'if (.selected|length)>0 then .selected[] else .detected[] end')
selected_clients="$(choose "${selector[@]}")" || exit $?
project_agents=()
while IFS= read -r client; do [[ -z "${client}" ]] || project_agents+=("${client}"); done <<< "${selected_clients}"
[[ ${#project_agents[@]} -gt 0 ]] || exit 3
ui_text "客户端：${project_agents[*]}"

ui_heading '阶段 2/5 · 工作方式'
active="$(printf '%s' "${state}" | jq -r '.workflow // "none"')"
installed="$(printf '%s' "${state}" | jq -r '.installed_workflows[]')"
install_workflow=none
if [[ "${active}" != none ]]; then
  ui_text "保留项目已明确采用的工作流：${active}" '检测安装与运行任务是两回事；本次不会运行工作流。'
  if ! printf '%s\n' "${installed}" | grep -Fxq "${active}"; then
    ui_warning '配置声明了工作流，但未发现完整安装入口。'
    if confirm '安装这项缺失的工作流？'; then install_workflow="${active}"; fi
  fi
elif [[ -n "${installed}" ]]; then
  selector=(--title '已有工作流：选择保留或明确采用' --option keep '保留现有启用状态，不改工作方式' --selected keep)
  while IFS= read -r item; do selector+=(--option "${item}" "采用已安装的 ${item}（不重装）"); done <<< "${installed}"
  selection="$(choose "${selector[@]}")" || exit $?
  [[ "${selection}" == keep ]] || active="${selection}"
else
  while :; do
    selection="$(choose --title '选择工作方式' \
      --option github-workflow '采用并安装 github-workflow · Git 分支、审阅与协作' \
      --option superpowers '采用并安装 Superpowers · 功能设计、实现与验证' \
      --option bmad '采用并安装 BMAD · 需求、架构与系统性迭代' \
      --option none '保留现有方法，不新增框架' --selected none)" || exit $?
    if [[ "${selection}" == bmad && " ${project_agents[*]} " == *' universal '* ]]; then
      ui_warning 'BMAD 不支持 Universal：请选择其他工作方式，或退出后调整客户端。'
      continue
    fi
    break
  done
  active="${selection}"
  install_workflow="${selection}"
fi
ui_note '选择采用只会在之后确认项目配置时保存；安装或选择不自动执行任务。'

ui_heading '阶段 3/5 · Skills 与可选能力'
installation_failed=false
entry_plan="$(project_info links --agents "${project_agents[@]}")" || exit 1
printf '%s' "${entry_plan}" | jq -r '.conflicts[] | "  待处理：\(.)"'
if [[ "$(printf '%s' "${entry_plan}" | jq '.links | length')" -gt 0 ]]; then
  ui_text '可为所选客户端复用已有项目 Skills；只补缺失的相对链接，不更新或覆盖现有内容：'
  printf '%s' "${entry_plan}" | jq -r '.links[] | "  \(.path) → \(.target)"'
  if confirm '补齐以上已有项目 Skill 的客户端入口？'; then
    token="$(printf '%s' "${entry_plan}" | jq -r .token)"
    project_info links --agents "${project_agents[@]}" --apply --expect "${token}" >/dev/null || installation_failed=true
  fi
fi
if [[ "${install_workflow}" != none ]]; then
  ui_text "将安装 ${install_workflow}，目标客户端：${project_agents[*]}"
  if [[ "${install_workflow}" == bmad && " ${project_agents[*]} " == *' universal '* ]]; then
    ui_warning 'BMAD 6.12.0 不支持 Universal tool ID。本次不安装；请重跑选择受支持客户端或保留现有方法。'
    installation_failed=true
  elif confirm '进入所选工作流安装器？'; then
    mkdir -p "${target_dir}"
    case "${install_workflow}" in
      github-workflow)
        run_installer npx skills@1.5.23 add "${repo_root}" --skill github-workflow --agent "${project_agents[@]}" || installation_failed=true ;;
      superpowers)
        pin="$(git ls-remote https://github.com/obra/superpowers.git 'refs/tags/v6.3.0' 'refs/tags/v6.3.0^{}')" || pin=''
        if ! printf '%s\n' "${pin}" | grep -q '^b36e0829c6d0140e93cfef2ca599b1b07d4a7797[[:space:]]'; then
          ui_warning 'Superpowers 固定版本校验失败，未执行安装。'; installation_failed=true
        else
          run_installer npx skills@1.5.23 add https://github.com/obra/superpowers/tree/v6.3.0 --agent "${project_agents[@]}" || installation_failed=true
        fi ;;
      bmad)
        if [[ -e "${target_dir}/_bmad" || -L "${target_dir}/_bmad" ]]; then
          ui_warning '发现既有或不完整 BMAD；请先按 installbmad preflight 审阅模块、工具和定制文件，未自动覆盖。'
          installation_failed=true
        elif ! bmad_fresh_preflight; then
          ui_warning '发现旧 BMAD 入口或不安全的适配路径；未启动安装器，请先审阅安装状态。'
          installation_failed=true
        else
          tools_csv="$(IFS=,; printf '%s' "${project_agents[*]}")"
          ui_text '模块、语言与项目设置仍在官方界面选择；不会传入 --yes。'
          run_installer npx bmad-method@6.12.0 install --directory "${target_dir}" --tools "${tools_csv}" || installation_failed=true
        fi ;;
    esac
  else ui_note '本次不安装所选工作流；缺失入口会在结果中列出。'; fi
fi

# Existing BMAD adapters need its official metadata/command-pointer handling,
# not generic Skill links or a blind reinstall.
if [[ "${active}" == bmad && -f "${target_dir}/_bmad/_config/manifest.yaml" && " ${project_agents[*]} " != *' universal '* ]]; then
  bmad_status="$(project_info readiness --agents "${project_agents[@]}" --workflow bmad)" || exit 1
  if [[ "$(printf '%s' "${bmad_status}" | jq '[.clients[].adapters_ready] | all')" != true ]]; then
    ui_warning 'BMAD 缺少所选客户端入口。补齐会调用官方 update；模块/tools 并集不保证定制文件不被改写。'
    if confirm '查看 BMAD 客户端补齐计划？'; then
      tools_csv="$(IFS=,; printf '%s' "${project_agents[*]}")"
      bmad_helper="${repo_root}/skills/installbmad/scripts/installbmad.py"
      if before="$(python3 "${bmad_helper}" preflight --target "${target_dir}" --installer-version 6.12.0 --modules core --tools "${tools_csv}" --interactive)"; then
        printf '%s\n' "${before}"
        if confirm '已审阅定制文件影响，执行以上 BMAD 补齐？'; then
          before_file="$(mktemp "${TMPDIR:?}/bmad-before.XXXXXX")"
          printf '%s\n' "${before}" > "${before_file}"
          command=()
          while IFS= read -r -d '' argument; do command+=("${argument}"); done < <(printf '%s' "${before}" | jq -j '.argv[] | ., "\u0000"')
          if run_installer "${command[@]}"; then
            python3 "${bmad_helper}" verify --target "${target_dir}" --before "${before_file}" || installation_failed=true
          else installation_failed=true; fi
          rm -f -- "${before_file}"
        fi
      else
        ui_warning 'BMAD 安全预检未通过或缺少 Python 3.11/PyYAML；没有安装依赖或覆盖现有配置。'
        installation_failed=true
      fi
    fi
  fi
fi

ui_section '普通 Skills'
ui_text '已有 Skills 保留；你仍可添加其他能力或为所选客户端安装入口。' \
  '官方界面负责搜索、多选、安装作用域与复制/链接。推荐选 Project；Global 不算项目入口已就绪。'
if confirm '进入技能选择？'; then
  mkdir -p "${target_dir}"
  run_installer npx skills@1.5.23 add "${repo_root}" --agent "${project_agents[@]}" || installation_failed=true
else ui_note '本次不添加普通技能。'; fi

ui_section 'Understand Anything · 可选'
ui_text '已有代码库可用它理解结构；空项目可以先跳过。固定版本 runtime 放在项目内，不安装全局插件。' \
  '已有 runtime 可以补齐客户端入口；安装不代表已经分析代码，后续分析可能产生模型费用。'
if confirm '安装或补齐 Understand Anything 项目入口？'; then
  mkdir -p "${target_dir}"
  args=(--target "${target_dir}")
  for client in "${project_agents[@]}"; do args+=(--agent "${client}"); done
  "${repo_root}/scripts/install-understand-anything.sh" "${args[@]}" || installation_failed=true
else ui_note '本次不安装 Understand Anything，继续项目规范。'; fi

ui_heading '阶段 4/5 · 项目规范与本地 Git'
ui_text "项目客户端：${project_agents[*]}" "采用的工作方式：${active}" \
  '将保存项目偏好、建立必要规则与客户端入口；已有原文保留，忽略规则稍后展示精确差异。' \
  '不会暂存、提交、推送、创建远端或设置全局 Git 身份。'
if confirm '建立或更新上述项目基础配置？'; then
  mkdir -p "${target_dir}"
  if [[ -f "${target_dir}/.agent/bootstrap.yml" ]]; then
    token="$(printf '%s' "${state}" | jq -r .config_sha256)"
    project_info save --agents "${project_agents[@]}" --workflow "${active}" --expect "${token}" >/dev/null || exit 1
    "${repo_root}/scripts/bootstrap.sh" --target "${target_dir}" --update || exit 1
  else
    args=(--target "${target_dir}" --workflow "${active}" --skip-skills --skip-understand-anything --skip-superpowers --adopt-existing)
    [[ "${active}" != github-workflow ]] || args+=(--skip-claude-auto-review)
    for client in "${project_agents[@]}"; do args+=(--agent "${client}"); done
    "${repo_root}/scripts/bootstrap.sh" "${args[@]}" || exit 1
    latest="$(project_info clients)" || exit 1
    token="$(printf '%s' "${latest}" | jq -r .config_sha256)"
    project_info save --agents "${project_agents[@]}" --workflow "${active}" --expect "${token}" >/dev/null || exit 1
  fi
  review_git_assets
  if ! git -C "${target_dir}" rev-parse --git-dir >/dev/null 2>&1; then
    if confirm '初始化本地 Git？（不创建提交或远端）'; then
      git -C "${target_dir}" init --quiet
      git -C "${target_dir}" symbolic-ref HEAD refs/heads/main
    else ui_note '本次未初始化 Git，基础环境仍有待处理项。'; fi
  else ui_text '✓ 已有 Git 仓库，保留现有分支、origin 和暂存区。'; fi
else
  ui_note '本次不写基础配置；客户端选择仅用于本次运行，不作为持久授权。'
fi

ui_heading '阶段 5/5 · 本地结果与开始工作'
readiness="$(project_info readiness --agents "${project_agents[@]}" --workflow "${active}")" || exit 1
if [[ "$(printf '%s' "${readiness}" | jq -r .ready)" == true && "${installation_failed}" == false && "${git_assets_failed}" == false ]]; then
  ui_text '✓ 本地配置就绪，待客户端加载确认'
else ui_warning '基础配置仍有待处理项；已有成果保留。'; fi
persisted="$(project_info metadata)" || exit 1
ui_text "项目：${target_dir}" "客户端（本次选择）：${project_agents[*]}" "工作方式（本次选择）：${active}"
printf '%s' "${persisted}" | jq -r '"  项目已保存的工作方式：\(.workflow)", "  项目已保存的客户端：\(.selected | join(", "))"'
if [[ "$(printf '%s' "${persisted}" | jq -r .workflow)" != "${active}" ]]; then
  ui_note '本次工作方式选择未写入配置；下面只提供起步建议，不代表已切换项目工作流。'
fi
printf '%s' "${readiness}" | jq -r '.clients[] | "  \(.id): \(.path) — 项目 Skill 入口 \(.skills | length) 个"'
printf '%s' "${readiness}" | jq -r '.issues[] | "  待处理：\(.)"'
printf '%s' "${readiness}" | jq -r '.notes[] | "  提示：\(.)"'
[[ "${installation_failed}" == false ]] || ui_warning '至少一个安装步骤失败或无法安全执行；未自动重试或覆盖。'
if [[ "$(printf '%s' "${readiness}" | jq -r '.git.head // ""')" == '' ]]; then
  ui_text '版本状态：尚未提交；正式资产目前仅在本地。'
else ui_text '版本状态：已有提交；本次改动未自动暂存或提交。'; fi
ui_text "忽略规则与政策引用：${git_assets_status}" '客户端加载：待所选客户端的新会话确认；文件存在不等于已加载。' \
  '首次提交检查：未执行；提交前须检查资产范围、敏感信息、大文件与符号链接。'
ui_section '下一步'
ui_text '1. 在所选客户端的新会话打开这个项目，先确认 AGENTS.md 与 Skills 被读取。' \
  '2. 让 Agent 说明它读取到的项目规则与可用能力；缺项先处理，不自动开发。'
case "${active}" in
  github-workflow) ui_text '3. 明确要求使用 github-workflow 处理首个任务；先检查本地 Git 并创建用途分支，远端 PR 可稍后接入。' ;;
  superpowers) ui_text '3. 从 using-superpowers 入口开始，描述第一个开发目标，先澄清需求再实现。' ;;
  bmad) ui_text '3. 使用 bmad-help 核对项目阶段，再选择需求、架构或实现入口。' ;;
  none) ui_text '3. 按已有方法描述第一个任务，要求 Agent 先给出方案与验证方式，再授权实施。' ;;
esac
ui_note '未接入 GitHub、没有业务测试或 CI，不影响基础配置阶段正常结束。'
if confirm '继续可选 GitHub 协作配置？'; then
  if [[ ! -f "${target_dir}/.agent/bootstrap.yml" ]]; then
    ui_warning '请先完成项目基础配置，再接入协作能力。'
    exit 0
  fi
  command -v gh >/dev/null || { ui_warning '可选协作需要 gh；基础配置已保留，没有安装依赖。'; exit 0; }
  # shellcheck disable=SC1091
  source "${repo_root}/scripts/lib/onboarding-handoff.sh"
  # shellcheck disable=SC1091
  source "${repo_root}/scripts/lib/onboarding-collaboration.sh"
  run_collaboration
else ui_note '本次在本地完成。需要协作配置时重新运行同一命令即可。'; fi
