#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 -B - "${repo_root}" <<'PY'
import json
import os
from pathlib import Path
import pty
import re
import select
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

root = Path(sys.argv.pop())
script = root / 'scripts/bootstrap.sh'
MARKERS = ('AI_AGENT', 'CODEX_SANDBOX', 'CODEX_CI', 'CODEX_THREAD_ID', 'CURSOR_TRACE_ID',
           'CURSOR_AGENT', 'CURSOR_EXTENSION_HOST_ROLE', 'GEMINI_CLI', 'ANTIGRAVITY_AGENT',
           'AUGMENT_AGENT', 'OPENCODE_CLIENT', 'CLAUDECODE', 'CLAUDE_CODE', 'REPL_ID',
           'COPILOT_MODEL', 'COPILOT_ALLOW_ALL', 'COPILOT_GITHUB_TOKEN')


class LocalWizardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ['TMPDIR'])
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.target = self.base / 'project with spaces'
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        self.env = {k: v for k, v in os.environ.items() if k not in MARKERS and not k.startswith('GIT_')}
        self.env.update(PATH=f'{self.bin}{os.pathsep}{os.environ["PATH"]}', TMPDIR=str(self.base),
                        HOME=str(self.base), XDG_CONFIG_HOME=str(self.base / 'config'), TERM='dumb',
                        MOCK_CALLS=str(self.base / 'calls.jsonl'), MOCK_TARGET=str(self.target))
        self.mock('gh', 'printf "unexpected remote call\\n" >> "$MOCK_TARGET/remote-calls"; exit 92\n')
        (self.bin / 'npx').write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
assert all(os.isatty(fd) for fd in (0,1,2))
args = sys.argv[1:]
with open(os.environ['MOCK_CALLS'], 'a') as out:
    out.write(json.dumps({'argv': args, 'cwd': os.getcwd(), 'tty': True}) + '\\n')
