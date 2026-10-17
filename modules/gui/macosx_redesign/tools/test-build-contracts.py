#!/usr/bin/env python3
"""Disposable build-rule and distribution regression tests; no product builds."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

PACKAGE = Path(__file__).resolve().parent.parent
FAKE_XCRUN = '''#!/usr/bin/env python3
import os, pathlib, sys
bin = pathlib.Path(os.environ['FAKE_BIN'])
args = sys.argv[1:]
if args[:1] == ['actool']:
    out = pathlib.Path(args[args.index('--compile') + 1])
    (out / 'Assets.car').write_text('car')
    with open(os.environ['ACTOOL_LOG'], 'a') as log: log.write('actool\\n')
elif '--help' in args: print('native')
elif '--show-bin-path' in args: print(bin)
else:
    for name in ('MacOSXRedesign_MXRCore.bundle', 'MacOSXRedesign_MXRDesign.bundle'):
        (bin / name).mkdir(parents=True, exist_ok=True)
    (bin / 'libMXRPlugin.a').write_bytes(b'same bytes')
'''


class BuildContracts(unittest.TestCase):
    def test_source_and_resource_deletions_reinvoke_swiftpm(self):
        with tempfile.TemporaryDirectory(prefix='mxr-make-contract-') as temporary:
            root = Path(temporary)
            module = root / 'gui/macosx_redesign'
            (module / 'Sources').mkdir(parents=True)
            (module / 'tools').mkdir()
            (module / 'Package.swift').touch()
            source = module / 'Sources/Delete.swift'
            resource = module / 'Sources/Delete.json'
            source.touch()
            resource.touch()
            wrapper = module / 'tools/swiftpm-build.sh'
            wrapper.write_text('#!/bin/sh\nmkdir -p "$(dirname "$6")"\necho call >> calls\ntest -f "$6" || touch "$6"\n')
            makefile = root / 'Makefile'
            makefile.write_text('srcdir = .\nabs_top_srcdir = ..\nabs_builddir = .\nSHELL = /bin/sh\n' +
                '\n'.join(line for line in (PACKAGE / 'Makefile.am').read_text().splitlines()
                          if not line.startswith(('if ', 'endif', 'gui_PLUGINS +='))) + '\n')
            def build():
                result = subprocess.run(['make', '-f', str(makefile), 'gui/macosx_redesign/swift/libMXRPlugin.a'],
                                        cwd=root, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            build()
            source.unlink()
            build()
            resource.unlink()
            build()
            self.assertEqual((root / 'calls').read_text().splitlines(), ['call'] * 3)

    def test_unchanged_swift_output_does_not_refresh_archive_or_recompile_assets(self):
        # Runs the real wrapper with a fake xcrun whose `swift build` rewrites identical bytes,
        # as SwiftPM may; the archive mtime drives the plugin relink in Makefile.am.
        with tempfile.TemporaryDirectory(prefix='mxr-swiftpm-contract-') as temporary:
            root = Path(temporary)
            package = root / 'package'
            catalog = package / 'Sources/MXRDesign/Resources/Icons.xcassets'
            catalog.mkdir(parents=True)
            (catalog / 'Contents.json').write_text('{}')
            fakebin = root / 'fakebin'
            fakebin.mkdir()
            xcrun = fakebin / 'xcrun'
            xcrun.write_text(FAKE_XCRUN)
            xcrun.chmod(0o755)
            archive = root / 'out/libMXRPlugin.a'
            env = dict(os.environ, PATH=f'{fakebin}:/usr/bin:/bin', FAKE_BIN=str(root / 'swiftbin'),
                       ACTOOL_LOG=str(root / 'actool.log'), MXR_SWIFT_BUILD_SYSTEM='native')
            def build():
                result = subprocess.run(['/bin/sh', str(PACKAGE / 'tools/swiftpm-build.sh'), str(package),
                                         str(root / 'scratch'), 'arm64', 'debug', '', str(archive),
                                         str(root / 'out/resources')], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            build()
            first = archive.stat().st_mtime_ns
            time.sleep(0.05)
            build()
            self.assertEqual(archive.stat().st_mtime_ns, first, 'unchanged archive must keep its mtime')
            self.assertEqual((root / 'actool.log').read_text().splitlines(), ['actool'])
            time.sleep(0.05)
            (catalog / 'Contents.json').write_text('{"changed": true}')
            build()
            self.assertEqual((root / 'actool.log').read_text().splitlines(), ['actool'] * 2)

    def test_distribution_contains_all_module_inputs(self):
        # Evaluate the actual Automake variable list, not a second hard-coded helper list.
        with tempfile.TemporaryDirectory(prefix='mxr-dist-contract-') as temporary:
            makefile = Path(temporary) / 'Makefile'
            text = (PACKAGE / 'Makefile.am').read_text()
            text = '\n'.join(line for line in text.splitlines()
                             if not line.startswith(('if ', 'endif', 'gui_PLUGINS +=')))
            makefile.write_text('srcdir = .\n' + text + '\nprint-dist:\n\t@echo $(EXTRA_DIST)\n')
            result = subprocess.run(['make', '-f', str(makefile), 'print-dist'], cwd=PACKAGE.parents[1],
                                    capture_output=True, text=True, check=True)
            distributed = set(result.stdout.split())
            for folder in ('Resources', 'tools', 'Sources/MXRBridgeAPI/include'):
                for path in (PACKAGE / folder).rglob('*'):
                    if path.is_file() and '__pycache__' not in str(path):
                        self.assertIn(str(path.relative_to(PACKAGE.parents[1])), distributed)
            for folder in ('design/tokens', 'design/figma/icons-svg', 'patches/engine'):
                for path in (PACKAGE.parents[2] / 'redesign' / folder).rglob('*'):
                    if path.is_file():
                        self.assertIn('../' + str(path.relative_to(PACKAGE.parents[2])), distributed)

    def test_swift_unit_tests_never_register_or_present_gui_process(self):
        for path in (PACKAGE / 'Tests').rglob('*.swift'):
            text = path.read_text()
            for forbidden in ('finishLaunching(', 'makeKeyAndOrderFront(', 'setActivationPolicy('):
                self.assertNotIn(forbidden, text, str(path))

    def test_swift_test_windows_survive_close(self):
        # A window created in a test is released by close() unless told otherwise; ARC then
        # releases it again and xctest crashes with SIGSEGV after the test "passes".
        # Checked per window, in tests and in every Sources helper tests can call.
        problems = []
        for folder in ('Tests', 'Sources'):
            for path in (PACKAGE / folder).rglob('*.swift'):
                problems += [f'{path.relative_to(PACKAGE)}: {problem}'
                             for problem in windows_released_on_close(path.read_text())]
        self.assertEqual(problems, [])

    def test_window_contract_checks_each_window(self):
        # The earlier per-file check passed a file with one flagged and one unflagged window.
        two = ('let first = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)\n'
               'first.isReleasedWhenClosed = false\n'
               'let second = NSPanel(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)\n')
        self.assertEqual(windows_released_on_close(two), ['line 3: NSPanel window "second" never sets isReleasedWhenClosed = false'])
        self.assertEqual(windows_released_on_close(two + 'second.isReleasedWhenClosed = false\n'), [])
        # Another window's flag, an unbound construction and a local subclass are all caught.
        self.assertEqual(len(windows_released_on_close('let a = NSWindow()\nlet b = NSWindow()\nb.isReleasedWhenClosed = false\n')), 1)
        self.assertEqual(windows_released_on_close('return NSWindow(contentRect: .zero)\n'),
                         ['line 1: NSWindow constructed without a binding; bind it and set isReleasedWhenClosed = false'])
        self.assertEqual(len(windows_released_on_close('final class Probe: NSPanel {}\nlet p = Probe()\n')), 1)
        self.assertEqual(windows_released_on_close(
            'final class Safe: NSPanel {\n    init() { super.init(); isReleasedWhenClosed = false }\n}\nlet p = Safe()\n'), [])
        # A same-named window later in the file needs its own flag.
        self.assertEqual(len(windows_released_on_close(
            'let w = NSWindow()\nw.isReleasedWhenClosed = false\nlet w = NSWindow()\n')), 1)


def windows_released_on_close(text):
    """Every NSWindow/NSPanel (or local subclass) construction must be bound to a name that
    sets isReleasedWhenClosed = false before the next construction bound to the same name."""
    import re
    lines = text.splitlines()
    classes = {'NSWindow', 'NSPanel'}
    for declared in re.finditer(r'class\s+(\w+)\s*:\s*(?:NSWindow|NSPanel)\b[^{]*\{', text):
        depth, end = 1, declared.end()
        while depth and end < len(text):
            depth += {'{': 1, '}': -1}.get(text[end], 0)
            end += 1
        # A subclass that sets the flag on itself (in its init) is safe wherever it is built.
        if not re.search(r'(?<![\w.])(?:self\.)?isReleasedWhenClosed\s*=\s*false', text[declared.end():end]):
            classes.add(declared.group(1))
    kinds = '|'.join(sorted(classes))
    construction = re.compile(rf'(?<![\w.])({kinds})\(')
    binding = re.compile(rf'(?:let|var)\s+(\w+)\s*(?::\s*[\w.?]+\s*)?=\s*({kinds})\(')
    windows, problems = [], []
    for number, line in enumerate(lines, 1):
        code = line.split('//', 1)[0]
        for match in construction.finditer(code):
            bound = binding.search(code)
            if bound and bound.start(2) == match.start(1):
                windows.append((number, bound.group(1), bound.group(2)))
            else:
                problems.append(f'line {number}: {match.group(1)} constructed without a binding; '
                                'bind it and set isReleasedWhenClosed = false')
    for index, (number, name, kind) in enumerate(windows):
        end = next((later for later, other, _ in windows[index + 1:] if other == name), len(lines) + 1)
        flag = re.compile(rf'\b{name}\.isReleasedWhenClosed\s*=\s*false')
        if not any(flag.search(lines[row - 1]) for row in range(number, end)):
            problems.append(f'line {number}: {kind} window "{name}" never sets isReleasedWhenClosed = false')
    return sorted(problems, key=lambda problem: int(problem.split()[1].rstrip(':')))


if __name__ == '__main__':
    unittest.main()
