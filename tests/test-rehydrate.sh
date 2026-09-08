#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${TMPDIR:?Set TMPDIR to a writable temporary directory}"

# Offline isolated copies, fake UA installer and native-CLI tripwire only.
python3 -B - "${repo_root}" <<'PY'
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

root = Path(sys.argv.pop())


class RehydrateTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(dir=os.environ['TMPDIR'])
        self.addCleanup(temp.cleanup)
        self.base = Path(temp.name).resolve()
        self.repo = self.base / 'source checkout; $(not-executed)'
        scripts = self.repo / 'scripts'
        scripts.mkdir(parents=True)
        shutil.copy2(root / 'scripts/rehydrate.sh', scripts)
        (scripts / 'lib').mkdir()
        for name in ('onboarding-project.py', 'merge-bootstrap-config.py'):
            shutil.copy2(root / 'scripts/lib' / name, scripts / 'lib' / name)
        shutil.copy2(root / 'bootstrap-manifest.yml', self.repo)
        self.target = self.base / "project 'quotes'; $(not-executed)"
        (self.target / '.agent').mkdir(parents=True)
        self.log = self.base / 'ua.json'
        ua = scripts / 'install-understand-anything.sh'
        ua.write_text('#!/usr/bin/env python3\nimport json, os, sys\n'
                      'from pathlib import Path\n'
                      'Path(os.environ["UA_LOG"]).write_text(json.dumps(sys.argv[1:]))\n')
        ua.chmod(0o755)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        npx = self.bin / 'npx'
        npx.write_text('#!/bin/sh\nprintf forbidden > "$NPX_LOG"\nexit 99\n')
        npx.chmod(0o755)
        self.env = dict(os.environ, UA_LOG=str(self.log), NPX_LOG=str(self.base / 'npx.log'),
                        PATH=str(self.bin) + os.pathsep + os.environ['PATH'])

    def metadata(self, agents=None, curated='skip', ua='skip', superpowers='skip', workflow='none'):
        content = (f'workflow_id: {workflow}\ncomponents:\n  curated_skills: {curated}\n'
                   f'integrations:\n  understand_anything:\n    installation: {ua}\n'
                   f'superpowers:\n  installation: {superpowers}\n'
                   'unknown_future_metadata:\n  nested: [keep, this, exactly]\n')
        if agents is not None:
            content += f'project_agents: {agents}\n'
        manifest = self.target / '.agent/bootstrap.yml'
        manifest.write_text(content)
        return manifest

    def run_restore(self):
        manifest = self.target / '.agent/bootstrap.yml'
        original = manifest.read_bytes() if manifest.exists() else None
        result = subprocess.run(['bash', str(self.repo / 'scripts/rehydrate.sh'), '--target', str(self.target)],
                                env=self.env, capture_output=True, text=True)
        self.assertFalse((self.base / 'npx.log').exists(), 'Must not execute native Skills installer')
        self.assertFalse((self.target / '.git').exists(), 'Must not invent Git repository/origin')
        if original is not None:
            self.assertEqual(manifest.read_bytes(), original, 'Metadata must remain byte-for-byte intact')
        self.assertEqual(sorted(str(p.relative_to(self.target)) for p in self.target.rglob('*')),
                         ['.agent', '.agent/bootstrap.yml'] if original is not None else ['.agent'])
        return result

    def commands(self, output):
        result = []
        for line in output.splitlines():
            if line.startswith('  cd '):
                words = shlex.split(line)
                self.assertEqual(words[:3], ['cd', str(self.target), '&&'])
                result.append(words[3:])
        return result

    def test_multi_client_restore_is_safe_and_manual_work_stays_pending(self):
        selected = ['claude-code', 'codex', 'opencode']
        self.metadata(json.dumps(selected), curated='install', ua='install', superpowers='install')
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.log.read_text()), ['--target', str(self.target),
                         '--agent', 'claude-code', '--agent', 'codex', '--agent', 'opencode'])
        commands = self.commands(result.stdout)
        self.assertEqual(len(commands), 2)
        for command in commands:
            self.assertEqual(command[:3], ['npx', 'skills@1.5.23', 'add'])
            self.assertEqual(command[4:], ['--agent', *selected])
            self.assertNotIn('--yes', command)
            self.assertNotIn('--all', command)
        self.assertEqual(commands[0][3], str(self.repo))
        self.assertIn('Rehydration pending', result.stdout)
        self.assertNotIn('Rehydration complete', result.stdout)

    def test_no_field_keeps_legacy_interactive_client_choice(self):
        self.metadata(curated='install', ua='install')
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.log.read_text()), ['--target', str(self.target)])
        self.assertNotIn('--agent', self.commands(result.stdout)[0])

    def test_universal_is_supported(self):
        self.metadata('["universal"] # selected explicitly', curated='install', ua='install')
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.log.read_text())[-2:], ['--agent', 'universal'])
        self.assertEqual(self.commands(result.stdout)[0][-2:], ['--agent', 'universal'])

    def test_invalid_selection_fails_before_any_installer(self):
        for field in ('["unknown"]', '["universal", "universal"]', '[claude-code]', 'null', '"codex"', '[1]',
                      '["codex;touch x"]', '["codex"] trailing',
                      '["codex"]\nproject_agents: ["claude-code"]'):
            with self.subTest(field=field):
                self.metadata(field, ua='install')
                result = self.run_restore()
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.log.exists())
                self.assertNotIn('Rehydration complete', result.stdout)

    def test_missing_shared_helpers_fail_without_fallback(self):
        self.metadata('["codex"]', ua='install')
        for name in ('onboarding-project.py', 'merge-bootstrap-config.py'):
            helper = self.repo / 'scripts/lib' / name
            helper.unlink()
            result = self.run_restore()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Missing shared metadata helper', result.stderr)
            self.assertFalse(self.log.exists())
            shutil.copy2(root / 'scripts/lib' / name, helper)

    def test_tabs_quotes_and_comments_use_shared_scalar_semantics(self):
        manifest = self.metadata('["claude-code"]\t# selected', curated='"install"\t# curated',
                                 ua="'install'\t# runtime", superpowers='install\t# pack',
                                 workflow='"superpowers" # chosen')
        manifest.write_text(manifest.read_text().replace(': ', ':\t'))
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.log.read_text())[-2:], ['--agent', 'claude-code'])
        self.assertEqual(len(self.commands(result.stdout)), 2)
        self.assertIn('Recorded workflow: superpowers', result.stdout)

    def test_hash_inside_quotes_is_not_an_install_action(self):
        self.metadata('["codex"]', curated='"install # not selected"',
                      ua="'install # not selected'", superpowers='"install\\nskip"')
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.log.exists())
        self.assertEqual(self.commands(result.stdout), [])
        self.assertIn('Rehydration complete', result.stdout)

    def test_bmad_restore_is_explicitly_pending(self):
        self.metadata('["codex"]', workflow='bmad')
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('BMAD manual restore pending', result.stdout)
        self.assertNotIn('Rehydration complete', result.stdout)
        self.assertFalse(self.log.exists())

    def test_no_recorded_installation_finishes_without_writes(self):
        self.metadata()
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Rehydration complete', result.stdout)
        self.assertFalse(self.log.exists())

    def test_unrelated_installation_fields_do_not_authorize_restore(self):
        manifest = self.metadata()
        manifest.write_text('future:\n  installation: install\n  child:\n    installation: install\n'
                            + manifest.read_text())
        result = self.run_restore()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Rehydration complete', result.stdout)
        self.assertFalse(self.log.exists())
        self.assertEqual(self.commands(result.stdout), [])

    def test_duplicate_installation_selection_is_blocked(self):
        for duplicate in ('integrations:\n  understand_anything:\n    installation: skip\n',
                          'workflow_id: none\n'):
            manifest = self.metadata(ua='install')
            manifest.write_text(manifest.read_text() + duplicate)
            result = self.run_restore()
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(self.log.exists())
        manifest = self.metadata(ua='install')
        manifest.write_text(manifest.read_text().replace('    installation: install\n',
                            '    installation: install\n    installation: skip\n'))
        result = self.run_restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists())

    def test_missing_metadata_reports_failure(self):
        result = self.run_restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No .agent/bootstrap.yml', result.stderr)


unittest.main(verbosity=2)
PY
