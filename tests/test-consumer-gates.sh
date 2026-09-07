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
script = root / 'scripts/configure-github.sh'


class ConsumerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR'))
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        subprocess.run(['bash', str(root / 'tests/test-bootstrap-evidence.sh'), '--fixture', str(self.directory)], check=True)
        self.project = self.directory / 'project'
        self.state_file = self.directory / 'state.json'
        self.state = json.loads(self.state_file.read_text())
        self.log = self.directory / 'calls.jsonl'
        self.env = dict(os.environ, PATH=str(self.directory / 'bin') + os.pathsep + os.environ['PATH'],
                        MOCK_STATE=str(self.state_file), MOCK_LOG=str(self.log), TMPDIR=str(self.directory))

    def invoke(self, *extra, expected=0):
        self.state_file.write_text(json.dumps(self.state))
        result = subprocess.run(['bash', str(script), '--profile', 'consumer', '--repo', 'acme/project',
                                 '--project', str(self.project), '--evidence', str(self.directory / 'evidence.json'),
                                 *extra], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        self.state = json.loads(self.state_file.read_text())
        return result

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def writes(self):
        return [call for call in self.calls() if call['method'] != 'GET']

    def gate(self):
        return dict(copy.deepcopy(self.state['baseline']), id=77, name='Project CI gates', rules=[{
            'type': 'required_status_checks', 'parameters': {
                'strict_required_status_checks_policy': True, 'do_not_enforce_on_create': False,
                'required_status_checks': [{'context': 'project-tests', 'integration_id': 15368}]}}])

    def test_create_verify_enable_and_repeat_are_idempotent(self):
        before = copy.deepcopy(self.state)
        self.invoke('--native-auto-merge', 'enable')
        self.assertEqual([call['method'] for call in self.writes()], ['POST', 'PATCH'])
        self.assertEqual(self.state['baseline'], before['baseline'])
        self.assertEqual(self.state['other'], before['other'])
        self.assertTrue(self.state['metadata']['allow_auto_merge'])
        calls = self.calls()
        post = next(i for i, call in enumerate(calls) if call['method'] == 'POST')
        patch = next(i for i, call in enumerate(calls) if call['method'] == 'PATCH')
        between = calls[post + 1:patch]
        for endpoint in ('/rulesets/77', '/rules/branches/trunk?per_page=100', '/rulesets/42', '/actions/runs/90'):
            self.assertTrue(any(call['endpoint'].endswith(endpoint) for call in between), endpoint)
        self.log.unlink()
        self.invoke('--native-auto-merge', 'enable')
        self.assertEqual(self.writes(), [])

    def test_additive_update_preserves_extra_parameters_checks_rules_and_approvals(self):
        self.state['gate'] = self.gate()
        gate = self.state['gate']
        gate['rules'][0]['parameters']['required_status_checks'] = [{'context': 'security', 'integration_id': 88}]
        gate['rules'][0]['parameters']['extra_server_policy'] = True
        gate['rules'].append({'type': 'required_signatures'})
        gate['rules'].append({'type': 'pull_request', 'parameters': {'required_approving_review_count': 4}})
        other = copy.deepcopy(self.state['other'])
        baseline = copy.deepcopy(self.state['baseline'])
        self.invoke()
        self.assertEqual([call['method'] for call in self.writes()], ['PUT'])
        parameters = self.state['gate']['rules'][-1]['parameters']
        self.assertEqual(len(parameters['required_status_checks']), 2)
        self.assertTrue(parameters['extra_server_policy'])
        self.assertIn({'type': 'required_signatures'}, self.state['gate']['rules'])
        self.assertIn({'type': 'pull_request', 'parameters': {'required_approving_review_count': 4}}, self.state['gate']['rules'])
        self.assertEqual(self.state['other'], other)
        self.assertEqual(self.state['baseline'], baseline)

    def test_dry_run_all_paths_never_write(self):
        for mode in ('create', 'update', 'noop'):
            with self.subTest(mode=mode):
                self.state['gate'] = None if mode == 'create' else self.gate()
                if mode == 'update': self.state['gate']['rules'][0]['parameters']['strict_required_status_checks_policy'] = False
                before = copy.deepcopy(self.state)
                self.invoke('--dry-run', '--native-auto-merge', 'enable')
                self.assertEqual(self.writes(), [])
                self.assertEqual(self.state, before)

    def test_bad_ci_and_identity_are_zero_write_failures(self):
        original = copy.deepcopy(self.state)
        cases = [('checks', 'head_sha', 'f' * 40), ('checks', 'app', {'id': 2}),
                 ('checks', 'conclusion', 'failure'), ('run', 'workflow_id', 20), ('run', 'status', 'in_progress')]
        for section, key, value in cases:
            self.state = copy.deepcopy(original)
            target = self.state[section][0] if section == 'checks' else self.state[section]
            target[key] = value
            self.invoke('--native-auto-merge', 'enable', expected=1)
            self.assertEqual(self.writes(), [])
        self.state = copy.deepcopy(original)
        self.state['metadata']['full_name'] = 'other/project'
        self.invoke(expected=1)
        self.assertEqual(self.writes(), [])

    def test_missing_or_bypassed_base_policy_blocks_before_write(self):
        original = copy.deepcopy(self.state)
        for mode in ('missing', 'bypass', 'inactive', 'no-threads'):
            self.state = copy.deepcopy(original)
            if mode == 'missing': self.state['baseline'] = None
            elif mode == 'bypass': self.state['baseline']['bypass_actors'] = [{'actor_id': 1}]
            elif mode == 'inactive': self.state['baseline']['enforcement'] = 'disabled'
            else: self.state['baseline']['rules'][0]['parameters']['required_review_thread_resolution'] = False
            self.invoke(expected=1)
            self.assertEqual(self.writes(), [])

    def test_explicit_pr_policy_bootstraps_unprotected_consumer_without_replacing_rules(self):
        self.state['baseline'] = None
        other = copy.deepcopy(self.state['other'])
        self.invoke('--with-pr-policy', '--dry-run', '--native-auto-merge', 'enable')
        self.assertEqual(self.writes(), [])
        self.invoke('--with-pr-policy', '--native-auto-merge', 'enable')
        self.assertEqual(self.state['other'], other)
        self.assertIsNone(self.state['baseline'])
        policies = [r for r in self.state['gate']['rules'] if r['type'] == 'pull_request']
        self.assertEqual(len(policies), 1)
        self.assertTrue(policies[0]['parameters']['required_review_thread_resolution'])
        self.log.unlink()
        self.invoke('--with-pr-policy', '--native-auto-merge', 'enable')
        self.assertEqual(self.writes(), [])

    def test_conflicting_producer_in_owned_or_other_effective_rule_never_overwritten(self):
        for key in ('gate', 'other'):
            for producer in (None, 99):
                self.state['gate'] = None
                self.state[key] = self.gate()
                self.state[key]['id'] = 77 if key == 'gate' else 55
                self.state[key]['name'] = 'Project CI gates' if key == 'gate' else 'Other policy'
                self.state[key]['rules'][0]['parameters']['required_status_checks'][0]['integration_id'] = producer
                self.invoke(expected=1)
                self.assertEqual(self.writes(), [])

    def test_unsafe_owned_scope_bypass_and_duplicates_preserved(self):
        for mode in ('scope', 'bypass', 'duplicate-rule', 'duplicate-name'):
            self.state['gate'] = self.gate()
            self.state.pop('duplicate_gate', None)
            if mode == 'scope': self.state['gate']['conditions']['ref_name']['include'] = ['~ALL']
            elif mode == 'bypass': self.state['gate']['bypass_actors'] = [{'actor_id': 1}]
            elif mode == 'duplicate-rule': self.state['gate']['rules'] *= 2
            else: self.state['duplicate_gate'] = True
            before = copy.deepcopy(self.state['gate'])
            self.invoke(expected=1)
            self.assertEqual(self.writes(), [])
            self.assertEqual(self.state['gate'], before)

    def test_readback_effectiveness_and_changed_head_never_enable(self):
        original = copy.deepcopy(self.state)
        for flag in ('bad_readback', 'ineffective', 'baseline_changes_after_write', 'head_changes_after_write'):
            with self.subTest(flag=flag):
                self.state = copy.deepcopy(original)
                self.state[flag] = True
                if self.log.exists(): self.log.unlink()
                self.invoke('--native-auto-merge', 'enable', expected=1)
                self.assertFalse(any(call['method'] == 'PATCH' for call in self.calls()))
                self.assertFalse(self.state['metadata']['allow_auto_merge'])

    def test_failed_reads_and_write_never_enable(self):
        self.state['fail_endpoint'] = 'repos/acme/project/rulesets'
        self.invoke('--native-auto-merge', 'enable', expected=1)
        self.assertEqual(self.writes(), [])
        del self.state['fail_endpoint']
        self.state['fail_method'] = 'POST'
        self.invoke('--native-auto-merge', 'enable', expected=1)
        self.assertEqual([call['method'] for call in self.writes()], ['POST'])

    def test_disable_and_unchanged_do_not_enroll_prs(self):
        self.state['gate'] = self.gate()
        self.state['metadata']['allow_auto_merge'] = True
        self.invoke('--native-auto-merge', 'disable')
        self.assertFalse(self.state['metadata']['allow_auto_merge'])
        self.assertEqual([call['payload'] for call in self.writes()], [{'allow_auto_merge': False}])
        self.assertFalse(any('/merge' in call['endpoint'] for call in self.calls()))

    def test_self_scope_and_invalid_flags_not_relaxed(self):
        for extra in (('--repo', 'blue126/agent-project-bootstrap'), ('--enforcement', 'disabled'),
                      ('--profile', 'baseline'), ('--profile', 'self')):
            self.invoke(*extra, expected=2)
            self.assertEqual(self.writes(), [])


unittest.main(verbosity=2)
PY
