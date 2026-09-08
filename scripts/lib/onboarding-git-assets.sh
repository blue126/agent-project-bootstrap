#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2034

git_assets_status='本次未检查或应用'
git_assets_failed=false
review_git_assets() {
  local preview token line
  local args=(--project "${target_dir}" --json)
  ui_section '版本控制规范与忽略规则'
  ui_text '共享 Agent 能力、锁文件和正式成果是项目资产；个人配置、凭据和运行状态留在本机。' \
    '下面只检查有限的项目路径并展示必要差异；不会暂存、提交、扫描凭据或删除文件。'
  preview="$(python3 "${repo_root}/scripts/configure-git-ignore.py" "${args[@]}")" || {
    git_assets_failed=true
    ui_warning '无法安全准备忽略规则，请先处理路径或文件冲突；原文件未覆盖。'; return 0;
  }
  while :; do
    while IFS= read -r line; do ui_text "${line}"; done < <(printf '%s' "${preview}" | jq -r '.facts.warnings[]')
    ui_note '当前被忽略的资产候选（含示例探针，最多显示 20 项；不自动放行）：'
    printf '%s' "${preview}" | jq -r '.facts.ignored_candidates[:20][] | "  \(.path) ← \(.source):\(.line) \(.rule)"'
    ui_note '已跟踪的本地状态候选（不会自动取消跟踪）：'
    printf '%s' "${preview}" | jq -r '.facts.tracked_local_candidates[:20][] | "  \(.)"'
    if [[ "$(printf '%s' "${preview}" | jq '.changes | length')" -gt 0 ]]; then
      ui_section '拟写入的精确差异'
      printf '%s' "${preview}" | jq -r '.changes[].diff'
      if confirm '应用以上忽略规则与政策引用差异？'; then
        token="$(printf '%s' "${preview}" | jq -r .token)"
        python3 "${repo_root}/scripts/configure-git-ignore.py" "${args[@]}" --apply --expect "${token}" >/dev/null || {
          git_assets_failed=true
          ui_warning '预览已过期或写入失败；请检查诊断并重跑，不覆盖冲突文件。'; return 0;
        }
        git_assets_status='已合并确认的差异；保留项仍需核对'
        ui_text '✓ 已应用确认的差异；既有规则保留，不代表首次提交检查通过。'
      else
        ui_note '本次保留原忽略规则与政策引用；下次会重新检查。'
        return 0
      fi
    else
      git_assets_status='已检查，无新增差异；保留项仍需核对'
      ui_note '无需新增忽略规则或政策引用；已有冲突仍需人工核对。'
    fi
    [[ "$(printf '%s' "${preview}" | jq '.facts.legacy_skill_ignores | length')" -gt 0 && ${#args[@]} -eq 3 ]] || break
    ui_warning '旧版 Skills 整目录忽略仍在生效。迁移可能暴露原本仅在本机的文件，须先核对用途与敏感信息。'
    if ! confirm '查看旧版 Skills 忽略规则迁移差异？'; then break; fi
    args+=(--migrate-skills)
    preview="$(python3 "${repo_root}/scripts/configure-git-ignore.py" "${args[@]}")" || return 0
  done
  ui_note '完整路径诊断可用 configure-git-ignore.py --project DIR 查看；这不是敏感信息扫描器。'
}
