#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 -B - "${repo_root}" <<'PY'
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import tempfile
import time
import unittest

root = Path(sys.argv.pop())
script = root / 'scripts/bootstrap.sh'


class StatelessWizardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ['TMPDIR'])
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.target = self.base / 'project with spaces'
        self.target.mkdir()
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.env = {key: value for key, value in os.environ.items() if key not in
                    ('AI_AGENT', 'CODEX_SANDBOX', 'CODEX_CI', 'CODEX_THREAD_ID', 'BOOTSTRAP_STATE_HOME')}
        self.env.update(PATH=f'{self.bin}{os.pathsep}{os.environ["PATH"]}', TMPDIR=str(self.base),
                        MOCK_TARGET=str(self.target), MOCK_CALLS=str(self.base / 'calls'))
        self.mock('gh', 'printf "Unexpected GitHub request\\n" >&2; exit 92\n')
        self.mock('npx', r'''
[ -t 0 ] && [ -t 1 ] || exit 94
printf '%s\n' "$*" >> "$MOCK_CALLS"
mkdir -p "$MOCK_TARGET/.agents/skills/example"
printf '%s\n' '---' 'name: example' '---' > "$MOCK_TARGET/.agents/skills/example/SKILL.md"
''')

    def mock(self, name, body):
        path = self.bin / name
        path.write_text('#!/usr/bin/env bash\nset -eu\n' + body)
        path.chmod(0o755)

    def tty(self, answers, expected=0, extra=()):
        master, slave = pty.openpty()
        process = subprocess.Popen(['bash', str(script), '--target', str(self.target), *extra],
                                   stdin=slave, stdout=slave, stderr=slave, env=self.env,
                                   start_new_session=True)
        os.close(slave)
        transcript, cursor = b'', 0
        deadline = time.monotonic() + 35
        try:
            for prompt, answer in answers:
                wanted = prompt.encode()
                while wanted not in transcript[cursor:]:
                    if time.monotonic() > deadline or process.poll() is not None:
                        self.fail(f'Missing prompt: {prompt}\n{transcript.decode(errors="replace")}')
                    if select.select([master], [], [], .1)[0]:
                        try: transcript += os.read(master, 65536)
                        except OSError: self.fail(transcript.decode(errors='replace'))
                cursor = transcript.index(wanted, cursor) + len(wanted)
                os.write(master, (answer + '\n').encode())
            while process.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try: transcript += os.read(master, 65536)
                    except OSError: break
            process.wait(timeout=5)
            while select.select([master], [], [], 0)[0]:
                try:
                    data = os.read(master, 65536)
                    if not data: break
                    transcript += data
                except OSError: break
        finally:
            if process.poll() is None:
                process.kill(); process.wait()
            os.close(master)
        text = transcript.decode(errors='replace')
        self.assertEqual(process.returncode, expected, text)
        return text

    def base_answers(self, workflow='4', skills='n', ua='n', policy='y', github='3', validation='n', existing=False):
        answers = [('开始接入', 'y')]
        known_bmad = (self.target / '_bmad/_config/manifest.yaml').is_file() and (self.target / '_bmad/_config/bmad-help.csv').is_file()
        if not known_bmad:
            answers.append(('安装选择', workflow))
        has_skills = any(path.is_file() for root_dir in (self.target / '.agents/skills', self.target / '.claude/skills')
                         for path in root_dir.glob('*/SKILL.md'))
        if not has_skills:
            answers.append(('进入技能选择', skills))
        if not (self.target / '.agent/runtime/understand-anything/repo/.git').is_dir():
            answers.append(('安装到当前项目', ua))
        policy_prompt = '检查并更新项目规范' if existing or (self.target / '.agent/bootstrap.yml').is_file() else '检查并建立项目规范'
        answers.append((policy_prompt, policy))
        has_origin = subprocess.run(['git', '-C', str(self.target), 'remote', 'get-url', 'origin'], capture_output=True).returncode == 0
        if not has_origin:
            answers.append(('GitHub 操作', github))
        answers.append(('让目标项目 Agent 协助准备', validation))
        return answers

    def test_no_resume_status_or_revisit_state_interface(self):
        for flag in ('--resume', '--status', '--revisit'):
            args = [flag] if flag != '--revisit' else ['--revisit', 'remote']
            result = subprocess.run(['bash', str(script), '--target', str(self.target), *args],
                                    env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertIn('no longer stores progress', result.stderr)
        self.assertFalse((self.target / '.agent').exists())
        self.assertFalse((self.base / 'state').exists())

    def test_agent_guard_and_status_directory_are_not_used(self):
        result = subprocess.run(['bash', str(script), '--target', str(self.target)],
                                env=dict(self.env, AI_AGENT='test'), capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('cannot host', result.stderr)
        self.assertFalse((self.target / '.agent').exists())
        self.assertFalse(any('agent-project-bootstrap' in str(path) for path in self.base.rglob('*')))

    def test_intro_detail_view_returns_to_menu_and_blank_does_not_exit(self):
        transcript = self.tty([('开始接入', 'i'), ('Enter 返回开始菜单', ''),
                               ('开始接入', ''), ('开始接入', 'y'),
                               ('安装选择', '4'), ('进入技能选择', 'q')], expected=3)
        self.assertIn('项目接入 · 完整说明', transcript)
        for stage in range(1, 7):
            self.assertIn(f'[{stage}/6]', transcript)
        self.assertGreaterEqual(transcript.count('检查：'), 6)
        self.assertGreaterEqual(transcript.count('可能改变：'), 6)
        self.assertGreaterEqual(transcript.count('不会：'), 6)
        self.assertIn('请选择 y 开始、i 查看完整说明、n 退出', transcript)
        self.assertIn('阶段 1/6', transcript)
        self.assertFalse((self.target / '.agent').exists())
        self.assertFalse((self.base / 'calls').exists())
        self.assertNotIn('templates/AGENTS.md（已有不同内容', transcript)

    def test_empty_github_menu_retries_and_does_not_skip(self):
        transcript = self.tty(self.base_answers()[:-2] + [
            ('GitHub 操作', ''), ('GitHub 操作', 'q')], expected=3)
        self.assertIn('空输入不会跳过 GitHub', transcript)
        self.assertNotIn('阶段 5/6', transcript)
        self.assertFalse((self.target / '.git').exists())
        self.assertFalse((self.base / 'calls').exists())

    def test_blank_repository_name_retries_then_back_creates_no_side_effect(self):
        self.env.update(MOCK_LOG=str(self.base / 'gh-calls'))
        self.mock('gh', r'''
printf '%s\n' "$*" >> "$MOCK_LOG"
if [[ "$1" == auth && "$2" == status ]]; then exit 0; fi
exit 92
''')
        transcript = self.tty(self.base_answers()[:-2] + [
            ('GitHub 操作', '2'), ('仓库 OWNER/REPOSITORY', ''),
            ('仓库 OWNER/REPOSITORY', 'b'), ('GitHub 操作', '3'),
            ('让目标项目 Agent 协助准备', 'n')])
        self.assertIn('仓库名称不能为空', transcript)
        self.assertNotIn('接入已暂停', transcript)
        self.assertFalse((self.target / '.git').exists())
        self.assertFalse((self.base / 'gh-calls').exists())

    def test_rerun_reoffers_unconfigured_github_without_journal(self):
        first = self.tty(self.base_answers())
        self.assertIn('本次不接入 GitHub', first)
        self.assertFalse((self.target / '.git').exists())
        second = self.tty(self.base_answers(policy='n', existing=True))
        self.assertIn('尚无 origin · 请选择接入方式', second)
        self.assertNotIn('发现上次进度', second)
        self.assertFalse((self.target / '.git').exists())

    def test_existing_project_config_and_known_bmad_are_preserved(self):
        config = self.target / '_bmad/_config'
        config.mkdir(parents=True)
        (config / 'manifest.yaml').write_text('installation:\n  version: 6.12.0\nmodules: [core,bmm]\n')
        (config / 'bmad-help.csv').write_text('module,skill\nbmm,bmad-build\n')
        original = (config / 'manifest.yaml').read_bytes()
        transcript = self.tty(self.base_answers())
        self.assertIn('已有工作流', transcript)
        self.assertNotIn('安装选择 [', transcript)
        self.assertEqual((config / 'manifest.yaml').read_bytes(), original)
        self.assertFalse((self.base / 'calls').exists())

    def test_installbmad_skill_does_not_count_as_bmad(self):
        entry = self.target / '.agents/skills/installbmad'
        entry.mkdir(parents=True)
        (entry / 'SKILL.md').write_text('Installer only')
        transcript = self.tty(self.base_answers())
        self.assertIn('未检测到内置工作流', transcript)

    def test_existing_user_instructions_are_not_overwritten(self):
        original = 'Use our own private development process.\n'
        (self.target / 'AGENTS.md').write_text(original)
        transcript = self.tty(self.base_answers(policy='y'))
        self.assertEqual((self.target / 'AGENTS.md').read_text(), original)
        self.assertIn('Preserved existing file without taking ownership: AGENTS.md', transcript)
        self.assertNotIn('未确认的操作没有执行', transcript)

    def test_validation_handoff_has_facts_task_file_and_non_git_command_contract(self):
        (self.target / 'manifest.json').write_text(json.dumps({'manifest_version': 3, 'version': '9.9.9', 'secret': 'do-not-copy'}))
        (self.target / 'bg').mkdir()
        transcript = self.tty(self.base_answers(validation='y'), expected=3)
        handoff = self.target / '.agent/runtime/onboarding/validation-handoff.md'
        self.assertTrue(handoff.is_file())
        content = handoff.read_text()
        self.assertIn('# 项目 Agent 任务：准备本地验证', content)
        self.assertIn('manifest.json: detected (manifest version 3)', content)
        self.assertIn('Source/test directory: `bg/`', content)
        self.assertIn('Conventional test config: not detected in this bounded scan', content)
        self.assertIn('--key-dir', content)
        self.assertNotIn('do-not-copy', content)
        self.assertNotIn('README.md\n', content)
        self.assertIn('为什么在这里停止', transcript)
        self.assertIn('已知项目事实', transcript)
        self.assertIn(str(handoff), transcript)
        self.assertNotIn('scripts/check-bootstrap-evidence.sh --project', transcript)
        self.assertFalse((self.base / 'calls').exists())

    def test_git_validation_handoff_uses_git_receipt_contract(self):
        subprocess.run(['git', 'init', '-q', '--initial-branch=main', str(self.target)], check=True)
        transcript = self.tty(self.base_answers(validation='y'), expected=3)
        handoff = self.target / '.agent/runtime/onboarding/validation-handoff.md'
        self.assertTrue(handoff.is_file())
        content = handoff.read_text()
        self.assertIn('Git branch: `main` (no commit yet)', content)
        self.assertNotIn('--key-dir', content)
        self.assertIn('需要项目 Agent 协助：准备本地验证', transcript)

    def test_declining_agent_assistance_does_not_write_handoff(self):
        transcript = self.tty(self.base_answers(validation='n'))
        self.assertIn('本次不配置本地验证', transcript)
        self.assertFalse((self.target / '.agent/runtime/onboarding/validation-handoff.md').exists())

    def test_interrupted_external_work_restarts_from_actual_project_state(self):
        transcript = self.tty(self.base_answers(validation='y'), expected=3)
        self.assertIn('需要项目 Agent 协助', transcript)
        command = self.base / 'command.json'
        command.write_text(json.dumps({'schema_version': 1, 'argv': [sys.executable, '-c', 'pass']}))
        receipt = self.target / '.agent/runtime/onboarding/local-evidence.json'
        receipt.parent.mkdir(parents=True, exist_ok=True)
        key_dir = self.target / '.agent/runtime/onboarding'
        result = subprocess.run(['bash', str(root / 'scripts/check-bootstrap-evidence.sh'),
                                 '--project', str(self.target), '--kind', 'local', '--run-local',
                                 '--command-file', str(command), '--key-dir', str(key_dir)], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt.write_text(result.stdout)
        answers = self.base_answers(policy='n', existing=True)
        answers.pop()  # The actual local receipt removes the validation prompt.
        transcript = self.tty(answers)
        self.assertIn('已核实本地验证执行证据', transcript)
        self.assertNotIn('需要项目 Agent 协助', transcript)

    def test_native_selector_is_immediate_and_skip_does_not_persist(self):
        transcript = self.tty(self.base_answers(skills='y'))
        self.assertIn('skills@1.5.23 add', (self.base / 'calls').read_text())
        self.assertLess(transcript.index('阶段 2/6 · 普通技能'), transcript.index('Understand Anything · 可选项目集成'))
        command = (self.base / 'calls').read_text()
        for forbidden in ('--all', ' -y', ' -g'):
            self.assertNotIn(forbidden, command)
        # A later run sees actual installed entries and does not rerun the native selector.
        self.tty(self.base_answers(policy='n', existing=True))
        self.assertEqual((self.base / 'calls').read_text().count('skills@1.5.23 add'), 1)

    def test_update_remains_side_effect_free_and_preserves_metadata(self):
        self.tty(self.base_answers())
        manifest = self.target / '.agent/bootstrap.yml'
        text = manifest.read_text().replace('  runtime_sha: none', '  runtime_sha: none\n  repo_validation_runtime_sha: keep-me')
        text += 'custom_extension:\n  value: keep-me\n'
        manifest.write_text(text)
        result = subprocess.run(['bash', str(script), '--target', str(self.target), '--update'],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('repo_validation_runtime_sha: keep-me', manifest.read_text())
        self.assertIn('custom_extension:\n  value: keep-me', manifest.read_text())
        for flag in ('--init-git', '--install-skills', '--install-understand-anything', '--create-github'):
            result = subprocess.run(['bash', str(script), '--target', str(self.target), '--update', flag],
                                    env=self.env, capture_output=True)
            self.assertEqual(result.returncode, 2, flag)
        self.assertFalse((self.target / '.git').exists())

    def test_terminal_formatting_and_plain_text_fallback(self):
        for term, no_color, expected_color in (('xterm-256color', '', True), ('xterm-256color', '1', False), ('dumb', '', False)):
            with self.subTest(term=term, no_color=no_color):
                self.env.update(TERM=term, NO_COLOR=no_color)
                transcript = self.tty(self.base_answers())
                self.assertEqual('\x1b[' in transcript, expected_color)
                self.assertIn('────────────────', transcript)
                self.assertIn('> ', transcript)
                for stage in range(1, 7):
                    self.assertIn(f'[{stage}/6]', transcript)
                self.assertIn('重要边界', transcript)
                self.assertIn('外部写入、发布、权限与覆盖操作都会在执行前单独确认', transcript)
                self.target = self.base / f'plain-{term}-{no_color or "color"}'
                self.target.mkdir()
                self.env['MOCK_TARGET'] = str(self.target)


unittest.main(verbosity=2)
PY
