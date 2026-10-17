#!/usr/bin/env python3
"""SCREENS.md is generated: the committed file must equal gen_screens.py's output.

A hand edit of SCREENS.md (or a generator that drops the status preamble or the
'Parity · live' column) fails here instead of being lost on the next regeneration.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[4]
GENERATOR = REPO / 'redesign/tools/figma/gen_screens.py'
SCREENS = REPO / 'redesign/design/SCREENS.md'


class ScreensDocTests(unittest.TestCase):
    def generate(self, *extra):
        with tempfile.TemporaryDirectory(prefix='mxr-screens-doc-') as directory:
            out = Path(directory) / 'SCREENS.md'
            subprocess.run([sys.executable, str(GENERATOR), '--out', str(out), *extra],
                           check=True, capture_output=True, text=True)
            return out.read_text(encoding='utf-8')

    def test_committed_file_is_the_generator_output(self):
        self.assertEqual(SCREENS.read_text(encoding='utf-8'), self.generate(),
                         'SCREENS.md differs from gen_screens.py output: change the generator and rerun it')

    def test_generator_emits_status_preamble_and_parity_column_for_every_screen(self):
        text = self.generate()
        self.assertIn('## Implementation status', text)
        self.assertIn('Capability limits:', text)
        rows = [line for line in text.splitlines() if re.match(r'^\| S\d\d \|', line)]
        self.assertEqual(len(rows), 72)
        verdict = re.compile(r'^(match|minor diff|major diff|missing|not checked|not judged)( \([A-J]-[a-z-]+(, [A-J]-[a-z-]+)*\))?( · live .+)?$')
        for row in rows:
            cells = [cell.strip() for cell in row.strip('|').split(' | ')]
            self.assertEqual(len(cells), 9, row[:40])
            self.assertEqual(cells[7], 'implemented UI', row[:40])
            self.assertRegex(cells[8], verdict)

    def test_parity_column_follows_the_parity_input(self):
        # The column is computed (worst verdict per S-id), not copied text: a different
        # judges' file changes the cells, and a screen nobody named reads 'not judged'.
        with tempfile.TemporaryDirectory(prefix='mxr-screens-parity-') as directory:
            parity = Path(directory) / 'parity.json'
            parity.write_text('[{"group": "g", "screens": ['
                              '{"screen": "S02 time labels", "verdict": "match", "owner": "B-controls"},'
                              '{"screen": "S02/S03 bar", "verdict": "major-diff", "owner": "B-controls / I-build"},'
                              '{"screen": "S03 seek", "verdict": "minor-diff", "owner": "A-window"}]}]')
            cells = {}
            for line in self.generate('--parity', str(parity)).splitlines():
                match = re.match(r'^\| (S\d\d) \|.*\| ([^|]*) \|$', line)
                if match:
                    cells[match.group(1)] = match.group(2)
        self.assertEqual(cells['S02'], 'major diff (B-controls, I-build)')
        self.assertEqual(cells['S03'], 'major diff (B-controls, I-build)')
        self.assertEqual(cells['S04'], 'not judged')


if __name__ == '__main__':
    unittest.main()
