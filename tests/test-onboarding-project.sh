#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:?TMPDIR must be set}/onboarding-project.XXXXXX")"
trap 'rm -rf "${test_root}"' EXIT
python3 -B - "${repo_root}" "${test_root}" <<'PY'
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import unittest
from unittest import mock

repo, temporary = map(Path, sys.argv[1:])
source = temporary / "source"
(source / "scripts/lib").mkdir(parents=True)
for name in ("onboarding-project.py", "merge-bootstrap-config.py"):
    shutil.copyfile(repo / "scripts/lib" / name, source / "scripts/lib" / name)
manifest = (repo / "bootstrap-manifest.yml").read_text()
manifest = manifest.replace("\nonboarding:\n", "    - name: fixture-client\n      project_path: .fixture/skills\n      bmad_tool: none\n\nonboarding:\n")
(source / "bootstrap-manifest.yml").write_text(manifest)
(source / "skills/pre-mortem").mkdir(parents=True)
(source / "skills/pre-mortem/SKILL.md").write_text("Fixture curated skill\n")
(source / "integrations/understand-anything").mkdir(parents=True)
shutil.copyfile(repo / "integrations/understand-anything/integration.yml", source / "integrations/understand-anything/integration.yml")
helper = source / "scripts/lib/onboarding-project.py"
spec = importlib.util.spec_from_file_location("onboarding_project", helper)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
env = dict(os.environ, HOME=str(temporary / "home"), XDG_CONFIG_HOME=str(temporary / "home/.config"))
Path(env["HOME"]).mkdir()
for key in list(env):
    if key.startswith("GIT_"):
        del env[key]


def run(*args, check=True):
    return subprocess.run(args, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=check)


