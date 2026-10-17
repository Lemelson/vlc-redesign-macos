#!/usr/bin/env python3
"""Installer transaction checks using disposable paths and fake external tools only."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parent
IDENTITY = 'org.example.vlc-redesign.codex'


class InstallationTests(unittest.TestCase):
    def run_install(self, failure='', running=False, source_identity=IDENTITY, config_log=None, lock_pid=None):
        with tempfile.TemporaryDirectory(prefix='mxr-install-contract-') as temporary:
            root = Path(temporary)
            tools = root / 'tools'
            tools.mkdir()
            applications = root / 'Applications'
            applications.mkdir()
            build = root / 'build'
            build.mkdir()
            fakebin = root / 'bin'
            fakebin.mkdir()
            log = root / 'events'
            template = root / 'template'
            def bundle(path, identity, marker):
                (path / 'Contents/MacOS').mkdir(parents=True)
                (path / 'Contents/Frameworks/plugins').mkdir(parents=True)
                (path / marker).write_text(marker)
                (path / 'Contents/MacOS/VLC').write_bytes(bytes.fromhex('cffaedfe') + bytes(20))
                (path / 'Contents/Frameworks/plugins/libmacosx_redesign_plugin.dylib').write_bytes(bytes.fromhex('cffaedfe') + bytes(20))
                cache = path / 'Contents/Frameworks/plugins/plugins.dat'
                cache.write_bytes(b'cache')
                if failure == 'stale-cache':
                    os.utime(cache, ns=(0, 0))
                with (path / 'Contents/Info.plist').open('wb') as target:
                    plistlib.dump({'CFBundleIdentifier': identity}, target)
            destination = applications / 'VLC Redesign.app'
            personal = applications / 'VLC.app'
            bundle(destination, IDENTITY, 'old-install')
            bundle(personal, 'org.videolan.vlc', 'personal-vlc')
            bundle(template, source_identity, 'new-install')
            def tool(name, body):
                path = fakebin / name
                path.write_text('#!' + sys.executable + '\nimport os,pathlib,sys,shutil,plistlib\n' + body)
                path.chmod(0o755)
                return str(path)
            tool('xcrun', 'print("/fake-sdk")\n')
            tool('autoconf', '')
            tool('automake', '')
            tool('make', 'if "VLC.app" in sys.argv:\n shutil.copytree(os.environ["TEMPLATE"], pathlib.Path(sys.argv[sys.argv.index("-C")+1])/"VLC.app")\n')
            tool('ditto', 'shutil.copytree(sys.argv[1],sys.argv[2],symlinks=True)\n')
            tool('osascript', 'with open(os.environ["EVENTS"],"a") as f: f.write("osascript "+" ".join(sys.argv[1:])+"\\n")\nprint("true" if os.getenv("RUNNING")=="1" or (os.getenv("RUNNING")=="later" and pathlib.Path(os.environ["EVENTS"]).read_text().count("osascript ")>1) else "false")\n')
            plist = tool('plist', 'with open(sys.argv[-1],"rb") as f: print(plistlib.load(f)["CFBundleIdentifier"])\n')
            register = tool('register', 'sys.exit(7 if os.getenv("FAIL")=="register" else 0)\n')
            tool('codesign', 'sys.exit(7 if os.getenv("FAIL")=="sign" or (os.getenv("FAIL")=="verify" and "--verify" in sys.argv) else 0)\n')
            tool('python3', 'if len(sys.argv)>2 and sys.argv[1]=="-c" and "os.rename" in sys.argv[2] and os.getenv("FAIL")=="rename" and sys.argv[3].endswith("replacement.app"):\n sys.exit(8)\nos.execv(' + repr(sys.executable) + ',[' + repr(sys.executable) + ']+sys.argv[1:])\n')
            # autoconf's real config.log format: one "PATH: <dir>/" line per directory.
            if config_log is None:
                config_log = ''.join(f'PATH: {folder}/\n' for folder in [str(fakebin), *os.defpath.split(':')] if folder)
                config_log += "PATH_SEPARATOR=':'\n"
            (build / 'config.log').write_text(config_log)
            if lock_pid is not None:
                (applications / '.vlc-redesign-install.lock').mkdir()
                (applications / '.vlc-redesign-install.lock/pid').write_text(f'{lock_pid}\n')
            script = (TOOLS / 'install-app.sh').read_text()
            script = script.replace('mxr_source=$(cd "$(dirname "$0")/../../../.." && pwd)', 'mxr_source="' + str(root) + '"')
            script = script.replace('/Applications/VLC Redesign.app', str(destination))
            script = script.replace('/usr/libexec/PlistBuddy', plist)
            script = script.replace('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister', register)
            (tools / 'install-app.sh').write_text(script)
            shutil.copyfile(TOOLS / 'finalize-app.py', tools / 'finalize-app.py')
            env = dict(os.environ, FAIL=failure, RUNNING='later' if running == 'later' else '1' if running else '0', TEMPLATE=str(template), EVENTS=str(log))
            result = subprocess.run(['/bin/sh', str(tools / 'install-app.sh'), str(build)], env=env,
                                    capture_output=True, text=True, timeout=30)
            return (result, (destination / 'old-install').exists(), (destination / 'new-install').exists(),
                    (personal / 'personal-vlc').read_text(), list(applications.glob('.vlc-redesign-install*')),
                    log.read_text() if log.exists() else '')

    def test_failure_preserves_existing_install_and_cleans_stage(self):
        for failure in ('verify', 'stale-cache', 'rename', 'register'):
            with self.subTest(failure=failure):
                result, old, new, personal, stages, _ = self.run_install(failure=failure)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue(old, 'Working installation must survive any failed transaction')
                self.assertFalse(new)
                self.assertEqual(personal, 'personal-vlc')
                self.assertEqual(stages, [])

    def test_config_log_without_toolchain_path_fails_clearly(self):
        result, old, new, _, stages, _ = self.run_install(config_log="PATH_SEPARATOR=':'\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no PATH: lines', result.stderr)
        self.assertTrue(old)
        self.assertFalse(new)
        self.assertEqual(stages, [])

    def test_lock_left_by_killed_installer_is_reclaimed(self):
        dead = subprocess.Popen(['true'])
        dead.wait()
        result, old, new, _, stages, _ = self.run_install(lock_pid=dead.pid)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('stale installer lock', result.stderr)
        self.assertTrue(new)
        self.assertEqual(stages, [])

    def test_lock_of_live_installer_is_respected(self):
        result, old, new, _, stages, _ = self.run_install(lock_pid=os.getpid())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('owns', result.stderr)
        self.assertTrue(old)
        self.assertFalse(new)
        self.assertEqual([path.name for path in stages], ['.vlc-redesign-install.lock'])

    def test_stock_source_is_rejected_before_replacing_install(self):
        result, old, new, _, stages, _ = self.run_install(source_identity='org.videolan.vlc')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(old)
        self.assertFalse(new)
        self.assertEqual(stages, [])

    def test_running_application_is_never_quit_or_replaced(self):
        result, old, new, _, stages, events = self.run_install(running=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(old)
        self.assertFalse(new)
        self.assertNotIn('to quit', events)
        self.assertEqual(stages, [])

    def test_app_started_during_build_is_not_replaced(self):
        result, old, new, _, stages, events = self.run_install(running='later')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(old)
        self.assertFalse(new)
        self.assertEqual(stages, [])
        self.assertNotIn('to quit', events)

    def test_success_replaces_only_redesign_and_removes_transaction_artifacts(self):
        result, old, new, personal, stages, events = self.run_install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(old)
        self.assertTrue(new)
        self.assertEqual(personal, 'personal-vlc')
        self.assertEqual(stages, [])
        self.assertNotIn('to quit', events)


if __name__ == '__main__':
    unittest.main()
