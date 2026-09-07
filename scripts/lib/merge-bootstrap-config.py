#!/usr/bin/env python3
"""Preserve unowned entries in bootstrap's indentation-based YAML configuration.

This merges our emitted block mappings, not arbitrary YAML, and never executes
or interprets values. Unknown subtrees are retained verbatim.
"""
import re
import sys
from pathlib import Path


def entries(lines, indent):
    result = {}
    current = None
    prefix = []
    for line in lines:
        if '\t' in line[:len(line) - len(line.lstrip())]:
            raise ValueError('Tabs in bootstrap configuration indentation are unsupported')
        match = re.match(r'^( *)([^\s#][^:]*):(?:\s|$)', line)
        if match and len(match[1]) == indent:
            current = match[2]
            if current in result:
                raise ValueError(f'Duplicate bootstrap configuration key: {current}')
            result[current] = []
        if current is None:
            prefix.append(line)
        else:
            result[current].append(line)
    return prefix, result


def merge(old, new, indent=0):
    old_prefix, previous = entries(old, indent)
    new_prefix, desired = entries(new, indent)
    output = new_prefix or old_prefix
    for key, block in desired.items():
        prior = previous.get(key)
        if prior and block[0].strip().endswith(':'):
            if not prior[0].strip().endswith(':'):
                raise ValueError(f'Unsupported inline mapping for {key}; preserve it and resolve the configuration manually')
            output += block[:1] + merge(prior[1:], block[1:], indent + 2)
        else:
            output += block
    for key, block in previous.items():
        if key not in desired:
            output += block
    return output


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: merge-bootstrap-config.py OLD DESIRED')
    try:
        old = Path(sys.argv[1]).read_text().splitlines(keepends=True)
        new = Path(sys.argv[2]).read_text().splitlines(keepends=True)
        sys.stdout.write(''.join(merge(old, new)))
    except (OSError, ValueError) as error:
        raise SystemExit(str(error)) from None
