#!/usr/bin/env python3
"""Universal-app merge checks on disposable bundles of tiny real Mach-O files (clang, lipo,
codesign); the plugin cache generator is a fake that writes plugins.dat."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parent
IDENTITY = 'io.github.lemelson.vlc-redesign'


class MakeUniversalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.objects = tempfile.TemporaryDirectory(prefix='mxr-universal-objects-')
        root = Path(cls.objects.name)
        (root / 'main.c').write_text('int main(void) { return 0; }\n')
        (root / 'lib.c').write_text('int mxr_value(void) { return 1; }\n')
        (root / 'media.c').write_text('#include <CoreMedia/CoreMedia.h>\nint mxr_time(void) { return (int)CMTimeMake(1, 2).value; }\n')
        cls.binaries = {}
        for arch in ('arm64', 'x86_64'):
            for name, flags in (('main', []), ('lib', ['-dynamiclib'])):
                out = root / f'{name}-{arch}'
                subprocess.run(['xcrun', 'clang', '-arch', arch, '-mmacosx-version-min=14.0', *flags,
                                '-o', str(out), str(root / f'{name}.c')], check=True)
                cls.binaries[name, arch] = out.read_bytes()
        # Xcode 27: x86_64 code linking CoreMedia for macOS < 10.15 gets @rpath/libswiftCoreMedia.dylib.
        old = root / 'media-x86_64-10.13'
        subprocess.run(['xcrun', 'clang', '-arch', 'x86_64', '-mmacosx-version-min=10.13', '-dynamiclib',
                        '-framework', 'CoreMedia', '-o', str(old), str(root / 'media.c')], check=True)
        cls.backdeployed = old.read_bytes()
        # 1.0.0/1.0.1 (issue #2): Objective-C code linked without a deployment target needed the SDK's macOS.
        cls.too_new = {}
        for arch in ('arm64', 'x86_64'):
            out = root / f'lib-{arch}-26'
            subprocess.run(['xcrun', 'clang', '-arch', arch, '-mmacosx-version-min=26.0', '-dynamiclib',
                            '-o', str(out), str(root / 'lib.c')], check=True)
            cls.too_new[arch] = out.read_bytes()

    @classmethod
    def tearDownClass(cls):
        cls.objects.cleanup()

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='mxr-universal-contract-')
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        cachegen = self.root / 'vlc-cache-gen'
        cachegen.write_text('#!/bin/sh\necho cache > "$1/plugins.dat"\n')
        cachegen.chmod(0o755)
        self.cachegen = cachegen
        self.arm = self.bundle('arm64')
        self.intel = self.bundle('x86_64')
        self.out = self.root / 'out'

    def bundle(self, arch, identity=IDENTITY):
        app = self.root / arch / 'VLC.app'
        contents = app / 'Contents'
        plugins = contents / 'Frameworks/plugins'
        for folder in (contents / 'MacOS', plugins / 'gui', contents / 'Resources', contents / 'Frameworks/lua'):
            folder.mkdir(parents=True)
        (contents / 'MacOS/VLC').write_bytes(self.binaries['main', arch])
        (contents / 'MacOS/VLC').chmod(0o755)
        (contents / 'MacOS/vlc-preparser').write_bytes(self.binaries['main', arch])
        (contents / 'MacOS/vlc-preparser').chmod(0o755)
        (contents / 'Frameworks/libvlc.12.dylib').write_bytes(self.binaries['lib', arch])
        os.symlink('libvlc.12.dylib', contents / 'Frameworks/libvlc.dylib')
        (plugins / 'libmacosx_redesign_plugin.dylib').write_bytes(self.binaries['lib', arch])
        (plugins / 'gui/libother_plugin.dylib').write_bytes(self.binaries['lib', arch])
        (plugins / 'plugins.dat').write_text(f'{arch} cache\n')
        (contents / 'Frameworks/lua/script.luac').write_bytes(b'\x1bLua shared')
        (contents / 'Resources/VLCRedesign.icns').write_bytes(b'icon')
        with (contents / 'Info.plist').open('wb') as target:
            plistlib.dump({'CFBundleIdentifier': identity, 'CFBundleExecutable': 'VLC',
                           'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '1.0.0',
                           'LSMinimumSystemVersion': '14.0', 'SUFeedURL': 'https://example.invalid/appcast.xml'}, target)
        sparkle = self.sparkle(contents / 'Frameworks/Sparkle.framework', arch)
        # As a packaged app: every item in Frameworks carries its own signature before the seal.
        nested = [path for path in (contents / 'Frameworks').rglob('*')
                  if path.is_file() and not path.is_symlink() and 'Sparkle.framework' not in path.parts]
        for path in [*sparkle, *nested, contents / 'MacOS/vlc-preparser', app]:
            subprocess.run(['codesign', '--force', '-s', '-', str(path)], check=True, capture_output=True)
        return app

    def sparkle(self, framework, arch):
        """A Sparkle 2 layout (the updater bundles one per architecture from contrib/<arch>/Frameworks),
        with an XPC service as newer Sparkle releases carry; returns what to sign, innermost first."""
        version = framework / 'Versions/B'
        def bundle(path, executable, kind):
            (path / 'Contents/MacOS').mkdir(parents=True)
            (path / 'Contents/MacOS' / executable).write_bytes(self.binaries['main', arch])
            (path / 'Contents/MacOS' / executable).chmod(0o755)
            with (path / 'Contents/Info.plist').open('wb') as target:
                plistlib.dump({'CFBundleIdentifier': 'org.sparkle-project.' + executable, 'CFBundleExecutable': executable,
                               'CFBundlePackageType': kind}, target)
        (version / 'Resources').mkdir(parents=True)
        (version / 'Sparkle').write_bytes(self.binaries['lib', arch])
        (version / 'Autoupdate').write_bytes(self.binaries['main', arch])
        (version / 'Autoupdate').chmod(0o755)
        with (version / 'Resources/Info.plist').open('wb') as target:
            plistlib.dump({'CFBundleIdentifier': 'org.sparkle-project.Sparkle', 'CFBundleExecutable': 'Sparkle',
                           'CFBundlePackageType': 'FMWK'}, target)
        bundle(version / 'Updater.app', 'Updater', 'APPL')
        bundle(version / 'XPCServices/Installer.xpc', 'Installer', 'XPC!')
        os.symlink('B', framework / 'Versions/Current')
        for name in ('Sparkle', 'Resources', 'Autoupdate', 'Updater.app', 'XPCServices'):
            os.symlink('Versions/Current/' + name, framework / name)
        return [version / 'Autoupdate', version / 'XPCServices/Installer.xpc', version / 'Updater.app', framework]

    def run_tool(self):
        return subprocess.run([sys.executable, str(TOOLS / 'make-universal.py'), str(self.arm), str(self.intel),
                               str(self.out), '--cachegen', str(self.cachegen)],
                              capture_output=True, text=True, timeout=120)

    def archs(self, path):
        return subprocess.run(['lipo', '-archs', str(path)], capture_output=True, text=True, check=True).stdout.split()

    def test_merges_every_binary_and_signs_the_result(self):
        result = self.run_tool()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        app = self.out / 'VLC Redesign.app'
        for relative in ('MacOS/VLC', 'MacOS/vlc-preparser', 'Frameworks/libvlc.12.dylib',
                         'Frameworks/plugins/libmacosx_redesign_plugin.dylib', 'Frameworks/plugins/gui/libother_plugin.dylib'):
            self.assertEqual(sorted(self.archs(app / 'Contents' / relative)), ['arm64', 'x86_64'], relative)
        self.assertEqual(os.readlink(app / 'Contents/Frameworks/libvlc.dylib'), 'libvlc.12.dylib')
        sparkle = app / 'Contents/Frameworks/Sparkle.framework/Versions/B'
        for relative in ('Sparkle', 'Autoupdate', 'Updater.app/Contents/MacOS/Updater',
                         'XPCServices/Installer.xpc/Contents/MacOS/Installer'):
            self.assertEqual(sorted(self.archs(sparkle / relative)), ['arm64', 'x86_64'], relative)
        subprocess.run(['codesign', '--verify', '--strict', str(sparkle.parent.parent)], check=True)
        self.assertEqual((app / 'Contents/Frameworks/plugins/plugins.dat').read_text(), 'cache\n',
                         'plugins.dat is regenerated for the merged plugins')
        self.assertEqual((app / 'Contents/Resources/VLCRedesign.icns').read_bytes(), b'icon')
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        self.assertIn('PASS', result.stdout)
        self.assertEqual([path.name for path in self.out.iterdir()], ['VLC Redesign.app'], 'no staging left behind')

    def test_leaves_out_plugins_built_for_one_architecture(self):
        # Kept, the other architecture logs "incompatible architecture" for them on every launch.
        plugins = 'Contents/Frameworks/plugins'
        (self.arm / plugins / 'libdeinterlace_sve_plugin.dylib').write_bytes(self.binaries['lib', 'arm64'])
        (self.intel / plugins / 'libdeinterlace_x86_plugin.dylib').write_bytes(self.binaries['lib', 'x86_64'])
        result = self.run_tool()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        app = self.out / 'VLC Redesign.app' / plugins
        self.assertFalse((app / 'libdeinterlace_sve_plugin.dylib').exists())
        self.assertFalse((app / 'libdeinterlace_x86_plugin.dylib').exists())
        self.assertIn('arm64-only plugin left out', result.stdout)
        self.assertIn('x86_64-only plugin left out', result.stdout)

    def test_contrib_builder_differences_keep_the_arm64_copy(self):
        for app, data in ((self.arm, b'arm jar'), (self.intel, b'intel jar')):
            (app / 'Contents/Frameworks/plugins/libbluray-j2se-1.4.1.jar').write_bytes(data)
        result = self.run_tool()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('contrib builder difference, arm64 copy kept', result.stdout)
        jar = self.out / 'VLC Redesign.app/Contents/Frameworks/plugins/libbluray-j2se-1.4.1.jar'
        self.assertEqual(jar.read_bytes(), b'arm jar')

    def test_rejects_a_slice_that_needs_back_deployed_swift(self):
        (self.intel / 'Contents/Frameworks/plugins/gui/libother_plugin.dylib').write_bytes(self.backdeployed)
        result = self.run_tool()
        if b'@rpath/libswift' not in self.backdeployed:
            self.skipTest('this linker no longer adds back-deployed Swift to CoreMedia clients')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('back-deployed Swift', result.stderr)
        self.assertIn('libother_plugin.dylib (x86_64)', result.stderr)
        self.assertFalse((self.out / 'VLC Redesign.app').exists())

    def test_rejects_a_slice_newer_than_the_app_minimum(self):
        for app, arch in ((self.arm, 'arm64'), (self.intel, 'x86_64')):
            (app / 'Contents/Frameworks/plugins/gui/libother_plugin.dylib').write_bytes(self.too_new[arch])
        result = self.run_tool()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('need a newer macOS than 14.0', result.stderr)
        self.assertIn('libother_plugin.dylib (arm64): minos 26.0', result.stderr)
        self.assertIn('libother_plugin.dylib (x86_64): minos 26.0', result.stderr)
        self.assertFalse((self.out / 'VLC Redesign.app').exists())

    def test_rejects_a_file_present_in_one_app_only(self):
        (self.intel / 'Contents/Resources/extra.txt').write_text('x')
        result = self.run_tool()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('only in the x86_64 app: Contents/Resources/extra.txt', result.stderr)
        self.assertFalse((self.out / 'VLC Redesign.app').exists())

    def test_rejects_different_resources(self):
        (self.intel / 'Contents/Frameworks/lua/script.luac').write_bytes(b'\x1bLua other')
        result = self.run_tool()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('different contents: Contents/Frameworks/lua/script.luac', result.stderr)
        self.assertFalse((self.out / 'VLC Redesign.app').exists())

    def test_rejects_code_in_one_app_only(self):
        (self.intel / 'Contents/Frameworks/plugins/gui/libother_plugin.dylib').write_bytes(b'not code')
        result = self.run_tool()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('code in one app only', result.stderr)

    def test_rejects_wrong_identity_or_architecture(self):
        with (self.intel / 'Contents/Info.plist').open('wb') as target:
            plistlib.dump({'CFBundleIdentifier': 'org.example.vlc-redesign.codex'}, target)
        result = self.run_tool()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unexpected application identity', result.stderr)
        # Two arm64 builds are not a universal pair.
        self.intel = self.arm
        result = self.run_tool()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no x86_64 slice', result.stderr)
        self.assertFalse((self.out / 'VLC Redesign.app').exists())

    def test_check_is_wired_into_the_module_gate(self):
        makefile = (TOOLS.parent / 'Makefile.am').read_text()
        self.assertIn('tools/test-make-universal.py', makefile)


if __name__ == '__main__':
    unittest.main()
