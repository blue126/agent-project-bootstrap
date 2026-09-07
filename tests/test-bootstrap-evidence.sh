#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 -B - "${repo_root}" "$@" <<'PY'
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

root = Path(sys.argv.pop(1))
script = root / 'scripts/check-bootstrap-evidence.sh'
repository = 'acme/project'

MOCK = r'''#!/usr/bin/env python3
import copy, json, os, sys
from pathlib import Path
args = sys.argv[1:]
if args == ['auth', 'status']:
    raise SystemExit(0)
if args[:2] == ['repo', 'view']:
    assert args[2] == 'acme/project'
    print('acme/project')
    raise SystemExit(0)
assert args.pop(0) == 'api'
method, endpoint, payload, query, slurp = 'GET', None, None, None, False
while args:
    arg = args.pop(0)
    if arg == '-H': args.pop(0)
    elif arg == '--hostname': assert args.pop(0) == 'github.com'
    elif arg == '--method': method = args.pop(0)
    elif arg == '--input': payload = json.loads(Path(args.pop(0)).read_text())
    elif arg == '--jq': query = args.pop(0)
    elif arg == '--slurp': slurp = True
    elif arg == '--paginate': pass
    else:
        assert endpoint is None, arg
        endpoint = arg
state_file = Path(os.environ['MOCK_STATE'])
state = json.loads(state_file.read_text())
with Path(os.environ['MOCK_LOG']).open('a') as stream:
    stream.write(json.dumps(dict(method=method, endpoint=endpoint, payload=payload)) + '\n')
if state.get('fail_endpoint') == endpoint or state.get('fail_method') == method:
    raise SystemExit(1)
base = 'repos/acme/project'
assert endpoint.startswith(base), endpoint
path = endpoint[len(base):].split('?')[0]
if path == '':
    if method == 'PATCH':
        state['metadata'].update(payload)
    data = copy.deepcopy(state['metadata'])
    if query: data = data[query[1:]]
elif path == '/pulls/7':
    data = copy.deepcopy(state['pull'])
    if state.get('head_changes_after_write') and state['gate']:
        data['head']['sha'] = 'f' * 40
elif path == '/git/ref/heads/trunk': data = {'ref': 'refs/heads/trunk', 'object': {'sha': state['pull']['head']['sha']}}
elif path.startswith('/commits/') and path.endswith('/check-runs'): data = {'check_runs': state['checks']}
elif path == '/actions/runs/90': data = state['run']
elif path == '/actions/runs/90/jobs': data = {'jobs': state['jobs']}
elif path == '/pulls/7/reviews': data = state['reviews']
elif path == '/rulesets':
    if method == 'POST':
        assert payload['name'] == 'Project CI gates'
        state['gate'] = dict(payload, id=77, source_type='Repository')
        data = state['gate']
    else:
        data = [item for item in (state['baseline'], state['gate'], state['other']) if item]
        if state.get('duplicate_gate') and state['gate']: data.append(dict(state['gate'], id=78))
        if query:
            assert 'Project CI gates' in query
            print('\n'.join(str(item['id']) for item in data if item['name'] == 'Project CI gates'))
            raise SystemExit(0)
elif path in ('/rulesets/42', '/rulesets/77', '/rulesets/55'):
    key = {'42': 'baseline', '77': 'gate', '55': 'other'}[path.rsplit('/', 1)[1]]
    if method == 'PUT':
        assert key == 'gate'
        state[key] = dict(payload, id=77, source_type='Repository')
    data = copy.deepcopy(state[key])
    if key == 'gate' and state.get('bad_readback'): data['enforcement'] = 'disabled'
    if key == 'baseline' and state.get('baseline_changes_after_write') and state['gate']: data['enforcement'] = 'disabled'
elif path == '/rules/branches/trunk':
    data = []
    for key in ('baseline', 'gate', 'other'):
        source = state[key]
        if source and source['enforcement'] == 'active' and not (key == 'gate' and state.get('ineffective')):
            data.extend(dict(rule, ruleset_id=source['id']) for rule in source['rules'])
else: raise AssertionError((method, endpoint))
state_file.write_text(json.dumps(state))
print(json.dumps([data] if slurp else data))
'''


