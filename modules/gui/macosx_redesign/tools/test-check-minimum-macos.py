#!/usr/bin/env python3
"""check-minimum-macos.py on disposable bundles of tiny real Mach-O files (clang, lipo)."""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('check_minimum_macos', TOOLS / 'check-minimum-macos.py')
check_minimum_macos = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_minimum_macos)


def compile_slice(root, arch, minimum, dynamic=True):
    out = root / f'{arch}-{minimum}{"-dylib" if dynamic else ""}'
    if not out.exists():
        source = root / 'code.c'
        source.write_text('int mxr_value(void) { return 1; }\nint main(void) { return 0; }\n')
        subprocess.run(['xcrun', 'clang', '-arch', arch, f'-mmacosx-version-min={minimum}',
                        *(['-dynamiclib'] if dynamic else []), '-o', str(out), str(source)], check=True)
    return out


class CheckMinimumMacOSTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix='mxr-minos-')
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)
        self.app = self.root / 'VLC Redesign.app'
        (self.app / 'Contents/MacOS').mkdir(parents=True)
        (self.app / 'Contents/Frameworks/plugins').mkdir(parents=True)
        (self.app / 'Contents/Resources').mkdir()
        (self.app / 'Contents/Resources/notes.txt').write_text('not code\n')
        self.info({'LSMinimumSystemVersion': '14.0'})
        # The shape of a release: arm64 engine at 11.0, x86_64 at 11.0 / 10.13, the interface at 14.0.
        self.universal('Contents/MacOS/VLC', {'arm64': '11.0', 'x86_64': '11.0'}, dynamic=False)
        self.universal('Contents/Frameworks/plugins/libmacosx_redesign_plugin.dylib', {'arm64': '14.0', 'x86_64': '14.0'})
        self.universal('Contents/Frameworks/libvlc.dylib', {'arm64': '11.0', 'x86_64': '10.13'})

    def info(self, values):
        with (self.app / 'Contents/Info.plist').open('wb') as target:
            plistlib.dump({'CFBundleIdentifier': 'io.github.lemelson.vlc-redesign', **values}, target)

    def universal(self, relative, minimums, dynamic=True):
        slices = [str(compile_slice(self.root, arch, minimum, dynamic)) for arch, minimum in minimums.items()]
        subprocess.run(['lipo', '-create', *slices, '-output', str(self.app / relative)], check=True)

    def test_accepts_a_release_shaped_bundle(self):
        self.assertEqual(check_minimum_macos.check(self.app), 6)

    def test_names_every_slice_newer_than_the_app_minimum(self):
        # 1.0.0/1.0.1 (issue #2): Objective-C binaries required the SDK's macOS.
        self.universal('Contents/MacOS/VLC', {'arm64': '26.0', 'x86_64': '14.0'}, dynamic=False)
        self.universal('Contents/Frameworks/plugins/libvout_macosx_plugin.dylib', {'arm64': '14.1', 'x86_64': '15.0'})
        with self.assertRaises(ValueError) as caught:
            check_minimum_macos.check(self.app)
        message = str(caught.exception)
        self.assertIn('3 slice(s) need a newer macOS than 14.0', message)
        self.assertIn('Contents/MacOS/VLC (arm64): minos 26.0', message)
        self.assertNotIn('Contents/MacOS/VLC (x86_64)', message)
        self.assertIn('libvout_macosx_plugin.dylib (arm64): minos 14.1', message)
        self.assertIn('libvout_macosx_plugin.dylib (x86_64): minos 15.0', message)

    def test_minimum_comes_from_info_plist_or_the_option(self):
        self.info({'LSMinimumSystemVersion': '11.0'})
        with self.assertRaisesRegex(ValueError, 'newer macOS than 11.0'):
            check_minimum_macos.check(self.app)
        self.assertEqual(check_minimum_macos.check(self.app, '14'), 6)
        self.info({})
        with self.assertRaisesRegex(ValueError, 'no LSMinimumSystemVersion'):
            check_minimum_macos.check(self.app)

    def test_command_line_exit_status(self):
        tool = [sys.executable, str(TOOLS / 'check-minimum-macos.py'), str(self.app)]
        passed = subprocess.run(tool, capture_output=True, text=True)
        self.assertEqual(passed.returncode, 0, passed.stderr)
        self.assertIn('PASS: all 6 Mach-O slices run on macOS 14.0', passed.stdout)
        self.universal('Contents/MacOS/VLC', {'arm64': '27.2', 'x86_64': '27.2'}, dynamic=False)
        failed = subprocess.run(tool, capture_output=True, text=True)
        self.assertEqual(failed.returncode, 1)
        self.assertIn('Contents/MacOS/VLC (x86_64): minos 27.2', failed.stderr)

    def test_check_is_wired_into_the_release_tools(self):
        self.assertIn('tools/test-check-minimum-macos.py', (TOOLS.parent / 'Makefile.am').read_text())
        self.assertIn('check-minimum-macos.py', (TOOLS / 'package-dmg.sh').read_text())
        self.assertIn('verify_minimum_macos(stage)', (TOOLS / 'make-universal.py').read_text())


if __name__ == '__main__':
    unittest.main()
