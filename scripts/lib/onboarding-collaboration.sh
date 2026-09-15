#!/usr/bin/env bash
# shellcheck disable=SC2154
# Optional collaboration; called only after the local summary and explicit opt-in.

ci_pending_next_steps() {
  ui_section '下一步'
  ui_text '1. 在项目有实际实现后，按项目自身材料补入真实的构建、测试或检查命令。' \
    '2. 审阅、提交并推送该 CI 变更，让 GitHub Actions 在真实提交上运行。' \
    '3. 重新运行 bootstrap；只有当前提交的 CI 成功后，才会继续审查验证与合并保护。'
  ui_note '这个骨架没有测试任何代码，也不是可设为 required check 的绿色占位符。'
}

ci_prepare_or_report() {
  local state skeleton
  state="$(ci_skeleton_state)"
  skeleton="$(ci_skeleton_path)"
  case "${state}" in
    missing)
      ui_section 'GitHub CI'
      ui_text '当前项目还没有 CI workflow。可以先放入一个待补全的 CI 骨架。' \
        '它不会猜测技术栈、下载依赖、运行代码或产生绿色检查。'
      ui_text "目标：${skeleton}" '内容：仅手动触发、最小只读权限、明确失败的 pending job。'
      if confirm '创建待补全的 CI 骨架？'; then
        if skeleton="$(ci_write_skeleton)"; then
          ui_text "✓ 已创建待补全 CI 骨架：${skeleton}"
          ci_pending_next_steps
        else
          ui_warning '无法安全创建 CI 骨架；已保留所有现有文件。'
        fi
      else
        ui_note '本次不写 CI 骨架。项目有实际实现后可重新运行此向导。'
      fi
      return 1
      ;;
    scaffold_pending)
      ui_section 'GitHub CI'
      ui_text "待补全 CI 骨架仍在：${skeleton}" \
        '它不代表 CI 已运行或验证通过；向导不会覆盖它。'
      ci_pending_next_steps
      return 1
      ;;
    unsafe)
      ui_warning '检测到 .github、workflows 或 ci.yml 使用符号链接；为避免写入目标外路径，本次不处理 CI。'
      return 1
      ;;
    configured_unverified) return 0 ;;
    *) ui_warning '无法识别 CI 状态；已保留文件且不配置保护。'; return 1 ;;
  esac
}

run_collaboration() {
  ui_heading '可选协作 · 建立 GitHub CI 与协作保障'
  ui_text '已有配置保留；创建或连接远端不会自动提交或上传项目代码。' \
    'CI、审查和合并保护只会根据真实的当前 GitHub evidence 前进。'
  origin="$(git -C "${target_dir}" remote get-url origin 2>/dev/null || true)"
  remote_repo=""
  if [[ "${origin}" =~ ^https://github\.com/([^/[:space:]]+)/([^/[:space:]]+)/?$ ]]; then remote_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}";
  elif [[ "${origin}" =~ ^git@github\.com:([^/[:space:]]+)/([^/[:space:]]+)$ ]]; then remote_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"; fi
  if [[ -n "${origin}" && -n "${remote_repo}" ]]; then
    if gh repo view "${remote_repo}" --json nameWithOwner --jq .nameWithOwner > /dev/null; then ui_text "✓ 已连接 ${remote_repo}，保留并继续。";
    else ui_warning '已有 GitHub origin 无法验证；将保留它。本次仍可准备本地 CI 骨架。'; remote_repo=""; fi
  elif [[ -n "${origin}" ]]; then
    ui_warning '已有非 GitHub origin，将保留且不替换。仍可准备本地 CI 骨架。'
  else
    while :; do
      ui_section '尚无 origin · 请选择接入方式'
      ui_text '1) 创建 GitHub 仓库' '2) 连接已有 GitHub 仓库' '3) 暂不接入，仅准备 CI 骨架'
      ask 'GitHub 操作 [1-3，无默认，q 退出]:'
      case "${reply}" in
        1|2) mode="${reply}" ;;
        3) ui_note '本次不连接 GitHub；仍可准备本地 CI 骨架。'; break ;;
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

  if ! ci_prepare_or_report; then
    return 0
  fi

  ui_section 'GitHub CI'
  ci_verified=false
  ci_file=""
  if [[ -z "${remote_repo}" ]]; then
    ui_note '已发现项目自己的 CI workflow，但尚未连接可验证的 GitHub 仓库。审阅、远端 CI evidence 和合并保护保持待定。'
    return 0
  fi
  if ! git -C "${target_dir}" rev-parse --verify HEAD >/dev/null 2>&1; then
    ui_note '已发现项目自己的 CI workflow，但本地尚无提交；先审阅、提交并推送项目资产，再重新运行以核实 GitHub CI。'
    return 0
  fi
  if ci_result="$(check_evidence --kind ci --repo "${remote_repo}" --discover)"; then
    for directory in "${target_dir}/.agent" "${target_dir}/.agent/runtime" "${target_dir}/.agent/runtime/onboarding"; do
      ci_require_safe_path "${directory}" || return 1
    done
    mkdir -p "${target_dir}/.agent/runtime/onboarding"
    ci_file="$(mktemp "${target_dir}/.agent/runtime/onboarding/ci-evidence.XXXXXX")"
    printf '%s\n' "${ci_result}" > "${ci_file}"
    ci_verified=true
    ui_text '✓ 已核实当前默认分支的 CI。'
  else
    ui_note '已发现 CI workflow，但尚未发现当前项目版本的有效 GitHub CI evidence。' \
      '审阅并发布真实项目检查后重新运行；不会把 workflow 文件本身当成通过。'
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
}