if os.environ.get('MOCK_CANCEL'): raise SystemExit(0)
if os.environ.get('MOCK_FAIL'): raise SystemExit(7)
clients = args[args.index('--agent') + 1:] if '--agent' in args else []
skill = args[args.index('--skill') + 1] if '--skill' in args else 'example'
for client in clients:
    directory = Path('.claude/skills' if client == 'claude-code' else '.agents/skills') / skill
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'SKILL.md').write_text(chr(10).join(('---', 'name: ' + skill, '---', 'Fixture instructions', '')))
''')
        (self.bin / 'npx').chmod(0o755)

    def mock(self, name, body):
        path = self.bin / name
        path.write_text('#!/usr/bin/env bash\nset -eu\n' + body)
        path.chmod(0o755)

    def tty(self, answers, expected=0, extra=(), cwd=None, argv=None):
        master, slave = pty.openpty()
        invocation = ['bash', str(script), '--target', str(self.target), *extra] if argv is None else argv
        process = subprocess.Popen(invocation, cwd=cwd,
                                   stdin=slave, stdout=slave, stderr=slave, env=self.env,
                                   start_new_session=True)
        os.close(slave)
        transcript, cursor = b'', 0
        deadline = time.monotonic() + 45
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

    def answers(self, clients='claude-code', workflow='none', skills='n', policy='y', git='y', ignore='y', collaboration='n', known=False):
        result = [('开始接入', 'y'), ('选择项目 Agent 客户端', clients)]
        if known:
            result.append(('已有工作流：', 'keep'))
        else:
            result.append(('选择工作方式', workflow))
        if workflow != 'none': result.append(('进入所选工作流安装器', 'y'))
        result += [('进入技能选择', skills), ('安装或补齐 Understand Anything', 'n'),
                   ('建立或更新上述项目基础配置', policy)]
        if policy == 'y':
            if ignore is not None: result.append(('应用以上忽略规则与政策引用差异', ignore))
            if not (self.target / '.git').exists(): result.append(('初始化本地 Git', git))
        result.append(('继续可选 GitHub', collaboration))
        return result

    def calls(self):
        path = self.base / 'calls.jsonl'
        return [json.loads(x) for x in path.read_text().splitlines()] if path.exists() else []

    def readme_toolkit_fixture(self, readme_name='README.md'):
        # Simulate a downloaded candidate distribution, not a published release.
        # This offline regression never fetches packages or runs native installers.
        source = Path(os.environ.get('BOOTSTRAP_JOURNEY_SOURCE', str(root))).resolve()
        translations = {
            'README.md': ('## Quick start: initialize a project', '## Only want to install Skills?',
                          ('target defaults to the current working directory',
                           'toolkit directory and your project directory are different', 'already exists')),
            'README.zh-CN.md': ('## 快速开始：初始化项目', '## 只想安装 Skills？',
                                ('默认目标就是当前工作目录', '工具目录和项目目录不是一回事', '已经存在')),
        }
        start_heading, skills_heading, explanations = translations[readme_name]
        readme = (source / readme_name).read_text()
        english = (source / 'README.md').read_text()
        chinese = (source / 'README.zh-CN.md').read_text()
        self.assertIn('[简体中文](README.zh-CN.md)', english)
        self.assertIn('[English](README.md)', chinese)
        self.assertEqual(re.findall(r'```bash\n(.*?)\n```', english, re.S),
                         re.findall(r'```bash\n(.*?)\n```', chinese, re.S))
        self.assertLess(readme.index(start_heading), readme.index(skills_heading))
        quickstart = readme.split(start_heading + '\n', 1)[1].split('\n## ', 1)[0]
        commands = re.findall(r'```bash\n(.*?)\n```', quickstart, re.S)
        self.assertEqual(commands, [
            'git clone https://github.com/blue126/agent-project-bootstrap.git "$HOME/agent-project-bootstrap"',
            'mkdir "$HOME/my-agent-project"', 'cd "$HOME/my-agent-project"',
            'cd "/path/to/your/project"', '"$HOME/agent-project-bootstrap/scripts/bootstrap.sh"'])
        for explanation in explanations:
            self.assertIn(explanation, quickstart)
        self.toolkit = self.base / 'agent-project-bootstrap'
        self.toolkit.mkdir()
        # Keep a separate toolkit Git repository, as a clone would have. No
        # commits or remote operations are needed for this acquisition fixture.
        subprocess.run(['git', 'init', '-q', str(self.toolkit)], env=self.env, check=True)
        subprocess.run(['git', '-C', str(self.toolkit), 'remote', 'add', 'origin',
                        'https://github.com/blue126/agent-project-bootstrap.git'], env=self.env, check=True)
        for directory in ('scripts', 'templates', 'policies', 'skills', 'integrations'):
            shutil.copytree(source / directory, self.toolkit / directory,
                            ignore=shutil.ignore_patterns('__pycache__', '.venv', 'node_modules'))
        for name in ('README.md', 'README.zh-CN.md', 'bootstrap-manifest.yml'):
            shutil.copy2(source / name, self.toolkit / name)
        launch = [arg.replace('$HOME', self.env['HOME']) for arg in shlex.split(commands[-1])]
        self.assertEqual(launch, [str(self.toolkit / 'scripts/bootstrap.sh')])
        self.assertNotIn('--target', launch)
        return commands, launch

    def readme_newcomer_journey(self, readme_name):
        commands, launch = self.readme_toolkit_fixture(readme_name)
        # Run the README's actual mkdir/cd/start semantics against an isolated HOME.
        mkdir_argv = [arg.replace('$HOME', self.env['HOME']) for arg in shlex.split(commands[1])]
        subprocess.run(mkdir_argv, env=self.env, check=True)
        self.target = Path(shlex.split(commands[2])[1].replace('$HOME', self.env['HOME']))
        self.env['MOCK_TARGET'] = str(self.target)
        toolkit_before = {str(p.relative_to(self.toolkit)): p.read_bytes()
                          for p in self.toolkit.rglob('*') if p.is_file()}
        text = self.tty(self.answers(workflow='github-workflow', skills='y'), cwd=self.target, argv=launch)
        self.assertIn(str(self.target), text)
        self.assertLess(text.index(str(self.target)), text.index('开始接入'))
        self.assertIn('本地配置就绪，待客户端加载确认', text)
        self.assertIn('本次在本地完成', text)
        self.assertEqual([c['cwd'] for c in self.calls()], [str(self.target), str(self.target)])
        self.assertTrue((self.target / '.claude/skills/github-workflow/SKILL.md').is_file())
        self.assertTrue((self.target / '.claude/skills/example/SKILL.md').is_file())
        self.assertTrue((self.target / '.git').is_dir())
        self.assertFalse((self.target / 'remote-calls').exists())
        self.assertEqual(subprocess.check_output(['git', '-C', str(self.target), 'remote']), b'')
        self.assertEqual(subprocess.check_output(['git', '-C', str(self.target), 'ls-files']), b'')
        self.assertFalse((self.toolkit / '.agent').exists())
        self.assertTrue((self.toolkit / '.git').is_dir())
        self.assertEqual(subprocess.check_output(['git', '-C', str(self.toolkit), 'remote', 'get-url', 'origin']).strip(),
                         b'https://github.com/blue126/agent-project-bootstrap.git')
        self.assertEqual(toolkit_before, {str(p.relative_to(self.toolkit)): p.read_bytes()
                                         for p in self.toolkit.rglob('*') if p.is_file()})

    def readme_existing_project_journey(self, readme_name):
        _, launch = self.readme_toolkit_fixture(readme_name)
        self.target.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.target)], check=True)
        subprocess.run(['git', '-C', str(self.target), 'remote', 'add', 'origin',
                        'https://github.com/acme/existing.git'], check=True)
        original = self.target / 'user-work.txt'
        original.write_text('Keep my staged work.\n')
        subprocess.run(['git', '-C', str(self.target), 'add', '--', 'user-work.txt'], check=True)
        index_before = (self.target / '.git/index').read_bytes()
        self.tty(self.answers(), cwd=self.target, argv=launch)
        self.assertEqual(original.read_text(), 'Keep my staged work.\n')
        self.assertEqual((self.target / '.git/index').read_bytes(), index_before)
        self.assertEqual(subprocess.check_output(['git', '-C', str(self.target), 'remote', 'get-url', 'origin']).strip(),
                         b'https://github.com/acme/existing.git')
        self.assertFalse((self.target / 'remote-calls').exists())
        self.assertFalse((self.toolkit / '.agent').exists())

    def test_readme_newcomer_download_to_current_directory_journey(self):
        self.readme_newcomer_journey('README.md')

    def test_chinese_readme_newcomer_journey(self):
        self.readme_newcomer_journey('README.zh-CN.md')

    def test_readme_existing_project_uses_cwd_and_preserves_index(self):
        self.readme_existing_project_journey('README.md')

    def test_chinese_readme_existing_project_journey(self):
        self.readme_existing_project_journey('README.zh-CN.md')

    def test_explicit_target_override_still_works_from_another_directory(self):
        text = self.tty(self.answers(), cwd=self.base,
                        argv=[str(script), '--target', str(self.target)])
        self.assertIn(str(self.target), text)
        self.assertTrue((self.target / '.agent/bootstrap.yml').is_file())
        self.assertFalse((self.base / '.agent').exists())

    def test_local_completion_has_git_no_remote_no_commit_or_handoff(self):
        text = self.tty(self.answers())
        self.assertIn('本地配置就绪，待客户端加载确认', text)
        self.assertIn('版本状态：尚未提交', text)
        self.assertIn('首次提交检查：未执行', text)
        self.assertTrue((self.target / '.git').is_dir())
        self.assertFalse((self.target / 'remote-calls').exists())
        self.assertFalse((self.target / '.agent/runtime/onboarding/validation-handoff.md').exists())
        self.assertNotEqual(subprocess.run(['git', '-C', str(self.target), 'rev-parse', '--verify', 'HEAD'], capture_output=True).returncode, 0)
        self.assertEqual(subprocess.check_output(['git', '-C', str(self.target), 'ls-files']), b'')
        self.assertIn('project_agents: ["claude-code"]', (self.target / '.agent/bootstrap.yml').read_text())

    def test_intro_cancel_does_not_create_target(self):
        self.tty([('开始接入', 'n')])
        self.assertFalse(self.target.exists())
        self.tty([('开始接入', 'i'), ('Enter 返回开始菜单', ''), ('开始接入', 'q')], expected=3)
        self.assertFalse(self.target.exists())

    def test_client_cancel_does_not_create_target(self):
        self.tty([('开始接入', 'y'), ('选择项目 Agent 客户端', 'q')], expected=3)
        self.assertFalse(self.target.exists())

    def test_all_upstream_agent_markers_rejected(self):
        for key in MARKERS:
            value = 'agent-exec' if key == 'CURSOR_EXTENSION_HOST_ROLE' else 'test'
            result = subprocess.run(['bash', str(script), '--target', str(self.target)],
                                    env=dict(self.env, **{key: value}), text=True, capture_output=True)
            self.assertEqual(result.returncode, 2, (key, result.stderr))
            self.assertIn('Agent process', result.stderr)
        self.assertFalse(self.target.exists())

    def test_no_resume_interface(self):
        for flag in ('--resume', '--status', '--revisit'):
            result = subprocess.run(['bash', str(script), '--target', str(self.target), flag],
                                    env=self.env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn('no longer stores progress', result.stderr)

    def test_multi_client_native_targets_and_tty(self):
        text = self.tty(self.answers(clients='claude-code codex universal', skills='y'))
        call = self.calls()[0]
        self.assertEqual(call['cwd'], str(self.target))
        self.assertEqual(call['argv'], ['skills@1.5.23', 'add', str(root), '--agent', 'claude-code', 'codex', 'universal'])
        self.assertTrue(call['tty'])
        self.assertIn('本地配置就绪', text)
        self.assertTrue((self.target / '.claude/skills/example/SKILL.md').is_file())
        self.assertTrue((self.target / '.agents/skills/example/SKILL.md').is_file())

    def test_explicit_bootstrap_forwards_confirmed_clients_to_native_skills(self):
        self.tty([], extra=('--workflow', 'none', '--agent', 'claude-code',
                            '--install-skills', '--skip-understand-anything', '--skip-superpowers'))
        self.assertEqual(self.calls()[0]['argv'][-2:], ['--agent', 'claude-code'])
        self.assertTrue((self.target / '.claude/skills/example/SKILL.md').is_file())

    def test_workflow_install_does_not_suppress_ordinary_choice(self):
        text = self.tty(self.answers(workflow='github-workflow', skills='y'))
        self.assertEqual(len(self.calls()), 2)
        self.assertIn('--skill', self.calls()[0]['argv'])
        self.assertNotIn('--skill', self.calls()[1]['argv'])
        self.assertIn('采用的工作方式：github-workflow', text)
        self.assertFalse((self.target / 'remote-calls').exists())

    def test_existing_skills_still_offer_and_saved_client_still_confirms(self):
        self.tty(self.answers(skills='y'))
        self.tty(self.answers(skills='y', policy='n'))
        self.assertEqual(len(self.calls()), 2)

    def test_universal_does_not_create_claude_entry(self):
        self.tty(self.answers(clients='universal', skills='y'))
        self.assertFalse((self.target / 'CLAUDE.md').exists())
        self.assertFalse((self.target / '.claude').exists())
        self.assertEqual(self.calls()[0]['argv'][-1], 'universal')

    def test_existing_github_origin_not_contacted_without_opt_in(self):
        self.target.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.target)], check=True)
        subprocess.run(['git', '-C', str(self.target), 'remote', 'add', 'origin', 'https://github.com/acme/project.git'], check=True)
        self.tty(self.answers())
        self.assertFalse((self.target / 'remote-calls').exists())

    def test_declining_policy_keeps_clients_session_only_and_reports_pending(self):
        text = self.tty(self.answers(policy='n'))
        self.assertIn('基础配置仍有待处理项', text)
        self.assertFalse(self.target.exists())

    def test_existing_instructions_and_ignore_declined_are_preserved(self):
        self.target.mkdir()
        (self.target / 'AGENTS.md').write_text('My rules\n')
        (self.target / '.gitignore').write_text('# User rules\n/.*\n')
        text = self.tty(self.answers(ignore='n'))
        self.assertEqual((self.target / 'AGENTS.md').read_text(), 'My rules\n')
        self.assertEqual((self.target / '.gitignore').read_text(), '# User rules\n/.*\n')
        self.assertIn('基础配置仍有待处理项', text)

    def test_cancelled_native_workflow_is_not_installed_success(self):
        self.env['MOCK_CANCEL'] = '1'
        text = self.tty(self.answers(workflow='github-workflow'))
        self.assertIn('基础配置仍有待处理项', text)
        self.assertFalse((self.target / '.claude/skills/github-workflow').exists())

    def test_new_client_can_reuse_existing_skill_without_source_overwrite(self):
        self.tty(self.answers(clients='codex', skills='y'))
        original = (self.target / '.agents/skills/example/SKILL.md').read_bytes()
        answers = self.answers(clients='claude-code', policy='y')
        position = next(i for i, (prompt, _) in enumerate(answers) if prompt == '进入技能选择')
        answers.insert(position, ('补齐以上已有项目 Skill 的客户端入口', 'y'))
        text = self.tty(answers)
        self.assertTrue((self.target / '.claude/skills/example').is_symlink())
        self.assertEqual((self.target / '.agents/skills/example/SKILL.md').read_bytes(), original)
        self.assertEqual(len(self.calls()), 1)
        self.assertIn('本地配置就绪', text)

    def test_unsupported_bmad_universal_returns_to_workflow_choice(self):
        answers = self.answers(clients='universal')
        position = next(i for i, (prompt, _) in enumerate(answers) if prompt == '选择工作方式')
        answers.insert(position, ('选择工作方式', 'bmad'))
        text = self.tty(answers)
        self.assertIn('BMAD 不支持 Universal', text)
        self.assertEqual(self.calls(), [])
        self.assertFalse((self.target / '_bmad').exists())

    def test_multiple_detected_workflows_do_not_activate_from_order(self):
        for name in ('github-workflow', 'using-superpowers'):
            entry = self.target / '.claude/skills' / name
            entry.mkdir(parents=True)
            (entry / 'SKILL.md').write_text('Existing framework\n')
        self.tty(self.answers(known=True))
        self.assertIn('workflow_id: none', (self.target / '.agent/bootstrap.yml').read_text())
        self.assertEqual(self.calls(), [])

    def test_fresh_bmad_blocks_legacy_entries_and_external_command_root(self):
        for case in ('legacy', 'claude-entry', 'opencode-entry', 'external-commands'):
            self.target = self.base / case
            self.target.mkdir()
            self.env['MOCK_TARGET'] = str(self.target)
            outside = self.base / ('outside-' + case)
            outside.mkdir()
            if case == 'legacy':
                entry = self.target / 'bmad/keep.md'
            elif case == 'claude-entry':
                entry = self.target / '.claude/skills/bmad-help/SKILL.md'
            elif case == 'opencode-entry':
                entry = self.target / '.opencode/commands/bmad-help.md'
            else:
                (self.target / '.opencode').symlink_to(outside)
                entry = outside / 'keep.md'
            entry.parent.mkdir(parents=True, exist_ok=True)
            entry.write_text('User BMAD content\n')
            client = 'claude-code' if case == 'claude-entry' else 'opencode'
            text = self.tty(self.answers(clients=client, workflow='bmad', policy='n'))
            self.assertIn('未启动安装器', text)
            self.assertEqual(entry.read_text(), 'User BMAD content\n')
            self.assertFalse((self.target / '_bmad').exists())
        self.assertEqual(self.calls(), [])

    def test_complete_bmad_with_legacy_ignore_does_not_offer_adapter_update(self):
        self.target.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.target)], check=True)
        config = self.target / '_bmad/_config'
        config.mkdir(parents=True)
        (self.target / '_bmad/core').mkdir()
        (config / 'manifest.yaml').write_text('installation:\n  version: 6.12.0\nmodules:\n  - core\nides:\n  - codex\n')
        (config / 'bmad-help.csv').write_text('module,skill\ncore,bmad-help\n')
        entry = self.target / '.agents/skills/bmad-help'
        entry.mkdir(parents=True)
        (entry / 'SKILL.md').write_text('Existing BMAD\n')
        (entry.parent / '.gitignore').write_text('*\n!.gitignore\n')
        answers = self.answers(clients='codex', policy='n', known=True)
        answers = [(p, 'bmad' if p == '已有工作流：' else a) for p, a in answers]
        text = self.tty(answers)
        self.assertNotIn('查看 BMAD 客户端补齐计划', text)
        self.assertEqual(self.calls(), [])

    def test_inactive_pack_inventory_survives_update_and_rerun(self):
        entry = self.target / '.claude/skills/using-superpowers'
        entry.mkdir(parents=True)
        (entry / 'SKILL.md').write_text('Existing inactive framework\n')
        self.tty(self.answers(known=True))
        config = self.target / '.agent/bootstrap.yml'
        for _ in range(2):
            result = subprocess.run(['bash', str(script), '--target', str(self.target), '--update'],
                                    env=self.env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('workflow_id: none', config.read_text())
            self.assertIn('  workflow_pack: superpowers', config.read_text())
        self.tty(self.answers(known=True, ignore=None))
        self.assertIn('  workflow_pack: superpowers', config.read_text())

    def test_optional_remote_menu_retains_retry_and_local_summary_precedes_it(self):
        answers = self.answers(collaboration='y') + [('GitHub 操作', ''), ('GitHub 操作', 'q')]
        text = self.tty(answers, expected=3)
        self.assertIn('空输入不会跳过 GitHub', text)
        self.assertLess(text.index('本地结果与开始工作'), text.index('可选协作 · Git/GitHub'))
        self.assertFalse((self.target / 'remote-calls').exists())

    def test_existing_review_feedback_is_verified_and_continues_to_protection(self):
        self.target.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.target)], check=True)
        subprocess.run(['git', '-C', str(self.target), 'remote', 'add', 'origin', 'https://github.com/acme/project.git'], check=True)
        self.mock('gh', 'printf "acme/project\\n"\n')
        fixture_repo = self.base / 'fixture-toolkit'
        (fixture_repo / 'scripts').mkdir(parents=True)
        checker = fixture_repo / 'scripts/check-bootstrap-evidence.sh'
        checker.write_text('''#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$EVIDENCE_CALLS"
