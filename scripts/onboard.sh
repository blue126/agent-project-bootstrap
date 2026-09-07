#!/usr/bin/env bash
# shellcheck disable=SC2154
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="$(pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) [[ $# -ge 2 ]] || exit 2; target_dir="$2"; shift 2 ;;
    --onboard) shift ;;
    -h|--help)
      printf '%s\n' 'Usage: onboard.sh [--target DIR]'
      exit 0 ;;
    *) echo "Unknown onboarding argument: $1" >&2; exit 2 ;;
  esac
done
for tool in jq git python3; do
  command -v "${tool}" >/dev/null || { echo "${tool} is required; no dependency was installed" >&2; exit 2; }
done
if [[ -n "${AI_AGENT:-}" || -n "${CODEX_SANDBOX:-}" || -n "${CODEX_CI:-}" || -n "${CODEX_THREAD_ID:-}" ]]; then
  echo 'An Agent process cannot host the interactive bootstrap selectors.' >&2
  echo '请由用户在正常终端运行；不要清除 Agent 检测变量或使用 Agent PTY。' >&2
  exit 2
fi
[[ -t 0 && -t 1 ]] || { echo '完整接入需要真实交互终端。' >&2; exit 2; }
target_dir="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${target_dir}")"
[[ ! -e "${target_dir}" || -d "${target_dir}" ]] || { echo '目标不是目录' >&2; exit 2; }
git_probe="${target_dir}"
while [[ ! -d "${git_probe}" ]]; do git_probe="$(dirname "${git_probe}")"; done
git_root="$(git -C "${git_probe}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "${git_root}" && "$(cd "${git_root}" && pwd -P)" != "${target_dir}" ]]; then
  echo "目标位于另一个 Git 仓库内，请先确认项目边界：${git_root}" >&2
  exit 2
fi
if [[ -d "${target_dir}" ]]; then
  python3 - "${target_dir}" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
for name in ('.agent', '.agents', '.claude'):
    if not (root / name).resolve().is_relative_to(root):
        raise SystemExit(f'项目配置路径指向目标以外，先处理目录范围：{name}')
PY
fi
# shellcheck disable=SC1091
source "${repo_root}/scripts/lib/onboarding-ui.sh"
# shellcheck disable=SC1091
source "${repo_root}/scripts/lib/onboarding-handoff.sh"
ui_init
mkdir -p "${target_dir}"

ui_overview "${target_dir}"
if [[ -f "${target_dir}/.agent/bootstrap.yml" ]]; then
  ui_note '发现已有 bootstrap 配置，将保留并重新核实实际能力。'
fi
while :; do
  ask '开始接入？[y 开始，i 查看完整说明，n 退出]:'
  case "${reply}" in
    y|Y|yes|YES) break ;;
    i|I)
      ui_details
      ui_return_from_details ;;
    n|N|no|NO) exit 0 ;;
    '') ui_warning '请选择 y 开始、i 查看完整说明、n 退出，或 q 结束本次运行。' ;;
    *) ui_warning '请输入 y、i、n 或 q。' ;;
  esac
done

skill_roots() { printf '%s\n' "${target_dir}/.agents/skills" "${target_dir}/.claude/skills"; }
known_workflows() {
  local configured="" candidate root found
  if [[ -f "${target_dir}/.agent/bootstrap.yml" ]]; then
    configured="$(awk -F': ' '/^workflow_id:/ {print $2; exit}' "${target_dir}/.agent/bootstrap.yml")"
  fi
  for candidate in github-workflow superpowers bmad; do
    if [[ "${configured}" == "${candidate}" ]]; then printf '%s\n' "${candidate}"; continue; fi
    case "${candidate}" in
      github-workflow|superpowers)
        found=false
        while IFS= read -r root; do
          if [[ "${candidate}" == github-workflow && -s "${root}/github-workflow/SKILL.md" ]] ||
             [[ "${candidate}" == superpowers && -s "${root}/using-superpowers/SKILL.md" ]]; then found=true; fi
        done < <(skill_roots)
        [[ "${found}" != true ]] || printf '%s\n' "${candidate}" ;;
      bmad)
        [[ ! -s "${target_dir}/_bmad/_config/manifest.yaml" || ! -s "${target_dir}/_bmad/_config/bmad-help.csv" ]] || echo bmad ;;
    esac
  done
}
run_installer() { (cd "${target_dir}" && "$@"); }

