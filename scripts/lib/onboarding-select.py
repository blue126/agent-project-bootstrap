#!/usr/bin/env python3
"""Small, dependency-free selector for bootstrap-owned choices (not Skills).

stdout is exclusively stable IDs, one per line, in option order. Both stdin
and stderr must be terminals; stdout may be captured by a shell. Exit codes:
0 = confirmed nonempty selection, 2 = invalid arguments, 3 = cancelled/no TTY.
"""

import argparse
import os
import re
import select
import sys
import termios
import tty
import unicodedata


class Cancelled(Exception):
    pass


class Parser(argparse.ArgumentParser):
    def print_help(self, file=None):
        super().print_help(file or sys.stderr)


def arguments():
    parser = Parser(description=__doc__)
    parser.add_argument('--title', required=True)
    parser.add_argument('--option', action='append', nargs=2, required=True,
                        metavar=('ID', 'LABEL'))
    parser.add_argument('--selected', action='append', default=[], metavar='ID')
    parser.add_argument('--multi', action='store_true')
    parser.add_argument('--plain', action='store_true',
                        help='Use numbered input (also used for TERM=dumb).')
    args = parser.parse_args()
    ids = [option[0] for option in args.option]
    if any(not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', item) or
           item.lower() == 'q' for item in ids):
        parser.error('IDs must be simple nonempty tokens; q is reserved for cancellation')
    if len(set(ids)) != len(ids):
        parser.error('option IDs must be unique')
    if set(args.selected) - set(ids):
        parser.error('--selected must name an available option ID')
    if not args.multi and len(set(args.selected)) > 1:
        parser.error('single selection accepts at most one --selected ID')
    return args


def clean(text):
    """Prevent labels/titles from injecting terminal controls or extra lines."""
    return ''.join(' ' if unicodedata.category(char).startswith('C') else char
                   for char in text)


def cell_width(char):
    if unicodedata.combining(char) or unicodedata.category(char) in ('Mn', 'Me'):
        return 0
    return 2 if unicodedata.east_asian_width(char) in ('W', 'F') else 1


def clipped(text, width):
    """Clip Unicode characters by display cells, never encoded byte offsets."""
    result, used = [], 0
    for char in clean(text):
        size = cell_width(char)
        if used + size > width:
            break
        result.append(char)
        used += size
    return ''.join(result)


def terminal_size():
    try:
        size = os.get_terminal_size(sys.stderr.fileno())
        return max(1, (size.columns or 80) - 1), max(1, size.lines or 24)
    except OSError:
        return 79, 24


def plain_select(args):
    ids = [item[0] for item in args.option]
    numbered = {str(index): item for index, item in enumerate(ids, 1)}
    selected = set(args.selected)
    width, _ = terminal_size()
    print(clipped(args.title, width), file=sys.stderr)
    for number, (item, label) in enumerate(args.option, 1):
        marker = '*' if item in selected else ' '
        print(clipped(f' {marker} {number}. {label} ({item})', width), file=sys.stderr)
    print('Enter IDs or numbers' + (' separated by spaces' if args.multi else '') +
          '; q/Esc cancels.', file=sys.stderr)
    if selected:
        print('Enter keeps: ' + ', '.join(item for item in ids if item in selected),
              file=sys.stderr)
    while True:
        print('> ', end='', file=sys.stderr, flush=True)
        line = sys.stdin.readline()
        if not line or '\x1b' in line or '\x03' in line or '\x04' in line:
            raise Cancelled
        tokens = line.split()
        if any(token.lower() == 'q' for token in tokens):
            raise Cancelled
        if not tokens:
            if selected:
                return selected
        elif args.multi or len(tokens) == 1:
            choice = set()
            for token in tokens:
                if token in ids:  # Stable IDs take precedence over numbered aliases.
                    choice.add(token)
                elif token.lstrip('0') in numbered:
                    choice.add(numbered[token.lstrip('0')])
                else:
                    break
            else:
                return choice
        print('Choose at least one valid option.' if args.multi else
              'Choose one valid option.', file=sys.stderr)


