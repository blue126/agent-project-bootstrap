#!/usr/bin/env bash
# Keep this entry point dependency-free apart from Python, git, and (remote modes) gh.
set -euo pipefail
exec python3 -B - "$@" <<'PY'
import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
from urllib.parse import quote


class Blocked(Exception):
    pass


class Invalid(Exception):
    pass


def finish(status, reason, evidence=None, code=0):
    print(json.dumps({'status': status, 'reason': reason, 'evidence': evidence or {}}, sort_keys=True))
    raise SystemExit(code)


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise Invalid(message)


def run(argv, cwd=None):
    try:
        result = subprocess.run(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as error:
        raise Blocked(str(error)) from error
    if result.returncode:
        raise Blocked(f'{argv[0]} read failed: {result.stderr.decode(errors="replace").strip()}')
    return result.stdout


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()


def load(path):
    try:
        value = json.loads(Path(path).read_text())
    except (OSError, ValueError) as error:
        raise Invalid(f'Cannot read JSON evidence/configuration: {error}') from error
    if isinstance(value, dict) and value.get('status') in ('verified', 'blocked'):
        value = value.get('evidence')
    if not isinstance(value, dict) or type(value.get('schema_version')) is not int or value['schema_version'] != 1:
        raise Invalid('Expected an object with schema_version: 1 (or a checker result containing it)')
    return value


def positive(value):
    return type(value) is int and value > 0


def checks_config(values, actions=True):
    if not isinstance(values, list) or not values:
        raise Invalid('Explicit nonempty checks configuration is required; no stack is inferred')
    contexts = set()
    for item in values:
        if not isinstance(item, dict) or not isinstance(item.get('context'), str) or not item['context'].strip():
            raise Invalid('Each check needs a nonempty context')
        if set(item) - {'context', 'integration_id', 'workflow_id', 'head_sha', 'check_run_id', 'workflow_run_id'}:
            raise Invalid('Unknown check configuration fields')
        if item['context'] in contexts or not positive(item.get('integration_id')):
            raise Invalid('Duplicate context or missing positive integration_id')
        contexts.add(item['context'])
        if actions and (item['integration_id'] != 15368 or not positive(item.get('workflow_id'))):
            raise Invalid('CI checks require GitHub Actions integration_id 15368 and an explicit workflow_id')
    return values


def api(path, paginated=False):
    argv = ['gh', 'api', '--hostname', 'github.com', '-H', 'Accept: application/vnd.github+json',
            '-H', 'X-GitHub-Api-Version: 2022-11-28', path]
    if paginated:
        argv += ['--paginate', '--slurp']
    try:
        return json.loads(run(argv))
    except ValueError as error:
        raise Blocked('GitHub returned invalid JSON') from error


def pages(path, key=None):
    result = api(path, True)
    if not isinstance(result, list):
        raise Blocked('Expected paginated GitHub response')
    values = []
    for page in result:
        items = page.get(key) if key and isinstance(page, dict) else page
        if not isinstance(items, list):
            raise Blocked('Incomplete GitHub pagination response')
        values.extend(items)
    return values


def git(*args):
    return run(['git', '-C', str(project), *args])


def head():
    if not has_git:
        return None
    result = subprocess.run(['git', '-C', str(project), 'rev-parse', '--verify', 'HEAD'], capture_output=True)
    return result.stdout.decode().strip() if result.returncode == 0 else None


def digest():
    # Deliberately covers tracked and non-ignored untracked paths, including modes
    # and symlink targets, not ignored build products, journals, or .git metadata.
    if has_git:
        names = set(git('ls-files', '-z', '--cached', '--others', '--exclude-standard').split(b'\0')) - {b''}
    else:
        # Without Git, conservatively cover all files. Receipts stay outside the
        # target; a validator that mutates its inputs cannot yield a valid receipt.
        runtime = project / '.agent/runtime/onboarding'
        names = {os.fsencode(str(path.relative_to(project))) for path in project.rglob('*')
                 if (path.is_file() or path.is_symlink()) and not path.is_relative_to(runtime)}
    result = hashlib.sha256()
    for name in sorted(names):
        path = project / os.fsdecode(name)
        result.update(len(name).to_bytes(8, 'big') + name)
        if path.is_symlink():
            data, mode = os.fsencode(os.readlink(path)), b'link'
        elif path.is_file():
            data, mode = path.read_bytes(), str(path.stat().st_mode & 0o777).encode()
        elif not path.exists():
            data, mode = b'', b'missing'
        else:
            raise Blocked('Local receipts do not support submodules or tracked directories')
        result.update(mode + b'\0' + hashlib.sha256(data).digest())
    return result.hexdigest()


def command_config(path):
    config = load(path)
    argv = config.get('argv')
    if set(config) != {'schema_version', 'argv'} or not isinstance(argv, list) or not argv:
        raise Invalid('Command file must contain only schema_version: 1 and a nonempty argv array')
    if any(not isinstance(arg, str) or '\0' in arg for arg in argv) or not argv[0]:
        raise Invalid('Command argv must contain strings without NUL bytes')
    return config


def local_evidence():
    if has_git:
        if args.key_dir:
            raise Invalid('--key-dir is only for a project without Git')
        key_root = Path(git('rev-parse', '--absolute-git-dir').decode().strip())
    else:
        if not args.key_dir:
            raise Invalid('Non-Git local validation requires explicit --key-dir under .agent/runtime/onboarding')
        key_root = Path(args.key_dir).resolve()
        allowed = (project / '.agent/runtime/onboarding').resolve()
        if not key_root.is_absolute() or not key_root.is_relative_to(allowed):
            raise Invalid('--key-dir must be under the project runtime onboarding directory')
    key_file = key_root / 'bootstrap-evidence.key'
    if args.run_local:
        if not args.command_file or args.evidence:
            raise Invalid('--run-local requires --command-file; receipt is returned on stdout, not --evidence')
        command_path = Path(args.command_file).resolve(strict=True)
        config = command_config(command_path)
        before, sha = digest(), head()
        # Only this explicit invocation authorizes execution. Nothing read from
        # an evidence file reaches subprocess. Output stays on stderr.
        try:
            completed = subprocess.run(config['argv'], cwd=project, stdout=sys.stderr, stderr=sys.stderr)
        except OSError as error:
            raise Blocked(f'Authorized local validation could not run: {error}') from error
        if completed.returncode != 0:
            raise Blocked(f'Authorized local validation exited {completed.returncode}')
        if before != digest() or sha != head() or config != command_config(command_path):
            raise Blocked('Target or validation configuration changed during local validation')
        if key_root.is_symlink():
            raise Blocked('Local receipt state directory must not be a symlink')
        key_root.mkdir(parents=True, exist_ok=True, mode=0o700)
        if not key_file.exists():
            descriptor = os.open(key_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, 'wb') as stream:
                stream.write(secrets.token_bytes(32))
        if key_file.is_symlink() or key_file.stat().st_mode & 0o077:
            raise Blocked('Local receipt key must be private and not a symlink')
        receipt = {'project': str(project), 'head_sha': sha, 'target_digest': before,
                   'command_file': str(command_path), 'command_digest': hashlib.sha256(canonical(config)).hexdigest(),
                   'argv': config['argv'], 'exit_code': 0}
        receipt['signature'] = hmac.new(key_file.read_bytes(), canonical(receipt), hashlib.sha256).hexdigest()
        return {'schema_version': 1, 'local': receipt}
    if args.command_file:
        raise Invalid('--command-file is only valid with --run-local')
    receipt = evidence.get('local')
    if not isinstance(receipt, dict) or not isinstance(receipt.get('signature'), str):
        raise Blocked('Missing locally issued validation receipt; arbitrary done flags are not evidence')
    signed = {key: value for key, value in receipt.items() if key != 'signature'}
    if not key_file.is_file() or key_file.is_symlink() or key_file.stat().st_mode & 0o077:
        raise Blocked('Local receipt key is absent or unsafe')
    expected = hmac.new(key_file.read_bytes(), canonical(signed), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(receipt['signature'], expected):
        raise Blocked('Local receipt integrity check failed')
    if receipt.get('project') != str(project) or receipt.get('head_sha') != head() or receipt.get('target_digest') != digest():
        raise Blocked('Local receipt is stale or belongs to another target')
    config = command_config(receipt['command_file'])
    if receipt.get('exit_code') != 0 or receipt.get('argv') != config['argv'] or receipt.get('command_digest') != hashlib.sha256(canonical(config)).hexdigest():
        raise Blocked('Local validation configuration no longer matches the receipt')
    return evidence


def remote_identity():
    if not args.repo or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repo):
        raise Invalid('Remote evidence requires explicit --repo OWNER/REPO')
    origin = git('remote', 'get-url', 'origin').decode().strip()
    accepted = [f'https://github.com/{args.repo}', f'https://github.com/{args.repo}.git',
                f'git@github.com:{args.repo}', f'git@github.com:{args.repo}.git',
                f'ssh://git@github.com/{args.repo}', f'ssh://git@github.com/{args.repo}.git']
    if origin not in accepted:
        raise Blocked('origin does not match the explicitly selected GitHub repository')
    if git('status', '--porcelain', '--untracked-files=normal').strip():
        raise Blocked('Remote evidence requires a clean target; commit project changes before verifying PR HEAD')
    number = args.pr if args.pr is not None else evidence.get('pr')
    if number is not None and not positive(number):
        raise Invalid('PR number must be positive when supplied')
    if evidence.get('repository') != args.repo or evidence.get('pr') != number:
        raise Blocked('Evidence repository/PR does not match the explicit target')
    metadata = api(f'repos/{args.repo}')
    if metadata.get('full_name') != args.repo:
        raise Blocked('GitHub repository identity mismatch')
    branch = metadata.get('default_branch')
    if not isinstance(branch, str) or not branch:
        raise Blocked('Missing default branch')
    git('check-ref-format', '--branch', branch)
    reference = api(f'repos/{args.repo}/git/ref/heads/{quote(branch, safe="")}')
    if number is None:
        sha = reference.get('object', {}).get('sha')
        if not isinstance(sha, str) or not re.fullmatch(r'[0-9a-f]{40}', sha) or sha != head() or evidence.get('head_sha') != sha:
            raise Blocked('Default-branch evidence and local HEAD must match the current remote default branch')
        if args.kind == 'review':
            raise Blocked('Review verification needs a specific PR; a default-branch CI run is not a review')
        return None, branch, sha, {}
    pull = api(f'repos/{args.repo}/pulls/{number}')
    sha = pull.get('head', {}).get('sha')
    if pull.get('number') != number or pull.get('state') != 'open' or pull.get('base', {}).get('repo', {}).get('full_name') != args.repo:
        raise Blocked('PR is not an open PR of the selected repository')
    if pull.get('base', {}).get('ref') != branch:
        raise Blocked('Onboarding PR must target the verified default branch')
    if not isinstance(sha, str) or not re.fullmatch(r'[0-9a-f]{40}', sha) or sha != head() or evidence.get('head_sha') != sha:
        raise Blocked('Evidence, local HEAD, and current PR head must match exactly')
    return number, branch, sha, pull


def discover_configuration():
    configured = dict(evidence)
    if args.kind == 'ci':
        configured['checks'] = []
        for check in pages(f'repos/{args.repo}/commits/{sha}/check-runs?filter=latest&per_page=100', 'check_runs'):
            if check.get('app', {}).get('id') != 15368:
                continue
            if 'not a merge gate' in check.get('name', '').lower():
                continue
            match = re.fullmatch(r'https://github\.com/' + re.escape(args.repo) + r'/actions/runs/([1-9][0-9]*)/job/[1-9][0-9]*(?:\?[^#]*)?', check.get('details_url', ''))
            if not match:
                raise Blocked('Observed Actions check has no verifiable workflow link')
            workflow = api(f'repos/{args.repo}/actions/runs/{match[1]}')
            configured['checks'].append({'context': check['name'], 'integration_id': 15368, 'workflow_id': workflow.get('workflow_id')})
    elif args.kind == 'review':
        reviews = pages(f'repos/{args.repo}/pulls/{number}/reviews?per_page=100')
        candidates = [r for r in reviews if r.get('commit_id') == sha and r.get('user', {}).get('type') == 'Bot'
                      and r.get('state') in ('COMMENTED', 'APPROVED', 'CHANGES_REQUESTED')]
        if not candidates:
            raise Blocked('No automated review feedback on the current PR head; integration remains unverified')
        selected = max(candidates, key=lambda r: r['id'])
        configured['review'] = {'type': 'feedback', 'reviewer': selected['user']['login']}
    return configured


def verify_checks(wanted, actions=True):
    available = pages(f'repos/{args.repo}/commits/{sha}/check-runs?filter=latest&per_page=100', 'check_runs')
    verified = []
    for item in wanted:
        matching = [check for check in available if check.get('name') == item['context']]
        # Duplicate names from another workflow/producer cannot safely be made required.
        if len(matching) != 1:
            raise Blocked(f'Missing or ambiguous check context: {item["context"]}')
        check = matching[0]
        if check.get('head_sha') != sha or check.get('app', {}).get('id') != item['integration_id']:
            raise Blocked(f'Check SHA or producer mismatch: {item["context"]}')
        if check.get('status') != 'completed' or check.get('conclusion') != 'success' or not positive(check.get('id')):
            raise Blocked(f'Check is not completed successfully: {item["context"]}')
        proof = dict(item, head_sha=sha, check_run_id=check['id'])
        if actions:
            if check.get('app', {}).get('slug') != 'github-actions':
                raise Blocked('CI producer is not GitHub Actions')
            match = re.fullmatch(r'https://github\.com/' + re.escape(args.repo) + r'/actions/runs/([1-9][0-9]*)/job/([1-9][0-9]*)(?:\?[^#]*)?', check.get('details_url', ''))
            if not match:
                raise Blocked('Check lacks a repository-bound Actions run/job link')
            run_id, job_id = map(int, match.groups())
            workflow = api(f'repos/{args.repo}/actions/runs/{run_id}')
            if (workflow.get('id') != run_id or workflow.get('workflow_id') != item['workflow_id'] or
                    workflow.get('head_sha') != sha or workflow.get('status') != 'completed' or
                    workflow.get('conclusion') != 'success' or
                    (number is not None and (workflow.get('event') != 'pull_request' or
                     not any(pr.get('number') == number and pr.get('head', {}).get('sha') == sha for pr in workflow.get('pull_requests', [])))) or
                    (number is None and (workflow.get('event') not in ('push', 'workflow_dispatch') or workflow.get('head_branch') != branch))):
                raise Blocked('Actions workflow is not a successful configured producer on this PR head')
            jobs = pages(f'repos/{args.repo}/actions/runs/{run_id}/jobs?filter=latest&per_page=100', 'jobs')
            bound = [job for job in jobs if job.get('id') == job_id]
            if (len(bound) != 1 or bound[0].get('check_run_url') != f'https://api.github.com/repos/{args.repo}/check-runs/{check["id"]}' or
                    bound[0].get('head_sha') != sha or bound[0].get('status') != 'completed' or bound[0].get('conclusion') != 'success'):
                raise Blocked('Actions job does not corroborate the successful check run')
            proof['workflow_run_id'] = run_id
        verified.append(proof)
    return verified


def verify_protection(wanted):
    effective = pages(f'repos/{args.repo}/rules/branches/{quote(branch, safe="")}?per_page=100')
    sources = {}

    def unbypassed(rule):
        identifier = rule.get('ruleset_id')
        if not positive(identifier):
            return False
        if identifier not in sources:
            sources[identifier] = api(f'repos/{args.repo}/rulesets/{identifier}')
        source = sources[identifier]
        return source.get('target') == 'branch' and source.get('enforcement') == 'active' and source.get('bypass_actors') == []

    policy = any(rule.get('type') == 'pull_request' and
                 rule.get('parameters', {}).get('required_review_thread_resolution') is True and unbypassed(rule)
                 for rule in effective)
    result = dict(normalized, baseline_verified=policy, checks_verified=False)
    missing = False
    for wanted_check in wanted:
        found = False
        for rule in effective:
            if rule.get('type') != 'required_status_checks':
                continue
            parameters = rule.get('parameters', {})
            for check in parameters.get('required_status_checks', []):
                if check.get('context') != wanted_check['context']:
                    continue
                if check.get('integration_id') != wanted_check['integration_id']:
                    finish('blocked', 'conflicting_required_check_producer', result, 1)
                if (parameters.get('strict_required_status_checks_policy') is True and
                        parameters.get('do_not_enforce_on_create', False) is False and unbypassed(rule)):
                    found = True
        if not found:
            missing = True
    if not policy:
        finish('blocked', 'pr_policy_not_effective', result, 1)
    if missing:
        finish('blocked', 'required_checks_not_effective', result, 1)
    result['checks_verified'] = True
    result['ruleset_ids'] = sorted(sources)
    return result


try:
    parser = Parser(description='Verify evidence, never done flags. --run-local explicitly authorizes the exact argv in a command file; receipt JSON is returned in evidence. Only tracked/non-ignored files are digested. Save receipts in an ignored runtime directory or outside the project. Local receipts are integrity checks, not a sandbox or a defense against a caller with access to the private git key.')
    parser.add_argument('--project', required=True)
    parser.add_argument('--kind', required=True, choices=['local', 'ci', 'review', 'protection'])
    parser.add_argument('--repo')
    parser.add_argument('--pr', type=int)
    parser.add_argument('--evidence')
    parser.add_argument('--discover', action='store_true', help='Discover current Actions checks or bot review feedback; does not write GitHub')
    parser.add_argument('--run-local', action='store_true')
    parser.add_argument('--command-file')
    parser.add_argument('--key-dir', help='Explicit private directory for a non-Git local validation receipt key')
    args = parser.parse_args()
    project = Path(args.project).resolve(strict=True)
    if not project.is_dir():
        raise Invalid('--project must be a directory')
    probe = subprocess.run(['git', '-C', str(project), 'rev-parse', '--show-toplevel'], capture_output=True)
    has_git = probe.returncode == 0
    if has_git and Path(probe.stdout.decode().strip()).resolve() != project:
        raise Invalid('--project is nested in another Git worktree')
    if not has_git and (args.kind != 'local' or (project / '.git').exists()):
        raise Invalid('Remote evidence requires a valid Git worktree root')
    if args.run_local and args.kind != 'local':
        raise Invalid('--run-local is only valid with --kind local')
    evidence = load(args.evidence) if args.evidence else {}
    # A saved checker result can be passed directly, without extracting its payload.
    if evidence.get('status') in ('verified', 'blocked'):
        evidence = evidence.get('evidence', {})
    if args.kind == 'local':
        result = local_evidence()
    else:
        if args.run_local or args.command_file or (not args.evidence and not args.discover):
            raise Invalid('Remote checks require --evidence or --discover and do not accept local execution flags')
        if args.discover:
            if args.kind not in ('ci', 'review') or args.evidence:
                raise Invalid('--discover requires CI/review and no evidence file')
            evidence = {'schema_version': 1, 'repository': args.repo, 'pr': args.pr, 'head_sha': head()}
        number, branch, sha, pull = remote_identity()
        if args.discover:
            evidence = discover_configuration()
        normalized = {'schema_version': 1, 'repository': args.repo, 'pr': number,
                      'head_sha': sha, 'base_branch': branch, 'coverage': 'configured_checks'}
        if args.kind in ('ci', 'protection'):
            wanted = checks_config(evidence.get('checks'))
            normalized['checks'] = wanted
            result = dict(normalized, checks=verify_checks(wanted)) if args.kind == 'ci' else verify_protection(wanted)
        else:
            review = evidence.get('review', {})
            if review.get('type') == 'feedback':
                reviews = pages(f'repos/{args.repo}/pulls/{number}/reviews?per_page=100')
                matching = [r for r in reviews if r.get('commit_id') == sha and
                            r.get('user', {}).get('login') == review.get('reviewer') and r.get('user', {}).get('type') == 'Bot'
                            and r.get('state') in ('COMMENTED', 'APPROVED', 'CHANGES_REQUESTED')]
                if not matching:
                    raise Blocked('Configured automated reviewer has no current-head feedback')
                selected = max(matching, key=lambda r: r['id'])
                result = dict(normalized, coverage='review_integration_only',
                              review=dict(review, review_id=selected['id'], state=selected['state'], commit_id=sha))
            elif review.get('type') == 'check':
                wanted = checks_config([review.get('check')], actions=False)
                result = dict(normalized, review={'type': 'check', 'check': verify_checks(wanted, actions=False)[0]})
            elif review.get('type') == 'github_review' and isinstance(review.get('reviewer'), str) and review['reviewer']:
                reviews = pages(f'repos/{args.repo}/pulls/{number}/reviews?per_page=100')
                latest = {}
                for entry in sorted(reviews, key=lambda entry: entry['id']):
                    if entry.get('state') in ('APPROVED', 'CHANGES_REQUESTED', 'DISMISSED'):
                        latest[entry.get('user', {}).get('login')] = entry
                selected = latest.get(review['reviewer'], {})
                if (selected.get('state') != 'APPROVED' or selected.get('commit_id') != sha or
                        review['reviewer'] == pull.get('user', {}).get('login') or
                        any(entry.get('state') == 'CHANGES_REQUESTED' for entry in latest.values())):
                    raise Blocked('Configured reviewer has no current-head approval, or changes are requested')
                result = dict(normalized, review=dict(review, review_id=selected['id'], state='APPROVED', commit_id=sha))
            else:
                raise Invalid('Review requires a configured github_review reviewer or producer-bound check')
        # Do not return a stale receipt if the PR moved while the API was read.
        if number is None:
            current = api(f'repos/{args.repo}/git/ref/heads/{quote(branch, safe="")}')
            changed = current.get('object', {}).get('sha') != sha
        else:
            current = api(f'repos/{args.repo}/pulls/{number}')
            changed = (current.get('head', {}).get('sha') != sha or current.get('state') != 'open' or
                       current.get('base', {}).get('ref') != branch)
        if changed or head() != sha or git('status', '--porcelain', '--untracked-files=normal').strip():
            raise Blocked('PR/default branch or local target changed during evidence verification')
    finish('verified', f'{args.kind} evidence verified', result)
except Invalid as error:
    finish('blocked', str(error), code=2)
except (Blocked, OSError, KeyError, TypeError, ValueError, AttributeError) as error:
    finish('blocked', str(error), code=1)
PY