kind=''
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --kind ]]; then kind="$2"; shift 2; else shift; fi
done
if [[ "$kind" == review ]]; then exit "${REVIEW_FAILURE:-0}"; fi
printf '{}\\n'
''')
        checker.chmod(0o755)
        harness = r'''
set -eu
repo_root="$FIXTURE_REPO"
target_dir="$MOCK_TARGET"
source "$REAL_REPO/scripts/lib/onboarding-collaboration.sh"
ui_heading() { printf '%s\n' "$*"; }
ui_section() { printf '%s\n' "$*"; }
ui_text() { printf '%s\n' "$*"; }
ui_note() { printf '%s\n' "$*"; }
ui_warning() { printf '%s\n' "$*"; }
confirm() { [[ "$1" == 验证\ PR* ]]; }
ask() { reply=12; }
pause_for_agent() { exit 93; }
handoff_require_safe_path() { return 0; }
run_collaboration
'''
        calls = self.base / 'evidence-calls'
        for failure in ('0', '1'):
            result = subprocess.run(['bash', '-c', harness], text=True, capture_output=True,
                                    env=dict(self.env, FIXTURE_REPO=str(fixture_repo), REAL_REPO=str(root),
                                             EVIDENCE_CALLS=str(calls), REVIEW_FAILURE=failure))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('合并保护', result.stdout)
            if failure == '0':
                self.assertIn('仅验证集成，不是合并批准', result.stdout)
            else:
                self.assertIn('审查反馈尚未验证', result.stdout)
        self.assertIn('--kind review --repo acme/project --pr 12 --discover', calls.read_text())

    def test_validation_handoff_only_after_collaboration_opt_in(self):
        text = self.tty(self.answers(collaboration='y') + [('GitHub 操作', '3'), ('让目标项目 Agent 协助准备', 'y')], expected=3)
        self.assertIn('需要项目 Agent 协助', text)
        handoff = self.target / '.agent/runtime/onboarding/validation-handoff.md'
        self.assertTrue(handoff.is_file())
        self.assertNotIn('--key-dir', handoff.read_text())


unittest.main(defaultTest=os.environ.get('BOOTSTRAP_JOURNEY_TEST') or None, verbosity=2, failfast=True)
PY
