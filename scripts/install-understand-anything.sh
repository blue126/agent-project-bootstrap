#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
upstream="https://github.com/Egonex-AI/Understand-Anything.git"
ref="f08763d11d0202a8a8f52b5dedda6d1b2e2ebac8"
patch_file="${repo_root}/integrations/understand-anything/patches/project-scope-and-git-hardening.patch"
target_dir="$(pwd)"
claude_selected=false

usage() {
  cat <<'EOF'
Usage: scripts/install-understand-anything.sh [--target DIR] [--agent ID ...]

Install the pinned Understand Anything integration into one project only.
Supported agents: claude-code, codex, opencode, universal. Repeat --agent to
select multiple clients. Omitting --agent retains the legacy shared links.
Canonical .agents/skills links are always retained for runtime compatibility;
selecting claude-code also creates project-local .claude/skills links.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || { echo "--target requires a directory" >&2; exit 2; }
      target_dir="$2"
      shift 2
      ;;
    --agent)
      [[ $# -ge 2 ]] || { echo "--agent requires an ID" >&2; exit 2; }
      case "$2" in
        claude-code) claude_selected=true ;;
        codex|opencode|universal) ;;
        *) echo "Unsupported agent: $2" >&2; exit 2 ;;
      esac
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${BOOTSTRAP_INTEGRATION_TESTING:-0}" == 1 ]]; then
  upstream="${UNDERSTAND_ANYTHING_TEST_UPSTREAM:?Set UNDERSTAND_ANYTHING_TEST_UPSTREAM}"
  ref="${UNDERSTAND_ANYTHING_TEST_REF:?Set UNDERSTAND_ANYTHING_TEST_REF}"
  patch_file="${UNDERSTAND_ANYTHING_TEST_PATCH:-}"
fi

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
[[ -d "${target_dir}" ]] || { echo "Target directory does not exist: ${target_dir}" >&2; exit 1; }
target_dir="$(cd "${target_dir}" && pwd)"

runtime_parent="${target_dir}/.agent/runtime/understand-anything"
runtime_dir="${runtime_parent}/repo"
skills_dir="${target_dir}/.agents/skills"
upstream_skills="understand-anything-plugin/skills"

# Installation may precede bootstrap's broad runtime policy. Protect only this
# integration's checkout and staging directories without owning or replacing
# .agent/runtime/.gitignore (bootstrap installs that policy later).
skill_roots=("${skills_dir}")
installation_directories=("${target_dir}/.agent" "${target_dir}/.agent/runtime" "${runtime_parent}" "${runtime_dir}" "${target_dir}/.agents" "${skills_dir}")
if [[ "${claude_selected}" == true ]]; then
  skill_roots+=("${target_dir}/.claude/skills")
  installation_directories+=("${target_dir}/.claude" "${target_dir}/.claude/skills")
fi
for directory in "${installation_directories[@]}"; do
  [[ ! -L "${directory}" ]] || { echo "Refusing a symbolic-link installation directory: ${directory}" >&2; exit 1; }
  [[ ! -e "${directory}" || -d "${directory}" ]] || { echo "Installation directory is not a directory: ${directory}" >&2; exit 1; }
done
runtime_ignore="${runtime_parent}/.gitignore"
[[ ! -L "${runtime_ignore}" ]] || { echo "Refusing a symbolic-link runtime ignore file" >&2; exit 1; }
mkdir -p "${runtime_parent}"
for pattern in '/repo/' '/.install.*/'; do
  if [[ ! -f "${runtime_ignore}" ]] || ! grep -Fxq "${pattern}" "${runtime_ignore}"; then
    printf '\n%s\n' "${pattern}" >> "${runtime_ignore}"
  fi
done

verify_runtime() {
  actual_ref="$(git -C "${runtime_dir}" rev-parse HEAD 2>/dev/null || true)"
  if [[ "${actual_ref}" != "${ref}" ]]; then
    echo "Understand Anything runtime is at '${actual_ref:-unknown}', expected ${ref}; refusing to replace it" >&2
    exit 1
  fi
  if [[ -n "${patch_file}" ]] && ! git -C "${runtime_dir}" apply --unidiff-zero --reverse --check "${patch_file}" >/dev/null 2>&1; then
    echo "Understand Anything compatibility patch is missing or has drifted" >&2
    exit 1
  fi
}

if [[ -e "${runtime_dir}" ]]; then
  [[ -d "${runtime_dir}/.git" ]] || { echo "Runtime path exists but is not the managed checkout: ${runtime_dir}" >&2; exit 1; }
  verify_runtime
else
  mkdir -p "${runtime_parent}"
  temp_dir="$(mktemp -d "${runtime_parent}/.install.XXXXXX")"
  cleanup() {
    rm -rf -- "${temp_dir}"
  }
  trap cleanup EXIT

  git clone --no-checkout "${upstream}" "${temp_dir}/repo"
  git -C "${temp_dir}/repo" checkout --detach "${ref}"
  actual_ref="$(git -C "${temp_dir}/repo" rev-parse HEAD)"
  [[ "${actual_ref}" == "${ref}" ]] || {
    echo "Upstream ref resolved to ${actual_ref}, expected ${ref}" >&2
    exit 1
  }
  if [[ -n "${patch_file}" ]]; then
    git -C "${temp_dir}/repo" apply --unidiff-zero --check "${patch_file}"
    git -C "${temp_dir}/repo" apply --unidiff-zero "${patch_file}"
  fi
  mv "${temp_dir}/repo" "${runtime_dir}"
  trap - EXIT
  cleanup
  verify_runtime
fi

[[ -d "${runtime_dir}/${upstream_skills}" ]] || {
  echo "Pinned checkout does not contain the expected Skills directory" >&2
  exit 1
}

# Preflight the complete canonical + client link set before creating any links.
# A collision in the last Skill/client must not leave earlier links installed.
destinations=()
relative_targets=()
for skill_root in "${skill_roots[@]}"; do
  for skill_source in "${runtime_dir}/${upstream_skills}"/*; do
    [[ -d "${skill_source}" && -f "${skill_source}/SKILL.md" ]] || continue
    skill_name="$(basename "${skill_source}")"
    destination="${skill_root}/${skill_name}"
    relative_target="../../.agent/runtime/understand-anything/repo/${upstream_skills}/${skill_name}"
    if [[ -L "${destination}" ]]; then
      [[ "$(readlink "${destination}")" == "${relative_target}" ]] || {
        echo "Skill link already exists with a different target: ${destination}" >&2
        exit 1
      }
    elif [[ -e "${destination}" ]]; then
      echo "Skill path already exists; refusing to overwrite it: ${destination}" >&2
      exit 1
    fi
    destinations+=("${destination}")
    relative_targets+=("${relative_target}")
  done
done
for skill_root in "${skill_roots[@]}"; do
  mkdir -p "${skill_root}"
done
for ((index=0; index<${#destinations[@]}; index++)); do
  if [[ ! -L "${destinations[index]}" ]]; then
    ln -s "${relative_targets[index]}" "${destinations[index]}"
  fi
done

echo "Installed project-scoped Understand Anything at ${target_dir}"
echo "No user-level Skill or plugin directory was modified."
