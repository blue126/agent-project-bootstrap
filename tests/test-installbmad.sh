#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${TMPDIR:?Set TMPDIR to a writable temporary directory}"

# Dependencies are provisioned separately; these tests never install packages.
python3 -B - "${repo_root}" <<'PY'
import copy
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
root = Path(sys.argv.pop())
skill = root / 'skills/installbmad'
spec = importlib.util.spec_from_file_location('installbmad', skill / 'scripts/installbmad.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class InstallBmadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ['TMPDIR'])
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.target = self.base / 'project with spaces; $(not-a-command)'
        self.target.mkdir()

    def write(self, relative, content):
        path = self.target / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding='utf-8')
        return path

    def manifest(self, modules=('core', 'bmm'), tools=('claude-code',), objects=False):
        value = {
            'installation': {'version': '6.12.0'},
            'modules': [{'name': m, 'version': '1.0.0'} for m in modules] if objects else list(modules),
            'ides': list(tools),
        }
        self.write('_bmad/_config/manifest.yaml', helper.yaml.safe_dump(value))
        for module in modules:
            (self.target / '_bmad' / module).mkdir(parents=True, exist_ok=True)

    def plan(self, modules=('bmm',), tools=('claude-code',)):
        return helper.preflight(self.target, '6.12.0', list(modules), list(tools))

    def installed_files(self):
        self.manifest()
        self.write('_bmad/_config/bmad-help.csv', 'module,skill,display-name\n'
                   'Core,bmad-help,Help\nBMad Method,bmad-prd,PRD\n'
                   'BMad Method,bmad-architecture,Architecture\nBMad Method,bmad-build,Build\n')
        for name in helper.BMM_SKILLS | {'bmad-help'}:
            self.write(f'.claude/skills/{name}/SKILL.md', f'---\nname: {name}\n---\nInstructions\n')

    def snapshot(self):
        return {
            str(p.relative_to(self.target)): ('link', os.readlink(p)) if p.is_symlink()
            else ('directory',) if p.is_dir() else ('file', p.read_bytes())
            for p in self.target.rglob('*')
        }

    def test_fresh_plan_uses_literal_target_and_pinned_version(self):
        result = self.plan()
        self.assertIsNone(result['action'])
        self.assertNotIn('--action', result['argv'])
        self.assertIn('bmad-method@6.12.0', result['argv'])
        self.assertEqual(result['argv'][result['argv'].index('--directory') + 1], str(self.target))
        self.assertEqual(result['expected']['modules'], ['bmm', 'core'])

    def test_union_preserves_modules_tools_and_unknown_ids(self):
        for objects in (False, True):
            with self.subTest(objects=objects):
                self.manifest(('core', 'bmb', 'cis', 'custom-x'), ('codex', 'unknown-tool'), objects)
                result = self.plan(('bmm', 'bmm'))
                self.assertEqual(result['action'], 'update')
                self.assertEqual(set(result['expected']['modules']), {'core', 'bmb', 'cis', 'custom-x', 'bmm'})
                self.assertEqual(set(result['expected']['tools']), {'codex', 'unknown-tool', 'claude-code'})
                self.assertEqual(result['argv'][result['argv'].index('--modules') + 1], 'bmb,bmm,cis,custom-x')
                self.assertNotIn('quick-update', result['argv'])

    def test_existing_empty_tools_and_core_only_request(self):
        self.manifest(('core',), ())
        result = self.plan(('core',))
        self.assertEqual(result['expected']['tools'], ['claude-code'])
        self.assertEqual(result['argv'][result['argv'].index('--modules') + 1], 'core')

    def test_bad_manifests_never_become_fresh_installs(self):
        invalid = [
            '', '[]', 'modules: [',
            'installation: {version: 6.12.0}\nmodules: [core]\n',
            'installation: {version: 6.12.0}\nmodules: [core]\nides: null\n',
            'installation: {version: 6.12.0}\nmodules: [core]\nides: claude-code\n',
            'installation: {version: 6.12.0}\nmodules: []\nides: []\n',
            'installation: {version: 6.12.0}\nmodules: [core, {}]\nides: []\n',
            'installation: {version: 6.12.0}\nmodules: [core, {name: [bmm]}]\nides: []\n',
            'installation: {version: 6.12.0}\nmodules: [core]\nmodules: [bmm]\nides: []\n',
            'installation: {version: 6.12.0}\nmodules: [core]\nides: [false]\n',
            '!!python/object/apply:os.system ["touch SHOULD-NOT-EXIST"]',
        ]
        for content in invalid:
            with self.subTest(content=content):
                self.write('_bmad/_config/manifest.yaml', content)
                with self.assertRaises((ValueError, helper.yaml.YAMLError)):
                    self.plan()

    def test_invalid_requested_ids_and_versions(self):
        for modules in ([], [''], ['bmm,bmb'], ['../core'], ['--help'], ['bmm;touch x']):
            with self.subTest(modules=modules), self.assertRaises(ValueError):
                self.plan(modules)
        for version in ('latest', 'next', '6.13.0', '6.12.0;touch x'):
            with self.subTest(version=version), self.assertRaises(ValueError):
                helper.preflight(self.target, version, ['bmm'], ['claude-code'])

    def test_incomplete_and_legacy_install_evidence(self):
        for relative in ('_bmad', 'bmad', '.claude/skills/bmad-help'):
            path = self.target / relative
            path.mkdir(parents=True)
            with self.subTest(relative=relative), self.assertRaises(ValueError):
                self.plan()
            shutil.rmtree(path)

    def test_dangling_manifest_and_escaping_paths(self):
        outside = self.base / 'outside'
        outside.mkdir()
        (self.target / '_bmad').symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'escapes'):
            self.plan()
        (self.target / '_bmad').unlink()
        manifest = self.target / '_bmad/_config/manifest.yaml'
        manifest.parent.mkdir(parents=True)
        manifest.symlink_to(manifest.parent / 'missing')
        with self.assertRaises(ValueError):
            self.plan()

    def test_target_validation(self):
        self.assertEqual(helper.target_directory(str(self.target)), self.target)
        for path in ('relative', str(self.base / 'missing'), str(self.write('file', 'data'))):
            with self.subTest(path=path), self.assertRaises((ValueError, OSError)):
                helper.target_directory(path)

    def test_before_record_rejects_other_target_and_changed_expectations(self):
        before = self.plan()
        saved = self.base / 'before.json'
        saved.write_text(json.dumps(before))
        self.assertEqual(helper.load_record(self.target, saved), before)
        with self.assertRaises(ValueError):
            helper.load_record(self.base, saved)
        changed = copy.deepcopy(before)
        changed['expected']['modules'] = ['core']
        saved.write_text(json.dumps(changed))
        with self.assertRaises(ValueError):
            helper.load_record(self.target, saved)

    def test_successful_verification_remains_read_only(self):
        before = self.plan()
        self.installed_files()
        self.write('.claude/skills/unrelated/SKILL.md', 'Other skill')
        snapshot = self.snapshot()
        with patch('subprocess.Popen', side_effect=AssertionError('Must not start processes')), \
             patch('os.system', side_effect=AssertionError('Must not execute commands')):
            self.plan()
            result = helper.verify(self.target, before)
        self.assertEqual(result['status'], 'files_verified')
        self.assertEqual(result['claude_skill_count'], 5)
        self.assertEqual(result['session_loading'], 'not_verified')
        self.assertEqual(self.snapshot(), snapshot)

    def test_missing_retained_module_and_tool_fail(self):
        self.manifest(('core', 'bmb', 'cis'), ('codex',))
        before = self.plan()
        self.installed_files()
        result = helper.verify(self.target, before)
        self.assertEqual(result['status'], 'failed')
        self.assertTrue(any('bmb, cis' in error for error in result['errors']))
        self.assertTrue(any('codex' in error for error in result['errors']))

    def test_missing_module_directory_is_not_hidden_by_manifest(self):
        before = self.plan()
        self.installed_files()
        shutil.rmtree(self.target / '_bmad/bmm')
        result = helper.verify(self.target, before)
        self.assertEqual(result['status'], 'failed')
        self.assertIn('Missing module directory: bmm', result['errors'])

    def test_unrelated_external_skill_does_not_fail_bmad_verification(self):
        before = self.plan()
        self.installed_files()
        other = self.base / 'global-skill'
        other.mkdir()
        (other / 'SKILL.md').write_text('Global instructions')
        (self.target / '.claude/skills/unrelated').symlink_to(other, target_is_directory=True)
        result = helper.verify(self.target, before)
        self.assertEqual(result['status'], 'files_verified')
        self.assertEqual(result['claude_skill_count'], 4)

    def test_missing_or_malformed_catalog_and_entries_fail(self):
        before = self.plan()
        for content in ('', 'wrong,header\nx,y\n', 'module,skill\nCore\n',
                        'module,skill\nCore,bmad-help,extra\n',
                        'module,skill\nCore,bmad-help\n'):
            with self.subTest(content=content):
                self.installed_files()
                self.write('_bmad/_config/bmad-help.csv', content)
                self.assertEqual(helper.verify(self.target, before)['status'], 'failed')
        (self.target / '_bmad/_config/bmad-help.csv').unlink()
        self.assertEqual(helper.verify(self.target, before)['status'], 'failed')

    def test_nonzero_count_does_not_mask_missing_bmad_entry(self):
        before = self.plan()
        self.installed_files()
        self.write('.claude/skills/unrelated/SKILL.md', 'Other skill')
        path = self.target / '.claude/skills/bmad-build/SKILL.md'
        path.unlink()
        self.assertEqual(helper.verify(self.target, before)['status'], 'failed')
        path.symlink_to(path.parent / 'missing')
        self.assertEqual(helper.verify(self.target, before)['status'], 'failed')

    def test_internal_skill_symlink_works_but_external_one_fails(self):
        before = self.plan()
        self.installed_files()
        path = self.target / '.claude/skills/bmad-build/SKILL.md'
        path.unlink()
        source = self.write('_bmad/bmm/bmad-build/SKILL.md', 'Build instructions')
        path.symlink_to(source)
        self.assertEqual(helper.verify(self.target, before)['status'], 'files_verified')
        path.unlink()
        external = self.base / 'external-skill.md'
        external.write_text('External build')
        path.symlink_to(external)
        self.assertEqual(helper.verify(self.target, before)['status'], 'failed')

    def test_version_mismatch_and_downgrade(self):
        before = self.plan()
        self.installed_files()
        path = self.target / '_bmad/_config/manifest.yaml'
        path.write_text(path.read_text().replace('6.12.0', '6.13.0'))
        self.assertEqual(helper.verify(self.target, before)['status'], 'failed')
        with self.assertRaisesRegex(ValueError, 'downgrade'):
            self.plan()

    def test_cli_runs_from_standalone_skill_without_target_writes(self):
        standalone = self.base / 'standalone-skill'
        shutil.copytree(skill, standalone)
        script = standalone / 'scripts/installbmad.py'
        argv = [sys.executable, '-B', str(script)]
        result = subprocess.run(argv + ['preflight', '--target', str(self.target),
            '--installer-version', '6.12.0', '--modules', 'bmm', '--tools', 'claude-code'],
            cwd=self.base, capture_output=True, text=True, check=True)
        before = self.base / 'before.json'
        before.write_text(result.stdout)
        self.assertEqual(list(self.target.iterdir()), [])
        self.installed_files()
        snapshot = self.snapshot()
        check = argv + ['verify', '--target', str(self.target), '--before', str(before)]
        result = subprocess.run(check, cwd=self.base, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)['status'], 'files_verified')
        self.assertEqual(self.snapshot(), snapshot)
        (self.target / '.claude/skills/bmad-prd/SKILL.md').unlink()
        self.assertEqual(subprocess.run(check, capture_output=True).returncode, 1)
        before.write_text('{}')
        self.assertEqual(subprocess.run(check, capture_output=True).returncode, 2)
        missing_dep = subprocess.run([sys.executable, '-S', str(script), '--help'], capture_output=True, text=True)
        self.assertEqual(missing_dep.returncode, 2)
        self.assertIn('requirements.txt', missing_dep.stderr)

    def test_live_smoke_requires_opt_in_and_rejects_project_targets(self):
        smoke = skill / 'scripts/smoke.py'
        env = dict(os.environ, TMPDIR=str(self.base), PATH='')
        for arguments in ([], ['--run', '--target', str(self.target)]):
            with self.subTest(arguments=arguments):
                result = subprocess.run([sys.executable, '-B', str(smoke), *arguments],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 2)
                self.assertFalse(list(self.base.glob('installbmad-live-*')))

    def test_documentation_contract(self):
        main = (skill / 'SKILL.md').read_text()
        # Agent-only consent guards stay visible; executable behavior is tested above.
        for phrase in ('非交互', 'worktree', '.gitignore', '新会话', '不启动工作流'):
            self.assertIn(phrase, main)
        for document in [skill / 'SKILL.md', *sorted((skill / 'references').glob('*.md'))]:
            text = document.read_text()
            for block in re.findall(r'^```bash\n(.*?)^```', text, re.M | re.S):
                subprocess.run(['bash', '-n'], input=block, text=True, check=True)
            for link in re.findall(r'\[[^\]]+\]\(([^)]+)\)', text):
                if not re.match(r'[a-zA-Z][\w+.-]*:', link) and not link.startswith(('#', '/')):
                    self.assertTrue((document.parent / link.split('#')[0]).exists(), link)


unittest.main(verbosity=2)
PY