def fixture(directory):
    project = directory / 'project'
    project.mkdir()
    subprocess.run(['git', 'init', '-q', str(project)], check=True)
    (project / 'source.txt').write_text('source\n')
    (project / '.gitignore').write_text('.agent/runtime/\n')
    subprocess.run(['git', '-C', str(project), 'add', '.'], check=True)
    subprocess.run(['git', '-C', str(project), '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid',
                    'commit', '-qm', 'fixture', '--no-verify'], check=True)
    sha = subprocess.check_output(['git', '-C', str(project), 'rev-parse', 'HEAD'], text=True).strip()
    subprocess.run(['git', '-C', str(project), 'remote', 'add', 'origin', 'https://github.com/acme/project.git'], check=True)
    mock = directory / 'bin/gh'
    mock.parent.mkdir()
    mock.write_text(MOCK)
    mock.chmod(0o755)
    evidence = {'schema_version': 1, 'repository': repository, 'pr': 7, 'head_sha': sha,
                'checks': [{'context': 'project-tests', 'integration_id': 15368, 'workflow_id': 10}],
                'review': {'type': 'github_review', 'reviewer': 'reviewer'}}
    baseline = {'id': 42, 'name': 'Protect trunk', 'source_type': 'Repository', 'target': 'branch',
                'enforcement': 'active', 'bypass_actors': [],
                'conditions': {'ref_name': {'include': ['refs/heads/trunk'], 'exclude': []}},
                'rules': [{'type': 'pull_request', 'parameters': {'required_review_thread_resolution': True,
                           'required_approving_review_count': 2, 'require_last_push_approval': True}},
                          {'type': 'deletion'}, {'type': 'non_fast_forward'}]}
    state = {'metadata': {'full_name': repository, 'default_branch': 'trunk', 'allow_auto_merge': False},
             'pull': {'number': 7, 'state': 'open', 'head': {'sha': sha}, 'user': {'login': 'author'},
                      'base': {'ref': 'trunk', 'repo': {'full_name': repository}}},
             'checks': [{'id': 100, 'name': 'project-tests', 'head_sha': sha, 'app': {'id': 15368, 'slug': 'github-actions'},
                         'status': 'completed', 'conclusion': 'success',
                         'details_url': 'https://github.com/acme/project/actions/runs/90/job/80'}],
             'run': {'id': 90, 'workflow_id': 10, 'head_sha': sha, 'status': 'completed', 'conclusion': 'success',
                     'event': 'pull_request', 'pull_requests': [{'number': 7, 'head': {'sha': sha}}]},
             'jobs': [{'id': 80, 'head_sha': sha, 'status': 'completed', 'conclusion': 'success',
                       'check_run_url': 'https://api.github.com/repos/acme/project/check-runs/100'}],
             'reviews': [{'id': 12, 'user': {'login': 'reviewer'}, 'state': 'APPROVED', 'commit_id': sha}],
             'baseline': baseline, 'gate': None,
             'other': dict(copy.deepcopy(baseline), id=55, name='Other policy',
                           bypass_actors=[{'actor_id': 2, 'actor_type': 'Team', 'bypass_mode': 'pull_request'}])}
    (directory / 'state.json').write_text(json.dumps(state))
    (directory / 'evidence.json').write_text(json.dumps(evidence))
    (directory / 'command.json').write_text(json.dumps({'schema_version': 1, 'argv': [sys.executable, '-c', 'print("validated")']}))
    return project