class LocalProjectTests(unittest.TestCase):
    count = 0

    def setUp(self):
        LocalProjectTests.count += 1
        self.project = temporary / f"project-{self.count}"
        self.project.mkdir()
        self.config = self.project / ".agent/bootstrap.yml"

    def write(self, relative, content="fixture\n"):
        path = self.project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def cli(self, *args, ok=True):
        result = run(sys.executable, str(helper), "--project", str(self.project), *args, check=False)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(result.stdout)
        return result.stderr

    def local_cli(self, *args):
        output = io.StringIO()
        with mock.patch.object(sys, 'argv', [str(helper), '--project', str(self.project), *args]), contextlib.redirect_stdout(output):
            self.assertEqual(module.main(), 0)
        return json.loads(output.getvalue())

    def config_file(self, extra=""):
        self.write(".agent/bootstrap.yml", "schema_version: 5\nworkflow_id: none\ncomponents:\n  curated_skills: skip\n  workflow_pack: none\n" + extra)

    def baseline(self):
        self.config_file()
        self.write("AGENTS.md", "Read .agent/policies/git.md\n")
        self.write(".agent/policies/git.md", "Project Git policy\n")
        self.write("CLAUDE.md", "Read AGENTS.md\n")
        self.write(".gitignore", "# project ignore policy\n")
        run("git", "-C", str(self.project), "init", "-q", "--initial-branch=main")
        run("git", "-C", str(self.project), "config", "user.name", "Fixture")
        run("git", "-C", str(self.project), "config", "user.email", "fixture@example.invalid")

    def ready(self, workflow="none", agents=("claude-code",)):
        return self.cli("readiness", "--agents", *agents, "--workflow", workflow)

    def save(self, workflow="none", agents=("claude-code",), expect=None, ok=True):
        if expect is None:
            expect = self.cli("clients")["config_sha256"] or "missing"
        return self.cli("save", "--agents", *agents, "--workflow", workflow, "--expect", expect, ok=ok)

    def test_missing_directory_inspection_never_creates_it(self):
        self.project = self.project / 'absent'
        self.assertEqual(self.cli('clients')['selected'], [])
        self.assertFalse(self.ready()['ready'])
        self.assertFalse(self.project.exists())

    def test_missing_client_links_are_previewed_then_added_without_reinstall(self):
        source_file = self.write('.agents/skills/github-workflow/SKILL.md', 'Customized project skill\n')
        preview = self.cli('links', '--agents', 'claude-code', 'codex')
        self.assertEqual(len(preview['links']), 1)
        destination = self.project / '.claude/skills/github-workflow'
        self.assertFalse(destination.exists())
        self.cli('links', '--agents', 'claude-code', 'codex', '--apply', '--expect', preview['token'])
        self.assertTrue(destination.is_symlink())
        self.assertEqual((destination / 'SKILL.md').read_text(), source_file.read_text())
        self.assertEqual(self.cli('links', '--agents', 'claude-code')['links'], [])
        self.assertFalse((self.project / '.git').exists())

    def test_client_link_preview_rejects_changed_target_and_ambiguous_sources(self):
        self.write('.agents/skills/custom/SKILL.md', 'Source A\n')
        preview = self.cli('links', '--agents', 'claude-code')
        self.write('.claude/skills/custom/SKILL.md', 'Source B\n')
        self.cli('links', '--agents', 'claude-code', '--apply', '--expect', preview['token'], ok=False)
        self.assertEqual((self.project / '.claude/skills/custom/SKILL.md').read_text(), 'Source B\n')
        ambiguous = self.cli('links', '--agents', 'fixture-client')
        self.assertEqual(ambiguous['links'], [])
        self.assertTrue(ambiguous['conflicts'])

    def test_missing_snapshot_and_manifest_client_paths(self):
        info = self.cli("clients")
        self.assertEqual(info, {"selected": [], "detected": [], "workflow": "none", "installed_workflows": [], "config_sha256": None})
        self.write(".fixture/skills/custom/SKILL.md")
        self.assertIn("fixture-client", self.cli("clients")["detected"])
        self.assertIn("must exist", self.save(expect="missing", ok=False))
        self.assertFalse(self.config.exists())

    def test_separate_selection_detection_and_known_artifacts(self):
        self.config_file('project_agents: ["claude-code"]\n')
        self.config.write_text(self.config.read_text().replace("workflow_id: none", "workflow_id: superpowers"))
        self.write(".agents/skills/github-workflow/SKILL.md")
        self.write(".agents/skills/unknown-framework/SKILL.md")
        info = self.cli("clients")
        self.assertEqual(info["selected"], ["claude-code"])
        self.assertEqual(info["detected"], ["codex", "opencode", "universal"])
        self.assertEqual(info["workflow"], "superpowers")
        self.assertEqual(info["installed_workflows"], ["github-workflow"])

    def test_metadata_contract_and_bounded_client_discovery(self):
        self.assertEqual(self.cli('metadata'), {
            'selected': [], 'workflow': 'none', 'config_sha256': None,
            'curated_skills': '', 'workflow_pack': '', 'understand_anything': '', 'superpowers': ''})
        self.config_file('project_agents:\t["codex", "claude-code"] # selected\n'
                         'integrations:\n  understand_anything:\n    installation:\t"install"\t# recorded\n'
                         "superpowers:\n  installation: 'install # preserved scalar'\n"
                         'future:\n  arbitrary: [unknown, format]\n')
        for root in ('.agents/skills', '.claude/skills', '.fixture/skills'):
            for name in (*module.WORKFLOWS.values(), *(f'ordinary-{i}' for i in range(20))):
                self.write(f'{root}/{name}/SKILL.md')
        with mock.patch.object(module, 'read_bytes', wraps=module.read_bytes) as reads, \
                mock.patch.object(Path, 'iterdir', side_effect=AssertionError('Do not enumerate Skills')):
            result = self.local_cli('clients')
        skill_reads = [call.args[0] for call in reads.call_args_list if call.args[0].name == 'SKILL.md']
        self.assertEqual(len(skill_reads), 9, 'Only three markers per distinct client root')
        self.assertEqual(result['installed_workflows'], ['github-workflow', 'superpowers'])
        with mock.patch.object(module, 'skill_names', side_effect=AssertionError('No Skill inspection')), \
                mock.patch.object(module, 'path_in', wraps=module.path_in) as paths:
            data = self.local_cli('metadata')
        self.assertEqual([str(call.args[1]) for call in paths.call_args_list], ['.agent/bootstrap.yml'])
        self.assertEqual(data, {'selected': ['codex', 'claude-code'], 'workflow': 'none',
                               'config_sha256': hashlib.sha256(self.config.read_bytes()).hexdigest(),
                               'curated_skills': 'skip', 'workflow_pack': 'none',
                               'understand_anything': 'install', 'superpowers': 'install # preserved scalar'})

    def test_readiness_requires_metadata_but_allows_prewrite_workflow_check(self):
        self.baseline()
        self.write('.claude/skills/github-workflow/SKILL.md')
        report = self.ready('github-workflow')
        self.assertTrue(report['ready'], report)
        self.assertEqual(report['persisted_workflow'], 'none')
        self.config.unlink()
        self.assertEqual(self.cli('clients')['selected'], [])
        report = self.ready('github-workflow')
        self.assertFalse(report['ready'])
        self.assertFalse(report['config_present'])
        self.assertIn('Project .agent/bootstrap.yml is missing', report['issues'])
        self.assertTrue(report['clients'][0]['adapters_ready'])

    def test_save_preserves_metadata_and_owned_hashes_verbatim(self):
        unknown = "extension:\r\n  text: |\r\n    arbitrary: value\r\n  list: [1, {nested: true}]\r\n"
        managed = 'managed_files:\r\n  "AGENTS.md": "unchanged-hash"\r\n  .agent/policies/git.md: abc\r\n'
        self.config_file()
        self.config.write_bytes(self.config.read_bytes() + (unknown + managed).encode())
        self.write(".claude/skills/pre-mortem/SKILL.md")
        self.write(".claude/skills/github-workflow/SKILL.md")
        before = self.config.read_bytes()
        self.save("github-workflow", ("claude-code", "codex"))
        after = self.config.read_bytes()
        self.assertIn(unknown.encode(), after)
        self.assertIn(managed.encode(), after)
        self.assertIn(b'project_agents: ["claude-code", "codex"]\n', after)
        self.assertIn(b"  curated_skills: install\n", after)
        self.assertIn(b"  workflow_pack: github-workflow\n", after)
        self.assertNotEqual(before, after)
        self.assertEqual(self.cli("clients")["config_sha256"], hashlib.sha256(after).hexdigest())
        self.save("none")
        self.assertIn(b"  workflow_pack: github-workflow\n", self.config.read_bytes())
        self.assertFalse(list(self.config.parent.glob(".bootstrap-*")))
        self.assertFalse((self.project / ".git").exists())

    def test_stale_snapshot_and_duplicate_or_unsupported_config_fail_closed(self):
        self.config_file()
        stale = self.cli("clients")["config_sha256"]
        self.config.write_text(self.config.read_text() + "changed: true\n")
        before = self.config.read_bytes()
        self.save(expect=stale, ok=False)
        self.assertEqual(self.config.read_bytes(), before)
        for extra in ('project_agents: ["codex", "codex"]\n', 'project_agents: ["unknown"]\n',
                      "project_agents: [codex]\n", "project_agents:\n  - codex\n", "project_agents: null\n",
                      "workflow_id: none\n", '"workflow_id": none\n', "project_agents: [] trailing\n"):
            self.config_file(extra)
            before = self.config.read_bytes()
            self.cli("clients", ok=False)
            self.cli("metadata", ok=False)
            self.save(expect=hashlib.sha256(before).hexdigest(), ok=False)
            self.assertEqual(self.config.read_bytes(), before)
        self.config_file()
        self.save(agents=("codex", "codex"), ok=False)
        self.save(agents=("unknown",), ok=False)
        self.write(".claude/skills/pre-mortem/SKILL.md")
        self.config.write_text("workflow_id: none\ncomponents:\n  curated_skills: skip\n  curated_skills: skip\n")
        self.save(ok=False)

    def test_safe_links_and_policy_symlinks(self):
        self.baseline()
        self.write(".agents/skills/github-workflow/SKILL.md")
        (self.project / ".claude/skills").mkdir(parents=True)
        (self.project / ".claude/skills/github-workflow").symlink_to("../../.agents/skills/github-workflow")
        self.assertTrue(self.ready("github-workflow")["ready"])
        policy = self.project / ".agent/policies/git.md"
        policy.unlink()
        policy.symlink_to("../../AGENTS.md")
        self.assertFalse(self.ready()["policy_ready"])
        self.config.unlink()
        self.config.symlink_to("../AGENTS.md")
        self.cli("clients", ok=False)
        self.save(expect="missing", ok=False)

    def test_escaping_and_absolute_skills_are_rejected(self):
        self.baseline()
        outside = temporary / "outside-skill"
        outside.mkdir(exist_ok=True)
        (outside / "SKILL.md").write_text("private body never printed\n")
        self.write(".claude/skills/local/SKILL.md")
        link = self.project / ".claude/skills/github-workflow"
        link.symlink_to(os.path.relpath(outside, link.parent))
        result = self.ready("github-workflow")
        self.assertFalse(result["ready"])
        self.assertNotIn("private body", json.dumps(result))
        link.unlink()
        link.symlink_to(self.project / ".claude/skills/local")
        self.assertFalse(self.ready("github-workflow")["ready"])

    def test_none_baseline_and_git_root_identity_origin(self):
        self.baseline()
        result = self.ready()
        self.assertTrue(result["ready"], result)
        self.assertEqual(result["clients"][0]["skills"], [])
        self.assertTrue(result["workflow"]["installed"])
        self.assertEqual(result["git"], {"initialized": True, "branch": "main", "head": None, "identity_ready": True, "origin_present": False})
        child = self.project / "child"
        child.mkdir()
        parent = self.project
        self.project = child
        result = self.ready()
        self.assertFalse(result["git"]["initialized"])
        self.project = parent
        run("git", "-C", str(parent), "config", "--unset", "user.email")
        self.assertFalse(self.ready()["git"]["identity_ready"])
        self.assertEqual(run("git", "-C", str(parent), "remote").stdout, "")

    def test_workflow_required_for_every_selected_client_and_ignored_assets(self):
        self.baseline()
        self.write(".agents/skills/github-workflow/SKILL.md")
        result = self.ready("github-workflow", ("codex", "claude-code"))
        self.assertFalse(result["ready"])
        self.assertTrue(result["clients"][0]["ready"])
        self.assertFalse(result["clients"][1]["ready"])
        self.write(".claude/skills/github-workflow/SKILL.md")
        self.assertTrue(self.ready("github-workflow")["ready"])
        self.write(".agent/runtime/.gitignore", "*\n!.gitignore\n")
        self.write(".agent/runtime/local/file")
        self.assertTrue(self.ready("github-workflow")["ready"])
        for ignored in (".agent/", "AGENTS.md", ".claude/skills/github-workflow/SKILL.md"):
            self.write(".gitignore", ignored + "\n")
            result = self.ready("github-workflow")
            self.assertFalse(result["ready"])
            self.assertTrue(any("ignored by Git" in i for i in result["issues"]))

    def test_link_sources_are_critical_for_only_their_selected_clients(self):
        self.baseline()
        source_dir = self.write('shared skill/source/SKILL.md').parent
        link = self.project / '.claude/skills/custom'
        link.parent.mkdir(parents=True)
        link.symlink_to(os.path.relpath(source_dir, link.parent))
        self.write('.fixture/skills/unrelated/SKILL.md')
        for ignored in ('shared skill/', 'shared skill/source/SKILL.md', '.claude/skills/custom'):
            with self.subTest(ignored=ignored):
                self.write('.gitignore', ignored + '\n')
                report = self.ready(agents=('claude-code', 'fixture-client'))
                self.assertFalse(report['ready'])
                self.assertFalse(report['clients'][0]['ready'])
                self.assertTrue(report['clients'][1]['ready'])
                self.assertTrue(any('ignored by Git' in issue and 'claude-code' in issue for issue in report['issues']))
        self.write('.gitignore', '# changed; must inspect afresh\n')
        with mock.patch.object(module, 'git', wraps=module.git) as calls:
            report = self.local_cli('readiness', '--agents', 'claude-code', '--workflow', 'none')
        self.assertTrue(report['ready'], report)
        ignores = [call for call in calls.call_args_list if 'check-ignore' in call.args]
        self.assertEqual(len(ignores), 1)
        self.assertIn('--stdin', ignores[0].args)
        self.assertIn('-z', ignores[0].args)
        paths = ignores[0].kwargs['input'].decode().split('\0')
        self.assertIn('shared skill/source', paths)
        self.assertIn('shared skill/source/SKILL.md', paths)
        self.assertIn('.claude/skills/custom', paths)
        self.assertNotIn('.claude/skills/custom/SKILL.md', paths)

    def test_ignore_errors_fail_closed_without_invalidating_adapters(self):
        self.baseline()
        self.write('.claude/skills/github-workflow/SKILL.md')
        real_git = module.git
        def failed_ignore(project, *args, **kwargs):
            return (128, '') if 'check-ignore' in args else real_git(project, *args, **kwargs)
        with mock.patch.object(module, 'git', side_effect=failed_ignore):
            report = self.local_cli('readiness', '--agents', 'claude-code', '--workflow', 'github-workflow')
        self.assertFalse(report['ready'])
        self.assertFalse(report['clients'][0]['ready'])
        self.assertTrue(report['clients'][0]['adapters_ready'])
        self.assertTrue(any('Git ignore inspection failed' in issue for issue in report['issues']))
        with mock.patch.object(module.subprocess, 'run', side_effect=OSError('unavailable')):
            self.assertGreater(module.git(self.project, 'check-ignore')[0], 1)

    def test_bmad_adapter_repair_is_independent_of_ignore_policy(self):
        self.baseline()
        self.write('.agents/skills/bmad-help/SKILL.md')
        self.write('_bmad/_config/manifest.yaml', 'installation:\n  version: 6.12.0\nmodules:\n  - core\n')
        self.write('_bmad/_config/bmad-help.csv', 'module,skill\ncore,bmad-help\n')
        (self.project / '_bmad/core').mkdir()
        report = self.ready('bmad', ('opencode',))
        self.assertFalse(report['clients'][0]['adapters_ready'], 'Missing command requires adapter repair')
        self.write('.opencode/commands/bmad-help.md', '@skills/bmad-help\n')
        self.assertTrue(self.ready('bmad', ('opencode',))['ready'])
        for ignored in ('.agents/skills/', '_bmad/', '.opencode/commands/bmad-help.md'):
            self.write('.gitignore', ignored + '\n')
            report = self.ready('bmad', ('opencode',))
            self.assertFalse(report['ready'])
            self.assertFalse(report['clients'][0]['ready'])
            self.assertTrue(report['clients'][0]['adapters_ready'], 'Git policy must not trigger adapter reinstall')
        self.write('.gitignore', '# no ignores\n')
        self.write('_bmad/_config/bmad-help.csv', 'module,skill\ncore,other\n')
        report = self.ready('bmad', ('opencode',))
        self.assertFalse(report['ready'])
        self.assertTrue(report['clients'][0]['adapters_ready'], 'Core installation is separate from client adapters')

    def test_bmad_valid_markers_and_universal_unsupported(self):
        self.baseline()
        self.write(".claude/skills/bmad-help/SKILL.md")
        self.assertNotIn("bmad", self.cli("clients")["installed_workflows"])
        self.write("_bmad/_config/manifest.yaml", "installation:\n  version: 6.12.0\nmodules:\n  - name: core\nides:\n  - claude-code\n")
        self.write("_bmad/_config/bmad-help.csv", "module,skill\ncore,bmad-help\n")
        (self.project / "_bmad/core").mkdir()
        self.assertTrue(self.ready("bmad")["ready"])
        self.write(".agents/skills/bmad-help/SKILL.md")
        self.assertFalse(self.ready("bmad", ("universal",))["ready"])
        self.write("_bmad/_config/bmad-help.csv", "module,skill\ncore,other\n")
        self.assertFalse(self.ready("bmad")["ready"])

    def test_bare_integration_markers_do_not_invent_pins(self):
        record = "superpowers:\n  installation: skip\n  ref: existing-record\n  custom: keep\nintegrations:\n  understand_anything:\n    installation: skip\n    ref: existing-ua\n"
        self.config_file(record)
        self.write(".claude/skills/using-superpowers/SKILL.md")
        self.write(".agents/skills/understand/SKILL.md")
        self.save("superpowers")
        self.assertIn(record, self.config.read_text())
        self.assertIn("  workflow_pack: superpowers\n", self.config.read_text())
        self.assertNotIn("installation: install", self.config.read_text())

    def test_verified_ua_requires_pin_patch_and_all_links(self):
        self.baseline()
        self.config_file("integrations:\n  custom: keep\n  understand_anything:\n    installation: skip\n    custom: keep-ua\n")
        runtime = self.project / ".agent/runtime/understand-anything/repo"
        upstream = runtime / "understand-anything-plugin/skills"
        for name in ("understand", "understand-chat"):
            self.write(str((upstream / name / "SKILL.md").relative_to(self.project)))
        hardened = self.write(str((runtime / 'compatibility.txt').relative_to(self.project)), 'unpatched\n')
        run("git", "-C", str(runtime), "init", "-q", "--initial-branch=main")
        run("git", "-C", str(runtime), "add", ".")
        run("git", "-C", str(runtime), "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture")
        ref = run("git", "-C", str(runtime), "rev-parse", "HEAD").stdout.strip()
        integration = source / "integrations/understand-anything/integration.yml"
        original = integration.read_text()
        self.addCleanup(integration.write_text, original)
        patch = integration.parent / 'patches/offline-fixture.patch'
        patch.parent.mkdir(parents=True)
        patch.write_text('diff --git a/compatibility.txt b/compatibility.txt\n'
                         '--- a/compatibility.txt\n+++ b/compatibility.txt\n'
                         '@@ -1 +1 @@\n-unpatched\n+hardened\n')
        integration.write_text(re.sub(r"  ref: [0-9a-f]{40}", f"  ref: {ref}", original).replace(
            'patches/project-scope-and-git-hardening.patch', 'patches/offline-fixture.patch'))
        links = self.project / '.agents/skills'
        links.mkdir(parents=True)
        for name in ('understand', 'understand-chat'):
            (links / name).symlink_to(os.path.relpath(upstream / name, links))
        # The exact pin and complete links are insufficient without the patch.
        self.save()
        self.assertNotIn('installation: install', self.config.read_text())
        report = self.ready(agents=('codex',))
        self.assertFalse(report['ready'])
        self.assertTrue(any('compatibility patch' in issue for issue in report['issues']))
        run('git', '-C', str(runtime), 'apply', '--unidiff-zero', str(patch))
        (links / 'understand-chat').unlink()
        self.save()
        self.assertNotIn('installation: install', self.config.read_text())
        self.assertFalse(self.ready(agents=('codex',))['ready'])
        (links / 'understand-chat').symlink_to(os.path.relpath(upstream / 'understand-chat', links))
        self.save()
        value = self.config.read_text()
        self.assertIn('    installation: install\n', value)
        self.assertIn(f'    ref: {ref}\n', value)
        self.assertIn('    custom: keep-ua\n', value)
        self.assertIn('  custom: keep\n', value)
        client_links = self.project / '.claude/skills'
        client_links.mkdir(parents=True)
        for name in ('understand', 'understand-chat'):
            (client_links / name).symlink_to(os.path.relpath(upstream / name, client_links))
        self.write('.gitignore', '.agent/runtime/\n.agents/skills/understand*\n.claude/skills/understand*\n')
        report = self.ready(agents=('codex', 'claude-code'))
        self.assertTrue(report['ready'], report)
        self.assertTrue(all(client['ready'] for client in report['clients']))
        # Invalid observed runtime never erases old metadata or user modifications.
        hardened.write_text('tampered\n')
        self.assertFalse(self.ready(agents=('codex',))['ready'])
        self.save()
        self.assertEqual(self.config.read_text(), value)
        self.assertEqual(hardened.read_text(), 'tampered\n')
        hardened.write_text('hardened\n')
        pinned_manifest = integration.read_text()
        integration.write_text(pinned_manifest.replace(f'  ref: {ref}', '  ref: ' + '0' * 40))
        self.assertFalse(self.ready(agents=('codex',))['ready'])
        self.save()
        self.assertEqual(self.config.read_text(), value)
        integration.write_text(pinned_manifest)
        self.assertTrue(self.ready(agents=('codex',))['ready'])
        patch.unlink()
        self.assertFalse(self.ready(agents=('codex',))['ready'])
        self.save()
        self.assertEqual(self.config.read_text(), value)
        integration.write_text(original)
        self.config_file('integrations:\n  understand_anything:\n    installation: skip\n')
        self.save()
        self.assertNotIn('installation: install', self.config.read_text())
        self.assertFalse(self.ready(agents=('codex',))['ready'])
        self.assertEqual(run('git', '-C', str(runtime), 'remote').stdout, '')
        self.assertEqual(run('git', '-C', str(self.project), 'remote').stdout, '')
        self.assertFalse(list(source.rglob('__pycache__')))


unittest.main(argv=[sys.argv[0]], verbosity=2)
PY
