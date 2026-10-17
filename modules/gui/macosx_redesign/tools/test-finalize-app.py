#!/usr/bin/env python3
"""Signing/cache contract with fake tools and disposable Mach-O files."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

FINALIZER = Path(__file__).with_name('finalize-app.py')


class FinalizationTests(unittest.TestCase):
    def run_finalizer(self, mutate=False, escape=None, internal_links=False,
                      extra=('--sign', 'Contents/Frameworks/plugins/test.dylib'), cache_state='fresh'):
        with tempfile.TemporaryDirectory(prefix='mxr-sign-contract-') as temporary:
            root = Path(temporary)
            app = root / 'Redesign.app'
            plugins = app / 'Contents/Frameworks/plugins'
            plugins.mkdir(parents=True)
            binary = plugins / 'test.dylib'
            binary.write_bytes(b'\xcf\xfa\xed\xfe' + bytes(20))
            main = app / 'Contents/MacOS/VLC'
            main.parent.mkdir()
            main.write_bytes(binary.read_bytes())
            dependency = app / 'Contents/Frameworks/Test.framework/Versions/A/Test'
            dependency.parent.mkdir(parents=True)
            dependency.write_bytes(binary.read_bytes())
            resources = app / 'Contents/Resources/OnlyData.bundle'
            resources.mkdir(parents=True)
            (resources / 'file.json').write_text('{}')
            with (app / 'Contents/Info.plist').open('wb') as out:
                plistlib.dump({'CFBundleIdentifier': 'org.example.mxr.test'}, out)
            external = root / 'outside-app'
            external.mkdir()
            (external / 'sentinel').write_bytes(b'unchanged')
            if escape == 'plugins':
                plugins.rename(external / 'plugins')
                plugins.symlink_to(external / 'plugins', target_is_directory=True)
            elif escape == 'sign-target':
                main.rename(external / 'executable')
                main.symlink_to(external / 'executable')
            elif escape == 'cache':
                (plugins / 'plugins.dat').symlink_to(external / 'sentinel')
            elif escape == 'contents':
                (app / 'Contents').rename(external / 'Contents')
                (app / 'Contents').symlink_to(external / 'Contents', target_is_directory=True)
            if internal_links:
                framework = dependency.parents[2]
                (framework / 'Versions/Current').symlink_to('A', target_is_directory=True)
                (framework / 'Test').symlink_to('Versions/Current/Test')
            if cache_state:
                (plugins / 'plugins.dat').write_text('cache')
                if cache_state == 'stale':
                    os.utime(plugins / 'plugins.dat', ns=(0, 0))
            def external_state():
                return {str(path.relative_to(external)): path.read_bytes()
                        for path in external.rglob('*') if path.is_file()}
            before = external_state()
            # `make VLC.app` (codesign.sh) left every Frameworks item signed.
            signed = root / 'signed'
            signed.write_text(''.join(str(path) + '\n' for path in (app / 'Contents/Frameworks').rglob('*')
                                      if path.is_file() and not path.is_symlink()))
            signer = root / 'codesign'
            signer.write_text('''#!/usr/bin/env python3
import os, pathlib, sys
p = pathlib.Path(sys.argv[-1])
with open(os.environ['SIGN_LOG'], 'a') as f: f.write('sign ' + str(p) + '\\n')
if '--verify' not in sys.argv:
    signed = pathlib.Path(os.environ['SIGNED'])
    if p.is_file():
        p.write_bytes(p.read_bytes() + b'signed')
        with signed.open('a') as f: f.write(str(p) + '\\n')
    elif p.suffix == '.app':
        # Real codesign: Contents/Frameworks may hold only signed items.
        known = set(signed.read_text().splitlines())
        for item in (p / 'Contents/Frameworks').rglob('*'):
            if item.is_file() and not item.is_symlink() and str(item) not in known:
                sys.exit(f'code object is not signed at all: {item}')
        if os.getenv('MUTATE_PLUGIN'):
            b = p / 'Contents/Frameworks/plugins/test.dylib'
            b.write_bytes(b.read_bytes() + b'resigned')
''')
            signer.chmod(0o755)
            cache = root / 'cache-gen'
            cache.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
p = pathlib.Path(sys.argv[1])
with open(os.environ['SIGN_LOG'], 'a') as f: f.write('cache\\n')
(p / 'plugins.dat').write_text(json.dumps({b.name: b.stat().st_size for b in p.glob('*.dylib')}))
signed = pathlib.Path(os.environ['SIGNED'])  # a rewritten file loses its signature
signed.write_text(''.join(l + '\\n' for l in signed.read_text().splitlines() if not l.endswith('/plugins.dat')))
''')
            cache.chmod(0o755)
            env = dict(os.environ, SIGN_LOG=str(root / 'log'), SIGNED=str(signed))
            if mutate: env['MUTATE_PLUGIN'] = '1'
            arguments = [str(app / argument) if argument.startswith('Contents/') else argument for argument in extra]
            if '--verify-only' not in extra:
                arguments = [str(cache)] + arguments
            result = subprocess.run(['python3', str(FINALIZER), str(app), *arguments,
                                     '--codesign', str(signer)], capture_output=True, text=True, env=env)
            log = (root / 'log').read_text() if (root / 'log').exists() else ''
            return result, log, before == external_state()

    def test_rejects_external_mutation_paths_before_invoking_tools(self):
        for escape in ('plugins', 'sign-target', 'cache', 'contents'):
            with self.subTest(escape=escape):
                result, log, unchanged = self.run_finalizer(escape=escape)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(log, '', 'Containment must be checked before signing/cache generation')
                self.assertTrue(unchanged, 'No outside-app file may be changed')

    def test_retains_normal_framework_links_resolving_inside_bundle(self):
        result, _, _ = self.run_finalizer(internal_links=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_fails_if_final_seal_changes_cached_binary_metadata(self):
        result, _, _ = self.run_finalizer(mutate=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('cached plugin changed', result.stderr)

    def test_verify_only_never_signs_or_regenerates(self):
        result, log, _ = self.run_finalizer(extra=('--verify-only',), cache_state='fresh')
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = log.splitlines()
        self.assertEqual(len(lines), 1, 'only the bundle --verify call: ' + log)
        self.assertTrue(lines[0].endswith('Redesign.app'))

    def test_verify_only_rejects_plugin_newer_than_cache(self):
        result, _, _ = self.run_finalizer(extra=('--verify-only',), cache_state='stale')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('plugin cache predates', result.stderr)

    def test_resigns_only_named_plugin_then_caches_signs_cache_and_seals(self):
        result, log, _ = self.run_finalizer()
        self.assertEqual(result.returncode, 0, result.stderr)
        before, after = log.split('cache\n')
        self.assertEqual([line.rsplit('/', 1)[-1] for line in before.splitlines()], ['test.dylib'])
        self.assertEqual([line.rsplit('/', 1)[-1] for line in after.splitlines()],
                         ['plugins.dat', 'Redesign.app', 'Redesign.app'])

    def test_requires_named_replacement(self):
        result, log, _ = self.run_finalizer(extra=())
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(log, '')


if __name__ == '__main__':
    unittest.main()