handoff_validation() {
  local handoff_path facts
  handoff_path="$(handoff_write_validation "${remote_repo:-}")" || {
    ui_warning '无法安全写入交接任务文件；项目路径可能包含冲突或链接。'
    exit 1
  }
  facts="$(handoff_facts "${remote_repo:-}")"
  ui_heading '需要项目 Agent 协助：准备本地验证'
  ui_section '为什么在这里停止'
  ui_text '尚未发现可验证的本地检查结果。' \
    'bootstrap 不猜测这个项目的构建、测试或依赖安装命令。'
  ui_section '已知项目事实（受限扫描）'
  while IFS= read -r fact; do ui_text "${fact}"; done <<< "${facts}"
  ui_section '你现在要做什么'
  ui_text '1. 在目标项目打开 Agent 会话。' \
    '2. 让 Agent 阅读下面的任务文件。' \
    '3. 完成或明确阻塞后，重新运行同一条 bootstrap 命令。'
  ui_section '任务文件'
  ui_text "${handoff_path}"
  ui_note '任务文件不提供运行、依赖、Git 或远端操作授权；它只说明要先调查和提出方案。'
  ui_note '本次终端向导将在这里结束，不会自动启动 Agent。'
  exit 3
}

workflows="$(known_workflows)"
if [[ -n "${workflows}" ]]; then
  ui_heading '阶段 1/6 · 已有工作流'
  ui_note '保持现状，不重装或切换：'
  while IFS= read -r item; do ui_text "✓ ${item}"; done <<< "${workflows}"
else
  ui_heading '阶段 1/6 · 未检测到内置工作流'
  if [[ -e "${target_dir}/_bmad" || -L "${target_dir}/_bmad" ]]; then
    ui_warning '发现不完整的 BMAD 目录；不会覆盖。请先核对安装状态。'
  fi
  ui_text '1) github-workflow — 分支、提交、PR 与审查，适合 GitHub 协作' \
    '2) Superpowers — 设计、计划、测试和审查，适合功能开发、修复与重构' \
    '3) BMAD — 需求、架构、任务拆分与实现，适合新产品和系统性迭代' \
    '4) 不安装 — 不新增内置工作流，保持项目现状'
  while :; do
    ask '安装选择 [1-4，无默认，q 退出]:'
    case "${reply}" in
      1) selected=github-workflow; break ;;
      2) selected=superpowers; break ;;
      3) selected=bmad; break ;;
      4) selected=none; break ;;
      '') ui_warning '请选择 1、2、3 或 4；空输入不会跳过此阶段。' ;;
      *) ui_warning '请选择 1、2、3 或 4。' ;;
    esac
  done
  case "${selected}" in
    none) ui_note '本次不新增内置工作流；不判断或修改其他已有流程。' ;;
    github-workflow)
      run_installer npx skills@1.5.23 add "${repo_root}" --skill github-workflow || pause_for_agent '工作流安装未完成，请核对已有产物。' ;;
    superpowers)
      resolved="$(git ls-remote https://github.com/obra/superpowers.git 'refs/tags/v6.3.0' 'refs/tags/v6.3.0^{}')"
      pin="$(printf '%s\n' "${resolved}" | awk '/\^\{\}$/ {print $1; found=1; exit} END {if (!found) print ""}')"
      [[ -n "${pin}" ]] || pin="$(printf '%s\n' "${resolved}" | awk 'NR==1 {print $1}')"
      [[ "${pin}" == b36e0829c6d0140e93cfef2ca599b1b07d4a7797 ]] || pause_for_agent 'Superpowers 固定版本校验失败，未执行安装。'
      run_installer npx skills@1.5.23 add https://github.com/obra/superpowers/tree/v6.3.0 || pause_for_agent 'Superpowers 安装未完成，请检查后重跑。' ;;
    bmad)
      ui_text '将使用 BMAD 6.12.0 官方交互安装器；模块、工具和配置在其中选择。'
      confirm "确认在 ${target_dir} 安装 BMAD？" || { ui_note '本次不安装 BMAD。'; }
      if [[ "${reply}" == y || "${reply}" == Y || "${reply}" == yes || "${reply}" == YES ]]; then
        run_installer npx bmad-method@6.12.0 install --directory "${target_dir}" || pause_for_agent 'BMAD 安装未完成；保留已有产物并核对后重跑。'
      fi ;;
  esac