# Reuse realistic isolated fixtures in the consumer integration suite.
if len(sys.argv) == 3 and sys.argv[1] == '--fixture':
    fixture(Path(sys.argv[2]))
    raise SystemExit(0)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.project = fixture(self.directory)
        self.state_file = self.directory / 'state.json'
        self.evidence_file = self.directory / 'evidence.json'
        self.state = json.loads(self.state_file.read_text())
        self.evidence = json.loads(self.evidence_file.read_text())
        self.log = self.directory / 'calls.jsonl'
        self.env = dict(os.environ, PATH=str(self.directory / 'bin') + os.pathsep + os.environ['PATH'],
                        MOCK_STATE=str(self.state_file), MOCK_LOG=str(self.log), TMPDIR=str(self.directory))

    def invoke(self, kind='ci', extra=(), expected=0, file=True):
        self.state_file.write_text(json.dumps(self.state))
        self.evidence_file.write_text(json.dumps(self.evidence))
        argv = ['bash', str(script), '--project', str(self.project), '--kind', kind]
        if kind != 'local': argv += ['--repo', repository]
        if file: argv += ['--evidence', str(self.evidence_file)]
        result = subprocess.run(argv + list(extra), env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data['status'], 'verified' if expected == 0 else 'blocked')
        if self.log.exists():
            self.assertTrue(all(json.loads(line)['method'] == 'GET' for line in self.log.read_text().splitlines()))
        return data

    def test_live_ci_returns_producer_bound_normalized_checks(self):
        result = self.invoke()['evidence']
        self.assertEqual(result['coverage'], 'configured_checks')
        self.assertEqual(result['base_branch'], 'trunk')
        self.assertEqual(result['checks'][0]['check_run_id'], 100)
        self.assertEqual(result['checks'][0]['workflow_run_id'], 90)
        self.evidence = result
        self.invoke()

    def test_discovery_verifies_current_pr_without_manual_check_configuration(self):
        result = self.invoke(file=False, extra=['--discover', '--pr', '7'])
        self.assertEqual(result['evidence']['checks'][0]['workflow_id'], 10)
        self.state['checks'][0]['conclusion'] = 'failure'
        self.invoke(file=False, extra=['--discover', '--pr', '7'], expected=1)

    def test_default_branch_ci_does_not_need_a_demonstration_pr(self):
        self.state['run']['event'] = 'push'
        self.state['run']['head_branch'] = 'trunk'
        self.state['run']['pull_requests'] = []
        result = self.invoke(file=False, extra=['--discover'])
        self.assertIsNone(result['evidence']['pr'])
        self.evidence = result['evidence']
        self.invoke()
        self.state['run']['head_branch'] = 'unrelated'
        self.invoke(expected=1)

    def test_review_feedback_is_integration_evidence_not_merge_approval(self):
        self.state['reviews'][0]['user']['type'] = 'Bot'
        self.state['reviews'][0]['state'] = 'CHANGES_REQUESTED'
        result = self.invoke('review', file=False, extra=['--discover', '--pr', '7'])
        self.assertEqual(result['evidence']['coverage'], 'review_integration_only')
        self.assertEqual(result['evidence']['review']['state'], 'CHANGES_REQUESTED')

    def test_unsuccessful_wrong_head_and_wrong_producer_checks_fail(self):
        original = copy.deepcopy(self.state['checks'])
        for field, value in [('head_sha', 'b' * 40), ('status', 'in_progress'), ('conclusion', 'skipped'),
                             ('conclusion', 'cancelled'), ('conclusion', 'failure'), ('conclusion', 'neutral'),
                             ('app', {'id': 99, 'slug': 'other'})]:
            with self.subTest(field=field, value=value):
                self.state['checks'] = copy.deepcopy(original)
                self.state['checks'][0][field] = value
                self.invoke(expected=1)
        for checks in ([], original + original):
            self.state['checks'] = checks
            self.invoke(expected=1)

    def test_workflow_and_job_corroboration_required(self):
        original = copy.deepcopy(self.state)
        for section, key, value in [('run', 'head_sha', 'b' * 40), ('run', 'workflow_id', 11),
                                    ('run', 'event', 'push'), ('run', 'pull_requests', []),
                                    ('run', 'conclusion', 'failure'), ('run', 'status', 'in_progress')]:
            self.state = copy.deepcopy(original)
            self.state[section][key] = value
            self.invoke(expected=1)
        self.state = copy.deepcopy(original)
        self.state['jobs'][0]['check_run_url'] = 'https://api.github.com/repos/other/project/check-runs/100'
        self.invoke(expected=1)

    def test_target_origin_pr_and_configuration_are_not_inferred(self):
        self.invoke(extra=['--repo', 'other/project'], expected=1)
        self.invoke(extra=['--pr', '8'], expected=1)
        original = copy.deepcopy(self.evidence)
        for key, value, expected in [('head_sha', 'e' * 40, 1), ('checks', [], 2), ('checks', [{'context': 'tests'}], 2)]:
            self.evidence = dict(original, **{key: value})
            self.invoke(expected=expected)
        self.evidence = original
        subprocess.run(['git', '-C', str(self.project), 'remote', 'remove', 'origin'], check=True)
        self.invoke(expected=1)
        self.assertNotIn('origin', subprocess.check_output(['git', '-C', str(self.project), 'remote'], text=True))

    def test_failed_remote_read_blocks(self):
        self.state['fail_endpoint'] = 'repos/acme/project/actions/runs/90'
        self.invoke(expected=1)

    def test_review_requires_current_approval_or_configured_check(self):
        self.invoke('review')
        original = copy.deepcopy(self.state['reviews'])
        for field, value in [('state', 'COMMENTED'), ('state', 'DISMISSED'), ('commit_id', 'b' * 40)]:
            self.state['reviews'] = copy.deepcopy(original)
            self.state['reviews'][0][field] = value
            self.invoke('review', expected=1)
        self.state['reviews'] = original + [dict(original[0], id=13, state='CHANGES_REQUESTED')]
        self.invoke('review', expected=1)
        self.evidence['review'] = {'type': 'check', 'check': {'context': 'project-tests', 'integration_id': 15368}}
        self.invoke('review')
        self.evidence['review']['check']['integration_id'] = 999
        self.invoke('review', expected=1)

    def test_missing_protection_is_not_verified(self):
        result = self.invoke('protection', expected=1)
        self.assertTrue(result['evidence']['baseline_verified'])
        self.assertEqual(result['reason'], 'required_checks_not_effective')
        self.state['baseline']['bypass_actors'] = [{'actor_id': 1}]
        self.invoke('protection', expected=1)

    def test_local_requires_explicit_authorization_and_signed_receipt(self):
        marker = self.directory / 'marker'
        self.evidence = {'schema_version': 1, 'local': {'status': 'done', 'argv': ['touch', str(marker)]}}
        self.invoke('local', expected=1)
        self.assertFalse(marker.exists())
        result = self.invoke('local', ['--run-local', '--command-file', str(self.directory / 'command.json')], file=False)
        self.evidence = copy.deepcopy(result['evidence'])
        self.invoke('local')
        self.evidence['local']['exit_code'] = 2
        self.invoke('local', expected=1)
        self.evidence = copy.deepcopy(result['evidence'])
        (self.project / 'source.txt').write_text('changed')
        self.invoke('local', expected=1)

    def test_local_config_changes_failures_and_mutating_commands_block(self):
        config_path = self.directory / 'command.json'
        result = self.invoke('local', ['--run-local', '--command-file', str(config_path)], file=False)
        self.evidence = result['evidence']
        config_path.write_text(json.dumps({'schema_version': 1, 'argv': ['false']}))
        self.invoke('local', expected=1)
        self.invoke('local', ['--run-local', '--command-file', str(config_path)], file=False, expected=1)
        config_path.write_text(json.dumps({'schema_version': 1, 'argv': [sys.executable, '-c', 'open("source.txt", "w").write("changed")']}))
        self.invoke('local', ['--run-local', '--command-file', str(config_path)], file=False, expected=1)

    def test_saved_result_envelopes_are_reverified(self):
        result = self.invoke()
        self.evidence = result
        self.invoke()
        self.state['checks'][0]['conclusion'] = 'failure'
        self.invoke(expected=1)
        local = self.invoke('local', ['--run-local', '--command-file', str(self.directory / 'command.json')], file=False)
        self.evidence = local
        self.invoke('local')

    def test_dirty_target_and_tampered_local_target_block(self):
        (self.project / 'source.txt').write_text('not yet in PR')
        self.invoke(expected=1)
        local = self.invoke('local', ['--run-local', '--command-file', str(self.directory / 'command.json')], file=False)
        self.evidence = local['evidence']
        (self.project / 'new-file.txt').write_text('not validated')
        result = self.invoke('local', expected=1)
        self.assertIn('stale', result['reason'])

    def test_non_git_local_validation_requires_explicit_runtime_key_directory(self):
        project = self.directory / 'non-git'
        project.mkdir()
        (project / 'source.txt').write_text('source')
        command = self.directory / 'non-git-command.json'
        command.write_text(json.dumps({'schema_version': 1, 'argv': [sys.executable, '-c', 'pass']}))
        argv = ['bash', str(script), '--project', str(project), '--kind', 'local', '--run-local', '--command-file', str(command)]
        result = subprocess.run(argv, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        key_dir = project / '.agent/runtime/onboarding'
        result = subprocess.run(argv + ['--key-dir', str(key_dir)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        receipt = json.loads(result.stdout)
        evidence = self.directory / 'non-git-evidence.json'
        evidence.write_text(json.dumps(receipt))
        result = subprocess.run(['bash', str(script), '--project', str(project), '--kind', 'local',
                                 '--evidence', str(evidence), '--key-dir', str(key_dir)], env=self.env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        outside = self.directory / 'outside-key'
        result = subprocess.run(argv + ['--key-dir', str(outside)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)

    def test_schema_is_json_and_internal_references_resolve(self):
        schema = json.loads((root / 'schemas/onboarding-evidence.schema.json').read_text())
        def visit(value):
            if isinstance(value, dict):
                if '$ref' in value:
                    self.assertTrue(value['$ref'].startswith('#/'))
                    target = schema
                    for segment in value['$ref'][2:].split('/'):
                        target = target[segment]
                for child in value.values(): visit(child)
            elif isinstance(value, list):
                for child in value: visit(child)
        visit(schema)
        self.assertEqual(schema['$defs']['result']['properties']['status']['enum'], ['verified', 'blocked'])
        self.assertIn('signature', schema['$defs']['local']['required'])
        self.assertEqual(schema['$defs']['ci_check']['allOf'][1]['properties']['integration_id']['const'], 15368)

    def test_invalid_arguments_are_json(self):
        self.invoke('local', ['--run-local'], file=False, expected=2)
        self.invoke(extra=['--run-local'], expected=2)


unittest.main(verbosity=2)
PY
