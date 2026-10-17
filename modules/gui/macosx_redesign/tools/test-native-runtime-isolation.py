#!/usr/bin/env python3
"""Prove runtime fixture/isolation wiring without launching VLC or ffmpeg."""
import contextlib
import io
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

RUNNER = Path(os.environ.get('MXR_NATIVE_RUNNER', Path(__file__).with_name('native-tests.py')))


class RuntimeIsolationTests(unittest.TestCase):
    def exercise(self, suite, root, name, keep=True, fail=False, cache_gen=True, cache_writes=True):
        engine = root / 'engine'
        for item in ('config.h', 'src/.libs/libvlccore.dylib', 'modules/.libs/liblua_plugin.dylib',
                     'modules/.libs/libadummy_plugin.dylib', 'modules/.libs/libbonjour_plugin.dylib',
                     *(['bin/vlc-cache-gen'] if cache_gen else [])):
            target = engine / item
            target.parent.mkdir(parents=True, exist_ok=True)
            target.touch()
        work = root / name
        work.mkdir()
        calls = []
        namespace = runpy.run_path(str(RUNNER))
        def record(command, **kwargs):
            calls.append((command, dict(kwargs['env'])))
            if Path(str(command[0])).name == 'vlc-cache-gen' and cache_writes:
                (Path(command[1]) / 'plugins.dat').touch()
            if fail:
                raise subprocess.CalledProcessError(1, command)
        argv = [str(RUNNER), '--engine-build', str(engine), '--suite', suite] + (['--keep'] if keep else [])
        with patch.object(sys, 'argv', argv), \
             patch('tempfile.mkdtemp', return_value=str(work)), \
             patch('shutil.which', return_value='/unused/ffmpeg'), \
             patch('subprocess.run', side_effect=record), contextlib.redirect_stdout(io.StringIO()):
            namespace['main']()
        return work, calls

    def test_media_provisions_discoverable_fixture_and_unique_marker(self):
        with tempfile.TemporaryDirectory(prefix='mxr-runtime-runner-test-') as directory:
            root = Path(directory)
            markers = []
            for name in ('first', 'second'):
                work, calls = self.exercise('media', root, name)
                runs = [(command, env) for command, env in calls if Path(command[0]) == work / 'media-runtime']
                self.assertEqual(len(runs), 1, 'the media gate runs its harness once')
                command, env = runs[0]
                self.assertEqual(len(command), 4)
                marker = Path(command[3])
                self.assertEqual(marker.parent, work)
                self.assertFalse(marker.exists())
                fixture = Path(env['VLC_USERDATA_PATH']) / 'lua/extensions/runtime-trigger.lua'
                source = fixture.read_text()
                self.assertIn('title="MXR runtime trigger"', source)
                self.assertIn('capabilities={"trigger"}', source)
                self.assertIn(str(marker), source)
                markers.append(marker)
            self.assertNotEqual(*markers)

    def test_extension_gate_excludes_device_discovery_and_gui_plugins(self):
        with tempfile.TemporaryDirectory(prefix='mxr-runtime-runner-test-') as directory:
            work, calls = self.exercise('extensions', Path(directory), 'isolated')
            runs = [(command, env) for command, env in calls if Path(command[0]).parent == work]
            self.assertIn([str(work / 'extensions')], [command for command, _ in runs])
            command, env = runs[0]
            self.assertEqual(set(path.name for path in Path(env['VLC_PLUGIN_PATH']).iterdir()),
                             {'liblua_plugin.dylib', 'libadummy_plugin.dylib', 'plugins.dat'})
            self.assertEqual(Path(env['VLC_LIB_PATH']), work / 'modules')
            self.assertEqual(list((work / 'modules/plugins').iterdir()), [])

    def test_audio_gate_indexes_plugin_bank_before_any_harness_runs(self):
        # Without plugins.dat the core dlopens and, at libvlc_InternalCleanup,
        # dlcloses every plugin: the silent >8 s stretch after "removing keystore
        # memory" that made the audio-preferences shutdown deadline flake.
        with tempfile.TemporaryDirectory(prefix='mxr-runtime-runner-test-') as directory:
            root = Path(directory).resolve()
            work, calls = self.exercise('audio', root, 'cached')
            commands = [command for command, _ in calls]
            plugins = work / 'plugins'
            index = [i for i, command in enumerate(commands) if Path(command[0]).name == 'vlc-cache-gen']
            self.assertEqual(len(index), 1, commands)
            self.assertEqual(commands[index[0]], [str(root / 'engine/bin/vlc-cache-gen'), str(plugins)])
            harnesses = [i for i, command in enumerate(commands) if Path(command[0]).parent == work]
            self.assertTrue(harnesses and min(harnesses) > index[0], 'cache is generated before harnesses run')
            preference = [env for command, env in calls if Path(command[0]) == work / 'audio-preferences']
            self.assertEqual(len(preference), 1)
            self.assertEqual(Path(preference[0]['VLC_PLUGIN_PATH']), plugins)
            self.assertEqual(Path(preference[0]['MXR_NATIVE_EVIDENCE_DIR']), work)

    def test_missing_cache_gen_fails_every_suite_before_any_command(self):
        # A partial engine build without bin/vlc-cache-gen used to skip the index
        # without a word, so harnesses ran on an uncached bank (the flake's cause).
        for suite in ('contracts', 'audio', 'media', 'extensions'):
            with self.subTest(suite=suite), tempfile.TemporaryDirectory(prefix='mxr-runtime-runner-test-') as directory:
                stderr = io.StringIO()
                with self.assertRaises(SystemExit) as raised, contextlib.redirect_stderr(stderr):
                    self.exercise(suite, Path(directory), 'uncached', cache_gen=False)
                self.assertNotEqual(raised.exception.code, 0)
                self.assertIn('vlc-cache-gen', stderr.getvalue())

    def test_cache_gen_that_writes_no_index_fails_before_any_harness(self):
        with tempfile.TemporaryDirectory(prefix='mxr-runtime-runner-test-') as directory:
            with self.assertRaises(SystemExit) as raised:
                self.exercise('audio', Path(directory), 'noindex', cache_writes=False)
            self.assertIn('plugins.dat', str(raised.exception.code))

    def test_passing_run_removes_work_dir_and_failing_run_keeps_it(self):
        with tempfile.TemporaryDirectory(prefix='mxr-runtime-runner-test-') as directory:
            work, _ = self.exercise('extensions', Path(directory), 'passing', keep=False)
            self.assertFalse(work.exists())
            with self.assertRaises(subprocess.CalledProcessError):
                self.exercise('extensions', Path(directory), 'failing', keep=False, fail=True)
            self.assertTrue((Path(directory) / 'failing').exists())


if __name__ == '__main__':
    unittest.main()