fi

# Every run reflects real project skill paths. Choosing not to open the installer
# now does not become a stored decision.
ui_heading '阶段 2/6 · 普通技能'
skill_count="$(find "${target_dir}/.agents/skills" "${target_dir}/.claude/skills" -name SKILL.md -print 2>/dev/null | wc -l | tr -d ' ' || true)"
if [[ "${skill_count:-0}" -gt 0 ]]; then
  ui_text "✓ 发现项目内 ${skill_count} 个技能入口，保留现有安装。"
else
  ui_text '技能是按需使用的操作指南，安装不会自动执行任务。' \
    '官方界面会让你选择技能、Agent、项目/全局作用域和链接方式。'
  if confirm '进入技能选择？'; then
    run_installer npx skills@1.5.23 add "${repo_root}" || pause_for_agent '技能安装中断或失败，请核对已有产物后重跑。'
    ui_note '请核对原生安装器报告的作用域；Universal 是共享目录兼容性，不代表安装了这些 Agent 应用。'
  else ui_note '本次不添加普通技能。'; fi
fi

ui_section 'Understand Anything · 可选项目集成'
if [[ -d "${target_dir}/.agent/runtime/understand-anything/repo/.git" ]]; then
  ui_text '✓ 项目运行时已存在，保留现有安装。'
else
  ui_text '用于理解已有代码的结构与依赖。' \
    '已有项目（brownfield）或接手维护时通常更有价值；空项目可先跳过。'
  ui_section '安装影响'
  ui_text '• 下载固定版本运行时到 .agent/runtime，并建立项目技能链接。' \
    '• 占用网络和磁盘；不改全局插件，不自动扫描代码或启动服务。'
  ui_note '后续分析可能耗时并产生模型费用，本地安装不等于完全离线。'
  if confirm '安装到当前项目？'; then
    "${repo_root}/scripts/install-understand-anything.sh" --target "${target_dir}" || pause_for_agent '运行时安装未完成，保留已有状态并核对后重跑。'
  else ui_note '本次不安装 Understand Anything，继续到项目规范。'; fi
fi

ui_heading '阶段 3/6 · 项目规范'
if [[ -f "${target_dir}/.agent/bootstrap.yml" ]]; then
  ui_text '✓ 已有 bootstrap 管理记录；将只刷新未修改的受管文件。'
  if confirm '检查并更新项目规范？'; then
    "${repo_root}/scripts/bootstrap.sh" --target "${target_dir}" --update || pause_for_agent '政策更新存在问题，请保留本地修改并检查诊断。'
  else ui_note '本次不更新项目规范。'; fi
else
  ui_text '将建立必要的 AGENTS.md、CLAUDE.md 和 .agent 政策/配置；不提交或发布。'
  if confirm '检查并建立项目规范？'; then
    # A new selection remains a configuration only; bootstrap does not execute it.
    active="none"
    if [[ -n "${workflows}" ]]; then active="$(printf '%s\n' "${workflows}" | head -n1)";
    elif [[ "${selected:-none}" != none ]]; then active="${selected}"; fi
    arguments=(--target "${target_dir}" --workflow "${active}" --skip-skills --skip-understand-anything --skip-superpowers --adopt-existing)
    [[ "${active}" != github-workflow ]] || arguments+=(--skip-claude-auto-review)
    "${repo_root}/scripts/bootstrap.sh" "${arguments[@]}" || pause_for_agent '项目规范存在冲突，请审阅拟添加的政策引用，不覆盖已有内容。'
  else ui_note '本次不建立项目规范。'; fi
