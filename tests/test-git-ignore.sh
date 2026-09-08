#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 -B - "${repo_root}" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

root = Path(sys.argv.pop())
helper = root / 'scripts/configure-git-ignore.py'


class IgnoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ['TMPDIR'])
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.project = self.base / 'project with spaces'
        self.project.mkdir()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        self.env.update(HOME=str(self.base), XDG_CONFIG_HOME=str(self.base / 'config'),
                        GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull, TMPDIR=str(self.base))

    def write(self, path, text='fixture\n'):
        target = self.project / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return target

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.project), *args], env=self.env,
                              text=True, capture_output=True)

    def invoke(self, *args, expected=0):
        result = subprocess.run([sys.executable, str(helper), '--project', str(self.project), '--json', *args],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return json.loads(result.stdout) if expected == 0 else result

    def apply(self, *args):
        preview = self.invoke(*args)
        return self.invoke(*args, '--apply', '--expect', preview['token'])

    def bootstrap(self, *args):
        result = subprocess.run(['bash', str(root / 'scripts/bootstrap.sh'), '--target', str(self.project),
                                 *args], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_new_checkout_shared_assets_not_ignored_and_local_state_excluded(self):
        self.bootstrap('--workflow', 'none', '--skip-skills', '--skip-understand-anything')
        assets = ['.claude/settings.json', '.claude/launch.json', '.claude/skills/my/SKILL.md',
                  '.claude/hooks/check.sh', '.claude/agents/reviewer.md', '.claude/commands/check.md',
                  '.agents/skills/my/SKILL.md', 'skills-lock.json', 'package-lock.json', 'uv.lock',
                  '_bmad/_config/config.yaml', '_bmad-output/planning-artifacts/prd.md',
                  'docs/output/research.md', 'tests/fixtures/sample.db', '.env.example']
        local = ['.claude/settings.local.json', '.claude/worktrees/branch/private.txt',
                 '.agent/runtime/session.json', '.env', '.env.production', '.DS_Store']
        for name in assets + local:
            self.write(name)
        before = self.invoke()
        self.assertFalse((self.project / '.gitignore').exists())
        self.assertFalse((self.project / '.git').exists())
        self.invoke('--apply', '--expect', before['token'])
        self.git('init', '-q')
        for name in assets:
            self.assertEqual(self.git('check-ignore', '--no-index', name).returncode, 1, name)
        for name in local:
            self.assertEqual(self.git('check-ignore', '--no-index', name).returncode, 0, name)
        self.assertEqual(self.git('ls-files').stdout, '')
        self.assertNotEqual(self.git('remote', 'get-url', 'origin').returncode, 0)
        self.assertEqual(self.invoke()['changes'], [])

    def test_claude_preferences_protect_first_session_before_directory_exists(self):
        self.bootstrap('--workflow', 'none', '--skip-skills', '--skip-understand-anything', '--agent', 'claude-code')
        self.assertFalse((self.project / '.claude').exists())
        preview = self.invoke()
        self.assertEqual(preview['facts']['project_agents'], ['claude-code'])
        self.invoke('--apply', '--expect', preview['token'])
        self.git('init', '-q')
        for name in ('.claude/settings.local.json', '.claude/worktrees/topic/file.txt'):
            self.assertEqual(self.git('check-ignore', '--no-index', name).returncode, 0, name)
        self.assertEqual(self.git('check-ignore', '--no-index', '.claude/settings.json').returncode, 1)
        self.assertFalse((self.project / '.claude').exists())

    def test_preference_change_invalidates_ignore_preview(self):
        self.bootstrap('--workflow', 'none', '--skip-skills', '--skip-understand-anything', '--agent', 'claude-code')
        preview = self.invoke()
        path = self.project / '.agent/bootstrap.yml'
        path.write_text(path.read_text().replace('["claude-code"]', '["codex"]'))
        self.invoke('--apply', '--expect', preview['token'], expected=1)
        self.assertFalse((self.project / '.gitignore').exists())

    def test_existing_repo_does_not_need_temporary_git_initialization(self):
        self.git('init', '-q')
        self.env['TMPDIR'] = str(self.base / 'does-not-exist')
        self.invoke()
        self.assertFalse((self.base / 'does-not-exist').exists())

    def test_existing_rules_preserved_and_broad_conflicts_reported(self):
        original = '# user rules\n/.*\n/_*\n*.lock\noutput/\n'
        path = self.write('.gitignore', original)
        self.write('_bmad-output/spec.md')
        preview = self.invoke()
        self.assertIn('_bmad-output/spec.md', [x['path'] for x in preview['facts']['ignored_candidates']])
        self.apply()
        self.assertTrue(path.read_text().startswith(original))
        self.assertIn('.claude/settings.json', [x['path'] for x in self.invoke()['facts']['ignored_candidates']])
        self.assertFalse((self.project / '.git').exists())

    def test_update_even_force_preserves_legacy_skills_until_explicit_migration(self):
        self.bootstrap('--workflow', 'none', '--skip-skills', '--skip-understand-anything')
        legacy = '*\n!.gitignore\n'
        ignore = self.write('.agents/skills/.gitignore', legacy)
        manifest = self.project / '.agent/bootstrap.yml'
        text = manifest.read_text()
        old_hash = hashlib.sha256((root / 'templates/skills.gitignore').read_bytes()).hexdigest()
        manifest.write_text(text.replace(old_hash, hashlib.sha256(legacy.encode()).hexdigest()))
        self.write('.agents/skills/shared/SKILL.md')
        for flags in (('--update',), ('--update', '--force')):
            output = self.bootstrap(*flags)
            self.assertEqual(ignore.read_text(), legacy)
            self.assertIn('Preserved Skill ignore boundary', output)
        self.apply()
        self.assertEqual(ignore.read_text(), legacy)
        preview = self.invoke('--migrate-skills')
        self.assertIn('.agents/skills/shared/SKILL.md', [x['path'] for x in preview['facts']['ignored_candidates']])
        self.invoke('--migrate-skills', '--apply', '--expect', preview['token'])
        self.git('init', '-q')
        self.assertEqual(self.git('check-ignore', '.agents/skills/shared/SKILL.md').returncode, 1)
        self.assertEqual(self.git('ls-files').stdout, '')

    def test_custom_skill_ignore_never_rewritten(self):
        custom = self.write('.claude/skills/.gitignore', '*\n!.gitignore\n# personal\n')
        self.apply('--migrate-skills')
        self.assertEqual(custom.read_text(), '*\n!.gitignore\n# personal\n')

    def test_changed_preview_and_missing_token_rejected(self):
        first = self.invoke()
        self.invoke('--apply', expected=1)
        self.write('.gitignore', '# later user edit\n')
        self.invoke('--apply', '--expect', first['token'], expected=1)
        self.assertEqual((self.project / '.gitignore').read_text(), '# later user edit\n')

    def test_instruction_references_are_additive_and_require_confirmation(self):
        agents = self.write('AGENTS.md', '# Existing\nPreserve my process.\n')
        claude = self.write('CLAUDE.md', '# Harness rules\n')
        self.invoke()
        self.assertEqual(agents.read_text(), '# Existing\nPreserve my process.\n')
        self.apply()
        self.assertTrue(agents.read_text().startswith('# Existing\nPreserve my process.\n'))
        self.assertIn('.agent/policies/git.md', agents.read_text())
        self.assertIn('AGENTS.md', claude.read_text())
        self.assertEqual(self.invoke()['changes'], [])

    def test_symlink_policy_paths_rejected_without_writing_outside(self):
        outside = self.base / 'outside'
        outside.write_text('keep\n')
        for name in ('.gitignore', 'AGENTS.md', 'CLAUDE.md'):
            path = self.project / name
            path.symlink_to(outside)
            self.invoke(expected=1)
            self.assertEqual(outside.read_text(), 'keep\n')
            path.unlink()
        (self.project / '.agents').symlink_to(self.base)
        self.invoke(expected=1)
        self.assertFalse((self.project / '.gitignore').exists())

    def test_runtime_link_only_exact_path_is_ignored(self):
        target = '.agent/runtime/understand-anything/repo/understand-anything-plugin/skills/understand'
        self.write(target + '/SKILL.md')
        link = self.project / '.agents/skills/understand'
        link.parent.mkdir(parents=True)
        link.symlink_to('../../' + target)
        self.write('.agents/skills/custom/SKILL.md')
        self.apply()
        self.git('init', '-q')
        self.assertEqual(self.git('check-ignore', '.agents/skills/understand').returncode, 0)
        self.assertEqual(self.git('check-ignore', '.agents/skills/custom/SKILL.md').returncode, 1)

    def test_tracked_local_files_reported_never_removed(self):
        self.git('init', '-q')
        self.write('.claude/settings.local.json')
        staged = self.git('add', '-f', '.claude/settings.local.json')
        self.assertEqual(staged.returncode, 0, staged.stderr)
        index = self.git('ls-files', '--stage').stdout
        preview = self.invoke()
        self.assertIn('.claude/settings.local.json', preview['facts']['tracked_local_candidates'])
        self.invoke('--apply', '--expect', preview['token'])
        self.assertEqual(self.git('ls-files', '--stage').stdout, index)

    def test_actual_repository_info_excludes_are_reported(self):
        self.git('init', '-q')
        self.write('.git/info/exclude', '/.claude/\n')
        self.write('.claude/settings.json')
        matches = self.invoke()['facts']['ignored_candidates']
        self.assertTrue(any(x['path'] == '.claude/settings.json' and x['source'].endswith('info/exclude') for x in matches))

    def test_nested_target_rejected(self):
        self.git('init', '-q')
        self.project = self.project / 'nested'
        self.project.mkdir()
        self.invoke(expected=1)
        self.assertFalse((self.project / '.gitignore').exists())


unittest.main(verbosity=2)
PY
