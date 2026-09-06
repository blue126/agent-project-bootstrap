#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 -B - "${repo_root}" <<'PY'
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

root = Path(sys.argv.pop())
repo = 'blue126/agent-project-bootstrap'
script = root / 'scripts/configure-github.sh'
template = json.loads((root / 'github/rulesets/self-ci-gates.json').read_text())
baseline_template = json.loads((root / 'github/rulesets/protect-main.json').read_text())

MOCK = r'''#!/usr/bin/env python3
import copy
import json
import os
from pathlib import Path
import sys

state_file = Path(os.environ['MOCK_STATE'])
state = json.loads(state_file.read_text())
args = sys.argv[1:]
if args == ['auth', 'status']:
    raise SystemExit(0)
assert args.pop(0) == 'api', args
method, endpoint, query, payload = 'GET', None, None, None
while args:
    arg = args.pop(0)
    if arg == '-H':
        args.pop(0)
    elif arg == '--method':
        method = args.pop(0)
    elif arg == '--input':
        payload = json.loads(Path(args.pop(0)).read_text())
    elif arg == '--jq':
        query = args.pop(0)
    elif arg == '--paginate':
        pass
    else:
        assert endpoint is None, arg
        endpoint = arg
with Path(os.environ['MOCK_LOG']).open('a') as log:
    log.write(json.dumps({'method': method, 'endpoint': endpoint, 'payload': payload}) + '\n')
if method == state.get('fail_method') or (state.get('fail_self_listing') and query and 'Self CI gates' in query):
    print('Simulated API failure', file=sys.stderr)
    raise SystemExit(1)
base = 'repos/blue126/agent-project-bootstrap'
assert endpoint.startswith(base), endpoint
path = endpoint[len(base):]
if path == '':
    if method == 'PATCH':
        assert payload.keys() == {'allow_auto_merge'}, payload
        state['repository'].update(payload)
        state['patched'] = True
    else:
        assert method == 'GET'
    data = copy.deepcopy(state['repository'])
    if state.get('setting_readback_bad') and state.get('patched'):
        data['allow_auto_merge'] = not data['allow_auto_merge']
    if query:
        assert query in ('.allow_auto_merge', '.default_branch'), query
        data = data[query[1:]]
elif path == '/git/ref/heads/main':
    if state.get('missing_branch'):
        raise SystemExit(1)
    data = {'ref': 'refs/heads/main'}
elif path == '/rulesets':
    if method == 'POST':
        assert payload['name'] == 'Self CI gates', payload
        state['gate'] = dict(payload, id=77, source_type='Repository')
        data = state['gate']
    else:
        assert method == 'GET'
        data = [value for value in (state['baseline'], state['gate']) if value is not None]
        if state.get('duplicate') and state['gate']:
            data.append(dict(state['gate'], id=78))
        if query:
            name = 'Self CI gates' if 'Self CI gates' in query else 'Protect main'
            print('\n'.join(str(item['id']) for item in data if item['name'] == name))
            raise SystemExit(0)
elif path in ('/rulesets/42', '/rulesets/77'):
    key = 'baseline' if path.endswith('/42') else 'gate'
    if method == 'PUT':
        state[key] = dict(payload, id=42 if key == 'baseline' else 77, source_type='Repository')
    else:
        assert method == 'GET'
    data = copy.deepcopy(state[key])
    if key == 'gate' and state.get('gate_readback_bad'):
        data['enforcement'] = 'disabled'
    if key == 'baseline' and state.get('baseline_changes_after_gate') and state['gate']:
        data['enforcement'] = 'disabled'
elif path == '/rules/branches/main':
    assert method == 'GET'
    data = [dict(rule, ruleset_id=42) for rule in state['baseline']['rules']]
    if state['gate'] and not state.get('ineffective'):
        data.extend(dict(rule, ruleset_id=77) for rule in state['gate']['rules'])
else:
    raise AssertionError(f'Unexpected API call: {method} {endpoint}')
state_file.write_text(json.dumps(state))
print(json.dumps(data) if not isinstance(data, str) else data)
'''


class SelfCiTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.state_file = self.directory / 'state.json'
        self.log = self.directory / 'calls.jsonl'
        mock = self.directory / 'bin/gh'
        mock.parent.mkdir()
        mock.write_text(MOCK)
        mock.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{mock.parent}{os.pathsep}{os.environ["PATH"]}',
                        MOCK_STATE=str(self.state_file), MOCK_LOG=str(self.log), TMPDIR=str(self.directory))
        self.state = {
            'repository': {'full_name': repo, 'default_branch': 'main', 'allow_auto_merge': False},
            'baseline': dict(copy.deepcopy(baseline_template), id=42, source_type='Repository'),
            'gate': None,
        }
        # Extra server-side/stricter PR parameters must not be lost by self.
        parameters = next(rule['parameters'] for rule in self.state['baseline']['rules'] if rule['type'] == 'pull_request')
        parameters.update(required_reviewers=[], require_extra_approval_for_unattributed_changes=True,
                          required_approving_review_count=2, require_last_push_approval=True)

    def save(self):
        self.state_file.write_text(json.dumps(self.state))

    def invoke(self, *arguments, expected=0, save=True):
        if save:
            self.save()
        result = subprocess.run(['bash', str(script), '--repo', repo, '--profile', 'self', *arguments],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        self.state = json.loads(self.state_file.read_text())
        return result

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def writes(self):
        return [call for call in self.calls() if call['method'] != 'GET']

    def existing_gate(self):
        self.state['gate'] = dict(copy.deepcopy(template), id=77, source_type='Repository')

    def test_create_verify_enable_order_and_idempotency(self):
        before = copy.deepcopy(self.state['baseline'])
        self.invoke('--native-auto-merge', 'enable')
        self.assertEqual(self.state['baseline'], before)
        self.assertTrue(self.state['repository']['allow_auto_merge'])
        self.assertEqual([call['method'] for call in self.writes()], ['POST', 'PATCH'])
        calls = self.calls()
        post = next(i for i, call in enumerate(calls) if call['method'] == 'POST')
        patch = next(i for i, call in enumerate(calls) if call['method'] == 'PATCH')
        between = calls[post + 1:patch]
        self.assertTrue(any(call['endpoint'].endswith('/rulesets/77') for call in between))
        self.assertTrue(any(call['endpoint'].endswith('/rules/branches/main') for call in between))
        self.assertTrue(any(call['endpoint'].endswith('/rulesets/42') for call in between))
        self.log.unlink()
        self.invoke('--native-auto-merge', 'enable')
        self.assertEqual(self.writes(), [])

    def test_noop_gate_still_enables_capability(self):
        self.existing_gate()
        self.invoke('--native-auto-merge', 'enable')
        self.assertEqual([call['method'] for call in self.writes()], ['PATCH'])

    def test_additive_update_preserves_extra_checks_and_rules(self):
        self.existing_gate()
        gate = self.state['gate']
        gate['rules'][0]['parameters']['required_status_checks'] = [{'context': 'other-check', 'integration_id': 123}]
        gate['rules'][0]['parameters']['strict_required_status_checks_policy'] = False
        gate['rules'].append({'type': 'required_linear_history'})
        self.invoke('--native-auto-merge', 'enable')
        self.assertEqual([call['method'] for call in self.writes()], ['PUT', 'PATCH'])
        checks = next(rule['parameters'] for rule in self.state['gate']['rules'] if rule['type'] == 'required_status_checks')
        self.assertEqual(len(checks['required_status_checks']), 4)
        self.assertTrue(checks['strict_required_status_checks_policy'])
        self.assertIn({'type': 'required_linear_history'}, self.state['gate']['rules'])

    def test_order_only_differences_do_not_write(self):
        self.existing_gate()
        self.state['gate']['rules'][0]['parameters']['required_status_checks'].reverse()
        self.state['repository']['allow_auto_merge'] = True
        self.invoke('--native-auto-merge', 'enable')
        self.assertEqual(self.writes(), [])

    def test_dry_run_create_update_and_noop_never_write(self):
        for mode in ('create', 'update', 'noop'):
            with self.subTest(mode=mode):
                if mode != 'create':
                    self.existing_gate()
                if mode == 'update':
                    self.state['gate']['enforcement'] = 'disabled'
                before = copy.deepcopy(self.state)
                self.invoke('--native-auto-merge', 'enable', '--dry-run')
                self.assertEqual(self.state, before)
                self.assertEqual(self.writes(), [])

    def test_baseline_flags_and_dry_run_compatibility(self):
        self.existing_gate()
        gate = copy.deepcopy(self.state['gate'])
        self.save()
        self.state['baseline'] = None
        self.save()
        result = subprocess.run(['bash', str(script), '--repo', repo, '--dry-run'],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.writes(), [])
        self.assertEqual(json.loads(self.state_file.read_text())['gate'], gate)

    def test_baseline_rerun_cannot_remove_separate_self_gate(self):
        self.existing_gate()
        gate = copy.deepcopy(self.state['gate'])
        self.save()
        result = subprocess.run(['bash', str(script), '--repo', repo], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        after = json.loads(self.state_file.read_text())
        self.assertEqual(after['gate'], gate)
        self.assertTrue(all(call['endpoint'].endswith('/rulesets/42') for call in self.writes()))

    def test_wrong_target_identity_branch_or_flags_never_write(self):
        for arguments in (['--repo', 'acme/project'], ['--profile', 'baseline', '--native-auto-merge', 'enable'],
                          ['--enforcement', 'evaluate'], ['--native-auto-merge', 'invalid']):
            with self.subTest(arguments=arguments):
                self.invoke(*arguments, expected=2)
                self.assertEqual(self.writes(), [])
        for key, value in (('full_name', 'acme/project'), ('default_branch', 'trunk')):
            with self.subTest(key=key):
                self.state['repository'][key] = value
                self.invoke('--native-auto-merge', 'enable', expected=1)
                self.assertEqual(self.writes(), [])
                self.state['repository'][key] = repo if key == 'full_name' else 'main'
        self.state['missing_branch'] = True
        self.invoke('--native-auto-merge', 'enable', expected=1)
        self.assertEqual(self.writes(), [])

    def test_missing_or_unsafe_baseline_fails_closed(self):
        original = copy.deepcopy(self.state['baseline'])
        for change in ('missing', 'no-bypass-information', 'bypass', 'inactive', 'no-pr'):
            with self.subTest(change=change):
                baseline = copy.deepcopy(original)
                if change == 'missing':
                    baseline = None
                elif change == 'no-bypass-information':
                    del baseline['bypass_actors']
                elif change == 'bypass':
                    baseline['bypass_actors'] = [{'actor_id': 1, 'actor_type': 'Team', 'bypass_mode': 'always'}]
                elif change == 'inactive':
                    baseline['enforcement'] = 'disabled'
                else:
                    baseline['rules'] = [rule for rule in baseline['rules'] if rule['type'] != 'pull_request']
                self.state['baseline'] = baseline
                self.invoke('--native-auto-merge', 'enable', expected=1)
                self.assertEqual(self.writes(), [])

    def test_unsafe_self_gate_scope_bypass_and_duplicate_names(self):
        for change in ('missing-bypass', 'null-bypass', 'bypass', 'scope', 'duplicate-rule', 'duplicate-name'):
            with self.subTest(change=change):
                self.existing_gate()
                self.state.pop('duplicate', None)
                gate = self.state['gate']
                if change == 'missing-bypass':
                    del gate['bypass_actors']
                elif change == 'null-bypass':
                    gate['bypass_actors'] = None
                elif change == 'bypass':
                    gate['bypass_actors'] = [{'actor_id': 1}]
                elif change == 'scope':
                    gate['conditions']['ref_name']['include'] = ['~ALL']
                elif change == 'duplicate-rule':
                    gate['rules'].append(copy.deepcopy(gate['rules'][0]))
                else:
                    self.state['duplicate'] = True
                self.invoke('--native-auto-merge', 'enable', expected=1)
                self.assertEqual(self.writes(), [])

    def test_conflicting_check_producer_is_not_overwritten(self):
        for app_id in (None, 999):
            with self.subTest(app_id=app_id):
                self.existing_gate()
                self.state['gate']['rules'][0]['parameters']['required_status_checks'][0]['integration_id'] = app_id
                # jq reports policy conflicts as nonzero; no API writes may occur.
                self.save()
                result = subprocess.run(['bash', str(script), '--repo', repo, '--profile', 'self',
                                         '--native-auto-merge', 'enable'], env=self.env, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Conflicting', result.stderr)
                self.assertEqual(self.writes(), [])

    def test_failed_ruleset_listing_is_not_treated_as_absence(self):
        self.state['fail_self_listing'] = True
        self.invoke('--native-auto-merge', 'enable', expected=1)
        self.assertEqual(self.writes(), [])

    def test_failed_update_does_not_enable(self):
        self.existing_gate()
        self.state['gate']['enforcement'] = 'disabled'
        self.state['fail_method'] = 'PUT'
        self.invoke('--native-auto-merge', 'enable', expected=1)
        self.assertEqual([call['method'] for call in self.writes()], ['PUT'])
        self.assertFalse(self.state['repository']['allow_auto_merge'])

    def test_failed_ruleset_writes_or_readbacks_never_enable(self):
        for flag in ('fail_method', 'gate_readback_bad', 'ineffective', 'baseline_changes_after_gate'):
            with self.subTest(flag=flag):
                self.state['gate'] = None
                for old in ('fail_method', 'gate_readback_bad', 'ineffective', 'baseline_changes_after_gate'):
                    self.state.pop(old, None)
                self.state[flag] = 'POST' if flag == 'fail_method' else True
                if self.log.exists():
                    self.log.unlink()
                self.invoke('--native-auto-merge', 'enable', expected=1)
                self.assertFalse(any(call['method'] == 'PATCH' for call in self.calls()))
                self.assertFalse(self.state['repository']['allow_auto_merge'])

    def test_failed_settings_patch_or_readback_is_reported(self):
        for flag in ('fail_method', 'setting_readback_bad'):
            with self.subTest(flag=flag):
                self.existing_gate()
                self.state['repository']['allow_auto_merge'] = False
                self.state.pop('fail_method', None)
                self.state.pop('patched', None)
                self.state[flag] = 'PATCH' if flag == 'fail_method' else True
                self.invoke('--native-auto-merge', 'enable', expected=1)

    def test_disable_only_recovers_even_without_healthy_gates(self):
        self.state['baseline'] = None
        self.state['repository']['allow_auto_merge'] = True
        self.invoke('--native-auto-merge', 'disable')
        self.assertFalse(self.state['repository']['allow_auto_merge'])
        self.assertTrue(all(call['endpoint'] == f'repos/{repo}' for call in self.calls()))
        self.assertEqual([call['method'] for call in self.writes()], ['PATCH'])
        self.log.unlink()
        self.invoke('--native-auto-merge', 'disable')
        self.assertEqual(self.writes(), [])
        self.state['repository']['allow_auto_merge'] = True
        self.invoke('--native-auto-merge', 'disable', '--dry-run')
        self.assertTrue(self.state['repository']['allow_auto_merge'])
        self.assertEqual(self.writes(), [])

    def test_profile_matches_ci_producers_and_generic_template_stays_neutral(self):
        parameters = template['rules'][0]['parameters']
        self.assertTrue(parameters['strict_required_status_checks_policy'])
        self.assertFalse(parameters['do_not_enforce_on_create'])
        checks = parameters['required_status_checks']
        self.assertEqual({item['integration_id'] for item in checks}, {15368})
        self.assertEqual({item['context'] for item in checks}, {
            'shellcheck', 'bootstrap-validation (ubuntu-latest)', 'bootstrap-validation (macos-latest)'})
        workflow = (root / '.github/workflows/ci.yml').read_text()
        for name in ('name: shellcheck', 'name: bootstrap-validation (${{ matrix.os }})',
                     '- ubuntu-latest', '- macos-latest'):
            self.assertIn(name, workflow)
        self.assertFalse(any(rule['type'] == 'required_status_checks' for rule in baseline_template['rules']))
        state = (root / '.agent/bootstrap.yml').read_text()
        self.assertIn('auto_merge: disabled', state)


unittest.main(verbosity=2)
PY
