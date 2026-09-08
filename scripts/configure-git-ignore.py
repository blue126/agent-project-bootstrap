#!/usr/bin/env python3
"""Preview an additive project ignore policy; apply only the reviewed snapshot.

This is not a secret scanner or a general file classifier. No index, history,
remote or user file contents are changed beyond the explicitly listed edits.
"""
import argparse
from contextlib import ExitStack
import difflib
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

SOURCE = Path(__file__).resolve().parent.parent
LEGACY_SKILLS = '*\n!.gitignore\n'
SKILL_ROOTS = ('.agents/skills', '.claude/skills')
ASSET_ROOTS = ('.agents', '.claude', '_bmad', '_bmad-output', '.agent/policies')
PROBES = ('AGENTS.md', 'CLAUDE.md', '.agent/policies/git.md', 'skills-lock.json',
          '.claude/settings.json', '.claude/launch.json', '.claude/skills/example/SKILL.md',
          '.agents/skills/example/SKILL.md', '_bmad-output/planning-artifacts/prd.md')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(root, relative):
    path = root
    for part in Path(relative).parts:
        path = path / part
        if path.is_symlink():
            raise ValueError(f'Refusing symbolic-link policy path: {relative}')
    if path.exists() and not path.is_file():
        raise ValueError(f'Policy path is not a regular file: {relative}')
    if path.exists() and (path.stat().st_size > 1024 * 1024 or path.stat().st_nlink > 1):
        raise ValueError(f'Policy file is oversized or hard-linked: {relative}')
    return path


def read_policy(root, relative):
    path = safe_path(root, relative)
    return path.read_bytes() if path.exists() else None


def literal_pattern(path):
    # Gitignore metacharacters must not turn an exact local link into a glob.
    return '/' + ''.join('\\' + c if c in '\\ *?![]#' else c for c in path)


def git_env():
    return {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}


def inspect(root):
    assets = set(PROBES)
    links, inventory, warnings = [], [], []
    for name in ASSET_ROOTS:
        base = root / name
        if base.is_symlink():
            raise ValueError(f'Review symbolic-link Agent directory first: {name}')
        if not base.is_dir():
            continue
        for directory, dirs, files in os.walk(base, followlinks=False):
            parent = Path(directory)
            if '.git' in dirs or '.git' in files:
                warnings.append(f'Nested repository: {parent.relative_to(root)}; contents not inspected')
                dirs[:] = []
                continue
            for item in sorted(dirs + files):
                path = parent / item
                rel = path.relative_to(root).as_posix()
                if any(ord(c) < 32 or ord(c) == 127 for c in rel):
                    raise ValueError('Control characters in project paths require manual review')
                inventory.append(rel)
                if len(inventory) > 2000:
                    raise ValueError('Agent inventory exceeds 2000 entries; review scope manually, no files changed')
                if path.is_symlink():
                    target = os.readlink(path)
                    links.append({'path': rel, 'target': target})
                elif path.is_file() and rel != '.claude/settings.local.json' and not any(
                        part in ('worktrees', 'runtime', 'cache', '__pycache__') for part in Path(rel).parts):
                    assets.add(rel)
            # Never traverse runtime state, worktrees, caches or linked directories.
            dirs[:] = sorted(d for d in dirs if d not in ('worktrees', 'runtime', 'cache', '__pycache__')
                             and not (parent / d).is_symlink())
    # Git rejects a path below a symlink instead of checking its ignore status.
    # Check the link entry itself; canonical project sources are inspected above.
    normalized = set()
    for relative in assets:
        candidate = root
        for part in Path(relative).parts:
            candidate = candidate / part
            if candidate.is_symlink():
                relative = candidate.relative_to(root).as_posix()
                break
        normalized.add(relative)
    assets = normalized
    # An isolated Git directory reads the project's actual ignore rules without
    # initializing the project, inheriting global excludes, or touching its index.
    existing = subprocess.run(['git', '-C', str(root), 'rev-parse', '--git-dir'],
                              env=git_env(), capture_output=True).returncode == 0
    with ExitStack() as stack:
        if existing:
            cmd = ['git', '-C', str(root)]
            env = git_env()  # Include actual repository/global/info excludes.
        else:
            temp = stack.enter_context(tempfile.TemporaryDirectory(dir=os.environ.get('TMPDIR')))
            env = dict(git_env(), GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)
            subprocess.run(['git', 'init', '-q', temp], env=env, check=True, capture_output=True)
            cmd = ['git', '--git-dir', str(Path(temp) / '.git'), '--work-tree', str(root)]
        cmd += ['check-ignore', '--no-index', '-v', '-z', '--stdin']
        result = subprocess.run(cmd, input=b'\0'.join(os.fsencode(x) for x in sorted(assets)) + b'\0',
                                cwd=root, env=env, capture_output=True)
        if result.returncode not in (0, 1):
            raise ValueError('Cannot inspect project ignore rules; no files changed')
        fields = result.stdout.split(b'\0')
        ignored = []
        for i in range(0, len(fields) - 3, 4):
            source, line, pattern, path = [os.fsdecode(x) for x in fields[i:i + 4]]
            if not pattern.startswith('!'):
                ignored.append({'path': path, 'rule': pattern, 'source': source, 'line': line})
    tracked = []
    result = subprocess.run(['git', '-C', str(root), 'ls-files', '-z'], env=git_env(), capture_output=True)
    if result.returncode == 0:
        for value in result.stdout.split(b'\0'):
            path = os.fsdecode(value)
            if path and (path == '.claude/settings.local.json' or '/worktrees/' in path
                         or path.startswith('.agent/runtime/') and not path.endswith('/.gitignore')
                         or path == '.env' or path.startswith('.env.') and path != '.env.example'):
                tracked.append(path)
    return {'ignored_candidates': ignored, 'tracked_local_candidates': tracked,
            'links': links, 'inventory': sorted(inventory), 'warnings': warnings}


