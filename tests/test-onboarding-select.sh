#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Only the local selector runs inside these fixture PTYs; never an installer.
python3 -B - "${repo_root}" <<'PY'
import errno
import fcntl
import importlib.util
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time
import unittest

root = Path(sys.argv.pop())
script = root / 'scripts/lib/onboarding-select.py'
spec = importlib.util.spec_from_file_location('onboarding_select', script)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)

OPTIONS = ['--title', 'Choose clients', '--option', 'alpha', 'Alpha',
           '--option', 'beta', 'Beta', '--option', 'gamma', 'Gamma']


class SelectorTests(unittest.TestCase):
    def fixture(self, actions, extra=(), expected=0, output=b'', plain=False,
                term='xterm-256color', columns=80, options=OPTIONS, command=None):
        master, slave = pty.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, columns, 0, 0))
        saved = termios.tcgetattr(slave)
        env = os.environ.copy()  # Preserve Agent variables; this is only a mock UI fixture.
        env.update(TERM=term, NO_COLOR='1')
        if plain:
            extra = [*extra, '--plain']
        process = subprocess.Popen(command or [sys.executable, '-B', str(script), *options, *extra],
                                   stdin=slave, stderr=slave, stdout=subprocess.PIPE,
                                   env=env)
        transcript = b''
        cursor = 0
        deadline = time.monotonic() + 8

        def read(wait=0.05):
            nonlocal transcript
            if select.select([master], [], [], wait)[0]:
                try:
                    data = os.read(master, 65536)
                    transcript += data
                    return bool(data)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
            return False

        try:
            for prompt, answer in actions:
                while prompt not in transcript[cursor:]:
                    read()
                    if time.monotonic() > deadline or process.poll() is not None:
                        self.fail(f'Missing prompt {prompt!r}: {transcript!r}')
                cursor = transcript.index(prompt, cursor) + len(prompt)
                if isinstance(answer, int):
                    process.send_signal(answer)
                else:
                    os.write(master, answer)
            while process.poll() is None:
                read()
                if time.monotonic() > deadline:
                    self.fail(f'Selector hung: {transcript!r}')
            while read(0):
                if time.monotonic() > deadline:
                    self.fail('Selector output did not finish')
            stdout = process.communicate(timeout=1)[0]
            self.assertEqual(process.returncode, expected, transcript.decode(errors='replace'))
            self.assertEqual(stdout, output)
            restored = termios.tcgetattr(slave)
            # Darwin sets this kernel-owned pending-input flag when canonical
            # mode is restored; it is bookkeeping, not a changed user setting.
            restored[3] &= ~getattr(termios, 'PENDIN', 0)
            saved[3] &= ~getattr(termios, 'PENDIN', 0)
            self.assertEqual(restored, saved, 'selector leaked terminal mode')
            if not plain and term != 'dumb':
                self.assertIn(b'\x1b[?25l', transcript)
                self.assertIn(b'\x1b[?25h', transcript)
                self.assertGreater(transcript.rfind(b'\x1b[?25h'),
                                   transcript.rfind(b'\x1b[?25l'))
            else:
                self.assertNotIn(b'\x1b[', transcript)
            self.assertNotIn(b'\x1b[?1049', transcript, 'must not use an alternate screen')
            return transcript.decode('utf-8')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            if process.stdout:
                process.stdout.close()

    def test_shell_command_substitution_preserves_ui_and_result(self):
        shell = 'result=$("$@"); status=$?; printf "%s\\n" "$result"; exit "$status"'
        self.fixture([(b'q cancels', b'\x1b[B\r')], output=b'beta\n',
                     command=['bash', '-c', shell, 'selector-fixture',
                              sys.executable, '-B', str(script), *OPTIONS])

    def test_single_arrows(self):
        self.fixture([(b'q cancels', b'\x1b[B\r')], output=b'beta\n')

    def test_single_up_wraps(self):
        self.fixture([(b'q cancels', b'\x1b[A\r')], output=b'gamma\n')

    def test_application_cursor_keys(self):
        self.fixture([(b'q cancels', b'\x1bOB\x1bOB\x1bOA\r')], output=b'beta\n')

    def test_single_preselection(self):
        self.fixture([(b'q cancels', b'\r')], extra=['--selected', 'gamma'], output=b'gamma\n')

    def test_multi_arrows_and_space(self):
        self.fixture([(b'q cancels', b' \x1b[B \r')], extra=['--multi'],
                     output=b'alpha\nbeta\n')

    def test_multi_has_no_implicit_default(self):
        self.fixture([(b'q cancels', b'\r'), (b'Choose at least one option', b' \r')],
                     extra=['--multi'], output=b'alpha\n')

    def test_multi_preselection_and_toggle(self):
        self.fixture([(b'q cancels', b' \x1b[B \r')],
                     extra=['--multi', '--selected', 'alpha', '--selected', 'gamma'],
                     output=b'beta\ngamma\n')

    def test_multi_enter_keeps_explicit_preselection_in_option_order(self):
        self.fixture([(b'q cancels', b'\r')],
                     extra=['--multi', '--selected', 'gamma', '--selected', 'alpha'],
                     output=b'alpha\ngamma\n')

    def test_raw_cancellations_restore_terminal(self):
        for key in (b'q', b'Q', b'\x1b', b'\x03', b'\x04'):
            with self.subTest(key=key):
                text = self.fixture([(b'q cancels', key)], expected=3)
                self.assertIn('Selection cancelled.', text)

    def test_interrupt_signal_restores_terminal(self):
        self.fixture([(b'q cancels', signal.SIGINT)], expected=3)

    def test_plain_single_number(self):
        self.fixture([(b'> ', b'2\n')], plain=True, output=b'beta\n')

    def test_plain_multi_ids_and_numbers(self):
        self.fixture([(b'> ', b'gamma 1 gamma\n')], extra=['--multi'], plain=True,
                     output=b'alpha\ngamma\n')

    def test_plain_invalid_and_empty_retry_without_default(self):
        self.fixture([(b'> ', b'\n'), (b'Choose one valid option.', b'999\n'),
                      (b'Choose one valid option.', b'1 2\n'),
                      (b'Choose one valid option.', b'beta\n')],
                     plain=True, output=b'beta\n')

    def test_plain_multi_rejects_entire_invalid_choice(self):
        self.fixture([(b'> ', b'alpha invalid\n'),
                      (b'Choose at least one valid option.', b'2\n')],
                     plain=True, extra=['--multi'], output=b'beta\n')

    def test_plain_enter_keeps_explicit_preselection(self):
        self.fixture([(b'> ', b'\n')], plain=True,
                     extra=['--multi', '--selected', 'gamma', '--selected', 'alpha'],
                     output=b'alpha\ngamma\n')

    def test_dumb_terminal_automatically_uses_plain(self):
        self.fixture([(b'> ', b'gamma\n')], term='dumb', output=b'gamma\n')

    def test_plain_cancellations_and_eof(self):
        for key in (b'q\n', b'\x1b\n', b'\x04'):
            with self.subTest(key=key):
                self.fixture([(b'> ', key)], plain=True, expected=3)

    def test_plain_interrupt(self):
        self.fixture([(b'> ', signal.SIGINT)], plain=True, expected=3)

    def test_narrow_unicode_and_sanitized_labels(self):
        options = ['--title', 'Pick\n\x1b]0;unsafe\x07',
                   '--option', 'alpha', '中文选择项\n\t\x1b[31m\x07bad',
                   '--option', 'beta', 'Café']
        text = self.fixture([(b'/ q cancels', b'\r')], options=options, output=b'alpha\n')
        self.assertNotIn('\x07', text)
        self.assertNotIn('\x1b[31m', text)
        self.assertNotIn('\x1b]0;', text)
        # At narrow widths the footer is clipped, so wait for the last visible row.
        text = self.fixture([('  [ ] Café\r\n'.encode(), b'\r')], options=options,
                            columns=12, output=b'alpha\n')
        rendered = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', text)
        for line in rendered.splitlines():
            self.assertLessEqual(sum(selector.cell_width(char) for char in line), 11)

    def test_one_column_terminal(self):
        self.fixture([(b'C\r\n>\r\n \r\n \r\nA\r\n', b'\r')], columns=2,
                     output=b'alpha\n')

    def test_unicode_clipping_does_not_split_encoded_characters(self):
        self.assertEqual(selector.clipped('中文选择', 5), '中文')
        self.assertEqual(selector.clipped('Café', 4), 'Café')
        self.assertEqual(selector.clean('A\nB\x1b\x07‮'), 'A B   ')

    def test_runtime_exception_restores_terminal(self):
        # Force a failure after raw mode has been entered using a local mock,
        # not an external program or installer.
        code = '''import runpy, sys
module = runpy.run_path(sys.argv.pop(1))
def fail(self, *args):
    sys.stderr.write("ready\\r\\n")
    sys.stderr.flush()
    raise RuntimeError("fixture failure")
module["InlineDisplay"].draw = fail
module["main"]()
'''
        text = self.fixture([], expected=1, command=[sys.executable, '-B', '-c', code,
                                                   str(script), *OPTIONS])
        self.assertIn('fixture failure', text)

    def test_no_tty_fails_closed_without_stdout(self):
        for extra in ([], ['--plain']):
            result = subprocess.run([sys.executable, '-B', str(script), *OPTIONS, *extra],
                                    input=b'1\n', capture_output=True)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(result.stdout, b'')

    def test_invalid_arguments_are_exit_two(self):
        for extra in (['--selected', 'missing'], ['--selected', 'alpha', '--selected', 'beta'],
                      ['--option', 'alpha', 'Duplicate'], ['--option', 'bad\nID', 'Label'],
                      ['--option', 'q', 'Reserved']):
            with self.subTest(extra=extra):
                result = subprocess.run([sys.executable, '-B', str(script), *OPTIONS, *extra],
                                        capture_output=True)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, b'')

    def test_help_does_not_pollute_stdout(self):
        result = subprocess.run([sys.executable, '-B', str(script), '--help'], capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b'')
        self.assertIn(b'--option ID LABEL', result.stderr)


unittest.main()
PY
