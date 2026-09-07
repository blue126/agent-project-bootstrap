#!/usr/bin/env bash
# shellcheck disable=SC2154
# Safe, bounded project facts and task artifact generation for onboarding.
# Sourced only after the user explicitly selects Agent assistance.

handoff_require_safe_path() {
  local path="${1:?path required}" current=""
  case "${path}" in
    "${target_dir}"/*) ;;
    *) echo "Handoff path escapes target" >&2; return 1 ;;
  esac
  current="${target_dir}"
  local suffix="${path#"${target_dir}"/}" segment
  IFS=/ read -r -a segments <<< "${suffix}"
  for segment in "${segments[@]}"; do
    current="${current}/${segment}"
    [[ ! -L "${current}" ]] || { echo "Refusing handoff symlink path: ${current}" >&2; return 1; }
  done
}

handoff_facts() {
  python3 - "${target_dir}" "$1" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
remote = sys.argv[2]

def item(path, label=None):
    if (root / path).exists() and not (root / path).is_symlink():
        print(f'- {label or path}: detected')

print(f'- Project root: `{root}`')
print(f'- AGENTS.md: {"detected" if (root / "AGENTS.md").is_file() else "not detected"}')
print(f'- CLAUDE.md: {"detected" if (root / "CLAUDE.md").is_file() else "not detected"}')
print(f'- Bootstrap configuration: {"detected" if (root / ".agent/bootstrap.yml").is_file() else "not detected"}')
probe = subprocess.run(['git', '-C', str(root), 'rev-parse', '--git-dir'], capture_output=True, text=True)
if probe.returncode == 0:
    branch = subprocess.run(['git', '-C', str(root), 'symbolic-ref', '--quiet', '--short', 'HEAD'], capture_output=True, text=True)
    if branch.returncode == 0:
        head = subprocess.run(['git', '-C', str(root), 'rev-parse', '--verify', 'HEAD'], capture_output=True, text=True)
        suffix = '' if head.returncode == 0 else ' (no commit yet)'
        print(f'- Git branch: `{branch.stdout.strip()}`{suffix}')
    else:
        print('- Git branch: detached or unavailable')
else:
    print('- Git branch: not detected')
print(f'- Verified GitHub repository: `{remote}`' if remote else '- Verified GitHub repository: not detected')
for name in ('package.json', 'pyproject.toml', 'go.mod', 'Cargo.toml', 'Makefile', 'README.md', 'skills-lock.json'):
    item(name)
manifest = root / 'manifest.json'
if manifest.is_file() and not manifest.is_symlink():
    try:
        data = json.loads(manifest.read_text())
        version = data.get('manifest_version')
        if isinstance(version, int):
            print(f'- manifest.json: detected (manifest version {version})')
        else:
            print('- manifest.json: detected')
    except (OSError, ValueError):
        print('- manifest.json: detected (metadata unreadable)')
for name in ('src', 'app', 'bg', 'fg', 'lib', 'test', 'tests', 'spec'):
    if (root / name).is_dir() and not (root / name).is_symlink():
        print(f'- Source/test directory: `{name}/`')
workflow_dir = root / '.github/workflows'
if workflow_dir.is_dir() and not workflow_dir.is_symlink():
    workflows = sorted(p.name for p in workflow_dir.glob('*.y*ml') if p.is_file() and not p.is_symlink())
    print('- GitHub workflows: ' + (', '.join(f'`{name}`' for name in workflows) if workflows else 'not detected'))
else:
    print('- GitHub workflows: not detected')
configs = [name for name in ('pytest.ini', 'tox.ini', 'jest.config.js', 'jest.config.cjs', 'vitest.config.js', 'playwright.config.ts')
           if (root / name).is_file() and not (root / name).is_symlink()]
print('- Conventional test config: ' + (', '.join(f'`{name}`' for name in configs) if configs else 'not detected in this bounded scan'))
print(f'- Validation adapter manifest: {"detected" if (root / ".agent/validation/adapter.json").is_file() else "not detected"}')
PY
}

handoff_evidence_command() {
  local command_file='<command.json>' evidence_file="${target_dir}/.agent/runtime/onboarding/local-evidence.json"
  if git -C "${target_dir}" rev-parse --git-dir >/dev/null 2>&1; then
    printf '%q --project %q --kind local --run-local --command-file %s > %q' \
      "${repo_root}/scripts/check-bootstrap-evidence.sh" "${target_dir}" "${command_file}" "${evidence_file}"
  else
    printf '%q --project %q --kind local --run-local --command-file %s --key-dir %q > %q' \
      "${repo_root}/scripts/check-bootstrap-evidence.sh" "${target_dir}" "${command_file}" \
      "${target_dir}/.agent/runtime/onboarding" "${evidence_file}"
  fi
}

handoff_write_validation() {
  local remote_repo="${1:-}" handoff_dir="${target_dir}/.agent/runtime/onboarding"
  local canonical="${handoff_dir}/validation-handoff.md" candidate="${handoff_dir}/validation-handoff.new.md"
  local facts command temporary target
  handoff_require_safe_path "${target_dir}/.agent" || return 1
  handoff_require_safe_path "${target_dir}/.agent/runtime" || return 1
  handoff_require_safe_path "${handoff_dir}" || return 1
  mkdir -p "${handoff_dir}"
  handoff_require_safe_path "${canonical}" || return 1
  facts="$(handoff_facts "${remote_repo}")"
  command="$(handoff_evidence_command)"
  temporary="$(mktemp "${handoff_dir}/.validation-handoff.XXXXXX")"
  python3 - "${repo_root}/templates/onboarding-handoff.md" "${facts}" "${command}" \
    "${repo_root}/scripts/bootstrap.sh --target ${target_dir}" > "${temporary}" <<'PY'
from pathlib import Path
import re
import sys
text = Path(sys.argv[1]).read_text()
values = {
    'TITLE': '准备本地验证',
    'REASON': '尚未发现可验证的本地检查结果。Bootstrap 不猜测项目使用的构建、测试或依赖安装命令。',
    'FACTS': sys.argv[2],
    'EVIDENCE_COMMAND': sys.argv[3],
    'RERUN_COMMAND': sys.argv[4],
}
print(re.sub(r'\{\{(TITLE|REASON|FACTS|EVIDENCE_COMMAND|RERUN_COMMAND)\}\}', lambda m: values[m[1]], text), end='')
PY
  if [[ -e "${canonical}" ]]; then
    if cmp -s "${temporary}" "${canonical}"; then
      rm -f "${temporary}"
      printf '%s\n' "${canonical}"
      return 0
    fi
    handoff_require_safe_path "${candidate}" || { rm -f "${temporary}"; return 1; }
    if [[ -e "${candidate}" ]] && ! cmp -s "${temporary}" "${candidate}"; then
      rm -f "${temporary}"
      echo "Existing handoff files differ; preserving both: ${canonical}, ${candidate}" >&2
      return 1
    fi
    target="${candidate}"
  else
    target="${canonical}"
  fi
  mv "${temporary}" "${target}"
  printf '%s\n' "${target}"
}
