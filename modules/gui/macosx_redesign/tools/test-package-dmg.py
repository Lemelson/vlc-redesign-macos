#!/usr/bin/env python3
"""Release DMG checks on a disposable bundle and git checkout; real hdiutil, fake codesign and lipo."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parent
IDENTITY = 'io.github.lemelson.vlc-redesign'


class PackageDMGTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='mxr-dmg-contract-')
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.source)], check=True)
        (self.source / 'README').write_text('source\n')
        subprocess.run(['git', '-C', str(self.source), 'add', 'README'], check=True)
        subprocess.run(['git', '-C', str(self.source), '-c', 'user.name=t', '-c', 'user.email=t@example.invalid',
                        'commit', '-qm', 'source'], check=True)
        tools = self.root / 'tools'
        tools.mkdir()
        script = (TOOLS / 'package-dmg.sh').read_text()
        script = script.replace('mxr_source=$(cd "$(dirname "$0")/../../../.." && pwd)', 'mxr_source="' + str(self.source) + '"')
        (tools / 'package-dmg.sh').write_text(script)
        for name in ('finalize-app.py', 'dmg-first-launch.txt', 'gen-dmg-layout.py'):
            (tools / name).write_bytes((TOOLS / name).read_bytes())
        assets = self.root / 'Resources/dmg'
        assets.mkdir(parents=True)
        for asset in (TOOLS.parent / 'Resources/dmg').iterdir():
            (assets / asset.name).write_bytes(asset.read_bytes())
        self.assets = assets
        self.script = tools / 'package-dmg.sh'
        fakebin = self.root / 'bin'
        fakebin.mkdir()
        codesign = fakebin / 'codesign'
        codesign.write_text('#!' + sys.executable + '\nimport os,sys\nsys.exit(7 if os.getenv("FAIL")=="verify" else 0)\n')
        codesign.chmod(0o755)
        lipo = fakebin / 'lipo'
        lipo.write_text('#!/bin/sh\necho "${ARCHS:-x86_64 arm64}"\n')
        lipo.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{fakebin}:{os.environ["PATH"]}', TMPDIR=str(self.root))
        self.app = self.root / 'VLC Redesign.app'
        self.bundle(self.app, IDENTITY)
        self.out = self.root / 'out'

    def bundle(self, path, identity):
        (path / 'Contents/MacOS').mkdir(parents=True)
        plugins = path / 'Contents/Frameworks/plugins'
        plugins.mkdir(parents=True)
        (path / 'Contents/MacOS/VLC').write_bytes(bytes.fromhex('cffaedfe') + bytes(20))
        (plugins / 'libmacosx_redesign_plugin.dylib').write_bytes(bytes.fromhex('cffaedfe') + bytes(20))
        os.utime(plugins / 'libmacosx_redesign_plugin.dylib', ns=(0, 0))
        (plugins / 'plugins.dat').write_bytes(b'cache')
        (path / 'Contents/Resources').mkdir()
        (path / 'Contents/Resources/VLCRedesign.icns').write_bytes((TOOLS.parent / 'Resources/AppIcon.icns').read_bytes())
        with (path / 'Contents/Info.plist').open('wb') as target:
            plistlib.dump({'CFBundleIdentifier': identity, 'CFBundleShortVersionString': '1.0.0',
                           'CFBundleExecutable': 'VLC'}, target)

    def run_package(self, failure='', archs='x86_64 arm64'):
        return subprocess.run(['/bin/sh', str(self.script), str(self.out), str(self.app)],
                              env=dict(self.env, FAIL=failure, ARCHS=archs), capture_output=True, text=True, timeout=120)

    def mounted(self, dmg):
        mount = self.root / 'check'
        mount.mkdir()
        subprocess.run(['hdiutil', 'attach', '-quiet', '-readonly', '-nobrowse', '-mountpoint', str(mount), str(dmg)], check=True)
        self.addCleanup(subprocess.run, ['hdiutil', 'detach', '-quiet', '-force', str(mount)])
        return mount

    def test_packages_app_link_and_first_launch_notes(self):
        result = self.run_package()
        self.assertEqual(result.returncode, 0, result.stderr)
        commit = subprocess.run(['git', '-C', str(self.source), 'rev-parse', '--short=10', 'HEAD'],
                                capture_output=True, text=True, check=True).stdout.strip()
        dmg = self.out / 'VLC-Redesign-1.0.0-universal.dmg'
        self.assertTrue(dmg.is_file(), result.stdout)
        digest = (self.out / (dmg.name + '.sha256')).read_text()
        self.assertIn(dmg.name, digest)
        mount = self.mounted(dmg)
        self.assertTrue((mount / 'VLC Redesign.app/Contents/Frameworks/plugins/libmacosx_redesign_plugin.dylib').is_file())
        self.assertEqual(os.readlink(mount / 'Applications'), '/Applications')
        notes = (mount / 'Read Me First.txt').read_text()
        self.assertIn(commit, notes)
        self.assertIn('Open Anyway', notes)
        self.assertIn('VLC Redesign 1.0.0 for macOS 14', notes)
        self.assertIn('Apple silicon and Intel', notes)
        self.assertIn('not affiliated', notes.replace('\n', ' ').replace('  ', ' ').lower().replace('made by, ', ''))
        self.assertNotIn('@COMMIT@', notes)
        self.assertNotIn('@REPOSITORY@', notes)

    def test_rejects_foreign_identity(self):
        with (self.app / 'Contents/Info.plist').open('wb') as target:
            plistlib.dump({'CFBundleIdentifier': 'org.example.vlc-redesign.codex', 'CFBundleShortVersionString': '1.0.0',
                           'CFBundleExecutable': 'VLC'}, target)
        result = self.run_package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unexpected application identity', result.stderr)
        self.assertFalse(list(self.out.glob('*.dmg')))

    def test_rejects_bundle_whose_signature_fails(self):
        result = self.run_package('verify')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(list(self.out.glob('*.dmg')))

    def test_rejects_dirty_checkout_unless_allowed(self):
        (self.source / 'README').write_text('changed\n')
        result = self.run_package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('uncommitted changes', result.stderr)
        self.env['MXR_DMG_ALLOW_DIRTY'] = '1'
        self.assertEqual(self.run_package().returncode, 0)

    def test_leaves_no_staging_or_mount_behind(self):
        self.assertEqual(self.run_package().returncode, 0)
        self.assertFalse(list(self.root.glob('vlc-redesign-dmg.*')))
        attached = subprocess.run(['hdiutil', 'info'], capture_output=True, text=True, check=True).stdout
        self.assertNotIn(str(self.root), attached)

    def test_window_layout_background_and_volume_icon(self):
        result = self.run_package()
        self.assertEqual(result.returncode, 0, result.stderr)
        mount = self.mounted(self.out / 'VLC-Redesign-1.0.0-universal.dmg')
        self.assertEqual((mount / '.DS_Store').read_bytes(), (self.assets / 'DS_Store').read_bytes())
        info = subprocess.run(['tiffutil', '-info', str(mount / '.background/background.tiff')],
                              capture_output=True, text=True, check=True).stdout
        self.assertIn('Image Width: 640 Image Length: 480', info)
        self.assertIn('Image Width: 1280 Image Length: 960', info, 'a 2x picture for Retina displays')
        self.assertEqual((mount / '.VolumeIcon.icns').read_bytes(), (self.app / 'Contents/Resources/VLCRedesign.icns').read_bytes())
        finder_info = subprocess.run(['xattr', '-px', 'com.apple.FinderInfo', str(mount)], capture_output=True,
                                     text=True, check=True).stdout.replace(' ', '').replace('\n', '')
        self.assertEqual(finder_info[16:20], '0400', 'kHasCustomIcon makes Finder show .VolumeIcon.icns')
        volume = subprocess.run(['diskutil', 'info', str(mount)], capture_output=True, text=True).stdout
        self.assertIn('VLC Redesign', volume)

    def test_single_architecture_app_is_named_after_its_architecture(self):
        result = self.run_package(archs='arm64')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.out / 'VLC-Redesign-1.0.0-arm64.dmg').is_file())

    def test_rejects_a_layout_template_that_drifted_from_layout_json(self):
        layout = (self.assets / 'layout.json').read_text().replace('"iconSize": 96', '"iconSize": 80')
        (self.assets / 'layout.json').write_text(layout)
        result = self.run_package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('icon or text size', result.stderr)
        self.assertFalse(list(self.out.glob('*.dmg')))

    def test_rejects_an_item_that_leaves_its_card(self):
        layout = (self.assets / 'layout.json').read_text().replace('"Read Me First.txt": [112, 336]', '"Read Me First.txt": [112, 400]')
        (self.assets / 'layout.json').write_text(layout)
        result = self.run_package()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Read Me First.txt (with its label) does not fit inside a card', result.stderr)

    def test_template_matches_layout_and_is_wired_into_the_gate(self):
        check = subprocess.run([sys.executable, str(TOOLS / 'gen-dmg-layout.py'), '--check'], capture_output=True, text=True)
        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)
        self.assertIn('tools/test-package-dmg.py', (TOOLS.parent / 'Makefile.am').read_text())


if __name__ == '__main__':
    unittest.main()