fi

ui_heading '阶段 4/6 · Git/GitHub'
ui_text '已有配置保留；创建或连接远端不会自动提交或上传项目代码。'
origin="$(git -C "${target_dir}" remote get-url origin 2>/dev/null || true)"
remote_repo=""
if [[ "${origin}" =~ ^https://github\.com/([^/[:space:]]+)/([^/[:space:]]+)/?$ ]]; then remote_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}";
elif [[ "${origin}" =~ ^git@github\.com:([^/[:space:]]+)/([^/[:space:]]+)$ ]]; then remote_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"; fi
if [[ -n "${origin}" && -n "${remote_repo}" ]]; then
  if gh repo view "${remote_repo}" --json nameWithOwner --jq .nameWithOwner > /dev/null; then ui_text "✓ 已连接 ${remote_repo}，保留并继续。";
  else ui_warning '已有 GitHub origin 无法验证；将保留它。本次可继续本地配置。'; remote_repo=""; fi
elif [[ -n "${origin}" ]]; then
  ui_warning '已有非 GitHub origin，将保留且不替换。'
else
  while :; do
    ui_section '尚无 origin · 请选择接入方式'
    ui_text '1) 创建 GitHub 仓库' '2) 连接已有 GitHub 仓库' '3) 本次不接入，继续本地验证'
    ask 'GitHub 操作 [1-3，无默认，q 退出]:'
    case "${reply}" in
      1|2) mode="${reply}" ;;
      3) ui_note '本次不接入 GitHub。下次运行仍会重新提供此选项。'; break ;;
      '') ui_warning '请选择 1、2 或 3；空输入不会跳过 GitHub。'; continue ;;
      *) ui_warning '请选择 1、2 或 3；尚未执行任何操作。'; continue ;;
    esac
    if [[ "${mode}" == 1 ]]; then ui_section '创建新仓库'; else ui_section '连接已有仓库'; fi
    while :; do
      ask '仓库 OWNER/REPOSITORY [必填，b 返回上一级，q 退出]:'
      case "${reply}" in
        b|B) break ;;
        '') ui_warning '仓库名称不能为空；请输入 OWNER/REPOSITORY 或 b 返回。'; continue ;;
      esac
      if [[ ! "${reply}" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$ || "${reply##*/}" == . || "${reply##*/}" == .. ]]; then
        ui_warning '格式不正确，例如 your-account/your-project。'; continue
      fi
      draft_repo="${reply}"; break
    done
    [[ "${reply}" != b && "${reply}" != B ]] || continue
    arguments=(--source "${target_dir}" --repo "${draft_repo}")
    if [[ "${mode}" == 1 ]]; then
      while :; do
        ask '可见性 private/public/internal [默认private，b 返回，q 退出]:'
        case "${reply}" in b|B) break ;; private|public|internal|'') visibility="${reply:-private}"; break ;; *) ui_warning '请输入 private、public 或 internal。' ;; esac
      done
      [[ "${reply}" != b && "${reply}" != B ]] || continue
      arguments+=(--create-only --visibility "${visibility}")
      action="创建 ${visibility} 仓库"
    else arguments+=(--attach-only); action='连接已有仓库'; fi
    ui_section '操作确认'
    ui_text "项目：${target_dir}" "操作：${action} ${draft_repo}" '影响：按需初始化本地 Git 并设置 origin；不提交、不推送。'
    if ! confirm '确认执行？'; then ui_note '未执行操作，已返回接入方式选择。'; continue; fi
    "${repo_root}/scripts/create-github.sh" "${arguments[@]}" || pause_for_agent '远端操作未完成；下次运行将重新检查真实仓库和 origin。'
    remote_repo="${draft_repo}"
    break
  done
fi

check_evidence() {
  local arguments=("$@")
  if ! git -C "${target_dir}" rev-parse --git-dir >/dev/null 2>&1; then
    arguments+=(--key-dir "${target_dir}/.agent/runtime/onboarding")
  fi
  "${repo_root}/scripts/check-bootstrap-evidence.sh" --project "${target_dir}" "${arguments[@]}"
}
ui_heading '阶段 5/6 · 项目验证、CI、审查与保护'
ui_section '本地验证'
if check_evidence --kind local --evidence "${target_dir}/.agent/runtime/onboarding/local-evidence.json" >/dev/null 2>&1; then
  ui_text '✓ 已核实本地验证执行证据。'