def read_key(fd):
    try:
        key = os.read(fd, 1)
        if key != b'\x1b':
            return key
        # Distinguish a standalone Escape from CSI/application cursor keys.
        sequence = b''
        while select.select([fd], [], [], 0.1)[0]:
            char = os.read(fd, 1)
            if not char:
                raise Cancelled
            sequence += char
            if len(sequence) == 1 and char not in (b'[', b'O'):
                return b'\x1b'
            if len(sequence) > 1 and 0x40 <= char[0] <= 0x7e:
                return {b'[A': b'up', b'OA': b'up',
                        b'[B': b'down', b'OB': b'down'}.get(sequence, b'other')
            if len(sequence) > 16:
                return b'other'
        return b'\x1b'
    except OSError:
        raise Cancelled from None


class InlineDisplay:
    """An inline block, with no alternate screen, colors, or persistent cursor state."""
    def __init__(self):
        self.lines = 0

    def clear(self):
        for _ in range(self.lines):
            sys.stderr.write('\x1b[1A\r\x1b[2K')
        self.lines = 0

    def draw(self, args, focus, selected, warning):
        self.clear()
        width, height = terminal_size()
        visible = max(1, min(len(args.option), height - 4))
        start = max(0, min(focus - visible // 2, len(args.option) - visible))
        lines = [args.title]
        for index in range(start, start + visible):
            item, label = args.option[index]
            pointer = '>' if index == focus else ' '
            mark = '[x]' if item in selected else '[ ]'
            lines.append(f'{pointer} {mark} {label}')
        hint = 'Arrows move' + (' / Space toggles' if args.multi else '') + ' / Enter confirms / q cancels'
        if visible < len(args.option):
            hint = f'{focus + 1}/{len(args.option)}  ' + hint
        lines.append(warning or hint)
        for line in lines:
            sys.stderr.write(clipped(line, width) + '\r\n')
        self.lines = len(lines)
        sys.stderr.flush()


def interactive_select(args):
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    display = InlineDisplay()
    selected = set(args.selected)
    ids = [item[0] for item in args.option]
    focus = next((index for index, item in enumerate(ids) if item in selected), 0)
    warning = ''
    try:
        tty.setraw(fd, termios.TCSANOW)
        sys.stderr.write('\x1b[?25l')
        while True:
            display.draw(args, focus, selected, warning)
            key = read_key(fd)
            warning = ''
            if key in (b'', b'\x03', b'\x04', b'\x1b', b'q', b'Q'):
                raise Cancelled
            if key in (b'up', b'down'):
                focus = (focus + (1 if key == b'down' else -1)) % len(ids)
            elif key == b' ' and args.multi:
                if ids[focus] in selected:
                    selected.remove(ids[focus])
                else:
                    selected.add(ids[focus])
            elif key in (b'\r', b'\n'):
                if not args.multi:
                    return {ids[focus]}
                if selected:
                    return selected
                warning = 'Choose at least one option (Space toggles).'
    finally:
        # No installer may inherit raw input, hidden cursor, or this menu block.
        try:
            termios.tcsetattr(fd, termios.TCSANOW, saved)
        finally:
            display.clear()
            sys.stderr.write('\x1b[?25h')
            sys.stderr.flush()


def main():
    args = arguments()
    if not (sys.stdin.isatty() and sys.stderr.isatty()):
        print('Selection requires terminal stdin and stderr.', file=sys.stderr)
        return 3
    try:
        if args.plain or os.environ.get('TERM', '') == 'dumb':
            selected = plain_select(args)
        else:
            selected = interactive_select(args)
    except (Cancelled, KeyboardInterrupt, EOFError):
        print('Selection cancelled.', file=sys.stderr)
        return 3
    for item, _ in args.option:
        if item in selected:
            print(item)
    return 0


if __name__ == '__main__':
    sys.exit(main())