def proposal(root, migrate):
    facts = inspect(root)
    facts['legacy_skill_ignores'] = []
    changes = []

    def change(relative, text):
        before = read_policy(root, relative)
        after = text.encode()
        if before != after:
            diff = ''.join(difflib.unified_diff((before or b'').decode().splitlines(keepends=True),
                                              text.splitlines(keepends=True),
                                              fromfile=relative, tofile=relative))
            changes.append({'path': relative, 'before': before.decode() if before is not None else None,
                            'after': text, 'diff': diff})

    current = read_policy(root, '.gitignore')
    preferences = {'selected': [], 'config_sha256': None}
    if read_policy(root, '.agent/bootstrap.yml') is not None:
        result = subprocess.run([sys.executable, str(SOURCE / 'scripts/lib/onboarding-project.py'),
                                 '--project', str(root), 'metadata'], capture_output=True, text=True)
        if result.returncode:
            raise ValueError('Cannot validate project client preferences; no files changed')
        preferences = json.loads(result.stdout)
    facts['project_agents'] = preferences['selected']
    facts['config_sha256'] = preferences['config_sha256']
    baseline = (SOURCE / 'templates/project.gitignore').read_text()
    patterns = [line for line in baseline.splitlines() if line and not line.startswith('#')]
    if (root / '.claude').is_dir() or 'claude-code' in preferences['selected']:
        patterns += ['/.claude/settings.local.json', '/.claude/worktrees/']
    if (root / '.agents').is_dir() or set(preferences['selected']) & {'codex', 'opencode', 'universal'}:
        patterns += ['/.agents/worktrees/']
    for link in facts['links']:
        path = root / link['path']
        # Only links backed by our pinned Understand Anything runtime can be
        # automatically proposed for exclusion. Other links need human review.
        runtime = root / '.agent/runtime/understand-anything/repo'
        target = path.resolve()
        if not os.path.isabs(link['target']) and runtime in target.parents:
            patterns.append(literal_pattern(link['path']))
        else:
            facts['warnings'].append(f"Review link portability and tracked target: {link['path']}")
    text = current.decode() if current is not None else baseline
    missing = [p for p in patterns if p not in text.splitlines()]
    if missing:
        text += ('\n' if text and not text.endswith('\n') else '')
        text += '\n# Agent bootstrap: reviewed local-only paths\n' + '\n'.join(missing) + '\n'
    change('.gitignore', text)

    for skill_root in SKILL_ROOTS:
        relative = skill_root + '/.gitignore'
        old = read_policy(root, relative)
        if old is not None and old.decode().replace('\r\n', '\n') == LEGACY_SKILLS:
            facts['legacy_skill_ignores'].append(relative)
            facts['warnings'].append(f'Legacy blanket Skill ignore retained unless migration is confirmed: {relative}')
            if migrate:
                change(relative, (SOURCE / 'templates/skills.gitignore').read_text())
        elif old is not None and old != (SOURCE / 'templates/skills.gitignore').read_bytes():
            facts['warnings'].append(f'Existing Skill ignore rules retained for manual review: {relative}')

    # Existing instruction files are not replaced or claimed as managed files.
    # Their exact additive references are included in the same reviewed diff.
    for relative, reference, addition in (
        ('AGENTS.md', '.agent/policies/git.md',
         '\n## Git asset policy\n\nRead and follow `.agent/policies/git.md` before initialization, staging, committing, changing ignore rules, or cleanup.\n'),
        ('CLAUDE.md', 'AGENTS.md', '\nRead and follow `AGENTS.md` for shared project policies.\n'),
    ):
        old = read_policy(root, relative)
        if old is not None and reference not in old.decode():
            change(relative, old.decode().rstrip('\n') + '\n' + addition)
    payload = {'project': str(root), 'migrate_skills': migrate, 'changes': changes, 'facts': facts}
    payload['token'] = digest(json.dumps(payload, sort_keys=True).encode())
    return payload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', required=True)
    parser.add_argument('--migrate-skills', action='store_true', help='Preview removal of exact legacy blanket rules')
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--expect', help='Snapshot token from the reviewed preview; not publication authorization')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    root = Path(args.project).resolve(strict=True)
    if not root.is_dir():
        raise ValueError('Project must be an existing directory')
    top = subprocess.run(['git', '-C', str(root), 'rev-parse', '--show-toplevel'],
                         env=git_env(), capture_output=True, text=True)
    if top.returncode == 0 and Path(top.stdout.strip()).resolve() != root:
        raise ValueError('Target is inside another repository; review project boundary first')
    report = proposal(root, args.migrate_skills)
    if args.apply:
        if args.expect != report['token']:
            raise ValueError('Preview is missing or stale; inspect a fresh diff before applying')
        for item in report['changes']:
            safe_path(root, item['path'])
        for item in report['changes']:
            path = safe_path(root, item['path'])
            # Recheck immediately before writing, including absent -> existing.
            actual = path.read_bytes() if path.exists() else None
            expected = item['before'].encode() if item['before'] is not None else None
            if actual != expected:
                raise ValueError(f'File changed after preview: {item["path"]}; stop and re-inspect')
            with path.open('x' if expected is None else 'w') as handle:
                handle.write(item['after'])
    report['applied'] = args.apply
    if args.json:
        print(json.dumps(report, ensure_ascii=True))
    else:
        print('Ignore policy: ' + ('applied reviewed changes' if args.apply else 'preview only'))
        for item in report['changes']:
            print(item['diff'])
        for warning in report['facts']['warnings']:
            print('WARNING: ' + warning)
        for item in report['facts']['ignored_candidates']:
            print(f'Ignored candidate: {item["path"]} ({item["source"]}:{item["line"]}, {item["rule"]})')
        for path in report['facts']['tracked_local_candidates']:
            print('Already tracked, review separately (not removed): ' + path)
        print('Snapshot token: ' + report['token'])
        print('No staging, commit, secret scan or first-publication verification was performed.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from None
