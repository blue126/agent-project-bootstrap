#!/usr/bin/env bash
# shellcheck disable=SC2154
# Optional collaboration; called only after the local summary and explicit opt-in.

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

run_collaboration() {
  ui_heading '可选协作 · Git/GitHub'
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
  ui_heading '可选协作 · 验证、CI、审查与保护'
  ui_section '本地验证'
  if check_evidence --kind local --evidence "${target_dir}/.agent/runtime/onboarding/local-evidence.json" >/dev/null 2>&1; then
    ui_text '✓ 已核实本地验证执行证据。'
  elif confirm '让目标项目 Agent 协助准备并实际验证？'; then
    handoff_validation
  else ui_note '本次不配置本地验证。'; fi

  if [[ -n "${remote_repo}" ]]; then
    ui_section 'GitHub CI'
    ci_verified=false
    if ci_result="$(check_evidence --kind ci --repo "${remote_repo}" --discover)"; then
      for directory in "${target_dir}/.agent" "${target_dir}/.agent/runtime" "${target_dir}/.agent/runtime/onboarding"; do
        handoff_require_safe_path "${directory}" || return 1
      done
      mkdir -p "${target_dir}/.agent/runtime/onboarding"
      ci_file="$(mktemp "${target_dir}/.agent/runtime/onboarding/ci-evidence.XXXXXX")"
      printf '%s\n' "${ci_result}" > "${ci_file}"
      ci_verified=true
      ui_text '✓ 已核实当前默认分支的 CI。'
    else
      ui_note '尚未发现当前项目版本的有效 GitHub CI 证据。'
      if confirm '让项目 Agent 协助准备 CI？'; then pause_for_agent '检查现有验证与 CI，复用已有配置。需要发布时先明确展示文件范围并取得授权；不能套用 bootstrap 自身的测试。'; fi
    fi
    ui_section '自动审查'
    if confirm '验证 PR 的自动审查反馈，或查看 Claude Auto Review 安装指引？'; then
      while :; do
        ask 'PR 编号 [正整数，s 查看安装指引，b 暂不验证，q 退出]:'
        case "${reply}" in
          s|S)
            pause_for_agent '在此项目的 Claude Code 交互会话运行 /install-github-app，核对仓库和授权，然后在实际 PR 上获得审查反馈。重跑后输入该 PR 编号核实反馈。' ;;
          b|B|'') ui_note '本次不验证审查反馈。'; break ;;
        esac
        if [[ ! "${reply}" =~ ^[1-9][0-9]*$ ]]; then
          ui_warning '请输入正整数 PR 编号、s 或 b。'
          continue
        fi
        if check_evidence --kind review --repo "${remote_repo}" --pr "${reply}" --discover >/dev/null; then
          ui_text '✓ 已核实该 PR 当前版本的 bot 审查反馈（仅验证集成，不是合并批准，也不证明特定 Claude App 身份）。'
        else
          ui_warning '审查反馈尚未验证；请核对 PR、HEAD、工作区和集成状态。'
          if confirm '查看人工安装/排查指引？'; then
            pause_for_agent '检查目标 PR 的当前 HEAD 与 bot 反馈；需要 Claude Auto Review 时由用户运行 /install-github-app。不要把已有无关 bot 反馈当作 Claude 安装证明。'
          fi
        fi
        break
      done
    else ui_note '本次不接入自动审查。'; fi
    if [[ "${ci_verified}" == true ]]; then
      ui_section '合并保护'
      if check_evidence --kind protection --repo "${remote_repo}" --evidence "${ci_file}" >/dev/null; then
        ui_text '✓ 已有合并门槛有效，保持现状。'
      elif confirm '查看并配置基于本项目 CI 的推荐保护？'; then
        args=(--repo "${remote_repo}" --profile consumer --project "${target_dir}" --evidence "${ci_file}" --with-pr-policy)
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

}