elif confirm '让目标项目 Agent 协助准备并实际验证？'; then
  handoff_validation
else ui_note '本次不配置本地验证。'; fi

if [[ -n "${remote_repo}" ]]; then
  ui_section 'GitHub CI'
  if check_evidence --kind ci --repo "${remote_repo}" --discover >/dev/null; then
    "${repo_root}/scripts/check-bootstrap-evidence.sh" --project "${target_dir}" --kind ci --repo "${remote_repo}" --discover > "${target_dir}/.agent/runtime/onboarding/ci-evidence.json"
    ui_text '✓ 已核实当前默认分支的 CI。'
  else
    ui_note '尚未发现当前项目版本的有效 GitHub CI 证据。'
    if confirm '让项目 Agent 协助准备 CI？'; then pause_for_agent '检查现有验证与 CI，复用已有配置。需要发布时先明确展示文件范围并取得授权；不能套用 bootstrap 自身的测试。'; fi
  fi
  ui_section '自动审查'
  if confirm '接入/验证 Claude Auto Review？（不替代测试，也不会自动批准合并）'; then
    pause_for_agent '在此项目的 Claude Code 交互会话运行 /install-github-app，核对仓库和授权，然后在实际 PR 上获得审查反馈。重跑 bootstrap 会重新核实。'
  else ui_note '本次不接入自动审查。'; fi
  if [[ -f "${target_dir}/.agent/runtime/onboarding/ci-evidence.json" ]]; then
    ui_section '合并保护'
    if check_evidence --kind protection --repo "${remote_repo}" --evidence "${target_dir}/.agent/runtime/onboarding/ci-evidence.json" >/dev/null; then
      ui_text '✓ 已有合并门槛有效，保持现状。'
    elif confirm '查看并配置基于本项目 CI 的推荐保护？'; then
      args=(--repo "${remote_repo}" --profile consumer --project "${target_dir}" --evidence "${target_dir}/.agent/runtime/onboarding/ci-evidence.json" --with-pr-policy)
      "${repo_root}/scripts/configure-github.sh" "${args[@]}" --dry-run || pause_for_agent '无法安全生成保护差异，请检查现有规则与 CI 证据。'
      if confirm '确认应用刚才展示的保护差异？'; then
        "${repo_root}/scripts/configure-github.sh" "${args[@]}" || pause_for_agent '保护配置或回读失败。'
        ui_text '✓ 合并门槛已回读验证。'
      else
        ui_note '本次不修改保护。'
      fi
    else
      ui_note '本次保持现有保护。'
    fi
  else
    ui_note 'CI 尚未验证，不配置合并保护或原生自动合并。'
  fi
else
  ui_note '本次未接入 GitHub：仅完成可用的本地验证；CI、审查和远端保护未配置。'
fi

ui_heading '阶段 6/6 · 总体验收'
ui_text "项目：${target_dir}"
if [[ -n "$(known_workflows)" ]]; then
  ui_text "✓ 工作流：$(known_workflows | tr '\n' ' ')"
else
  ui_text '— 工作流：本次未发现或安装内置工作流'
fi
if [[ -f "${target_dir}/.agent/bootstrap.yml" ]]; then
  ui_text '✓ 项目规范：已建立/保留'
else
  ui_text '— 项目规范：本次未建立'
fi
if [[ -n "${remote_repo}" ]]; then
  ui_text "✓ GitHub：${remote_repo}"
else
  ui_text '— GitHub：本次未接入'
fi
if [[ -f "${target_dir}/.agent/runtime/onboarding/ci-evidence.json" ]]; then
  ui_text '✓ GitHub CI：存在当前实证'
else
  ui_text '— GitHub CI：本次未验证'
fi
ui_note '下次运行同一命令会重新检查项目实际状态和尚未配置的能力。'
