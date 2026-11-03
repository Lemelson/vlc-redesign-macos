#!/usr/bin/env python3
"""F5 (1.0.1): a background update check that falls during video playback runs once after
playback stops instead of waiting for Sparkle's next scheduled check. Compiles
module/bridge/tests/MXRUpdateDeferralTests.m without the engine. The policy cases always run;
the Sparkle case runs a real SPUUpdater against a feed on 127.0.0.1 when Sparkle.framework from
the contribs is found (MXR_SPARKLE_FRAMEWORKS, else ../build/codex-arm64 next to the repo)."""
import http.server
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import threading
import unittest

TOOLS = Path(__file__).resolve().parent
PACKAGE = TOOLS.parent
BRIDGE = PACKAGE / 'module/bridge'
TEST = BRIDGE / 'tests/MXRUpdateDeferralTests.m'
REPO = PACKAGE.parents[2]
EMPTY_FEED = (b'<?xml version="1.0" encoding="utf-8"?><rss version="2.0" '
              b'xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>'
              b'<title>VLC Redesign</title></channel></rss>')


def sparkle_frameworks():
    configured = os.environ.get('MXR_SPARKLE_FRAMEWORKS')
    candidates = [Path(configured)] if configured else sorted(
        (REPO.parent / 'build/codex-arm64/contrib').glob('*/Frameworks'))
    for folder in candidates:
        if (folder / 'Sparkle.framework/Headers/Sparkle.h').is_file():
            return folder
    return None


def compile_test(output, frameworks=None):
    command = ['xcrun', 'clang', '-fobjc-arc', '-mmacosx-version-min=14.0', '-Wall', '-Werror',
               '-I' + str(BRIDGE), str(TEST), '-framework', 'Foundation', '-o', str(output)]
    if frameworks is not None:
        command += ['-DMXR_WITH_SPARKLE', '-F' + str(frameworks), '-framework', 'Sparkle',
                    '-Wl,-rpath,' + str(frameworks)]
    subprocess.run(command, check=True)


class FeedHandler(http.server.BaseHTTPRequestHandler):
    requests = 0

    def do_GET(self):
        if self.path == '/count':
            body = str(FeedHandler.requests).encode()
        else:
            FeedHandler.requests += 1
            body = EMPTY_FEED
        self.send_response(200)
        self.send_header('Content-Type', 'application/rss+xml')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


class UpdateDeferralTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix='mxr-update-deferral-')
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name)

    def test_background_check_during_video_is_deferred_to_the_next_stop(self):
        binary = self.root / 'policy'
        compile_test(binary)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS: update deferral', result.stdout)

    def test_sparkle_reads_the_feed_once_after_playback_stops_and_never_during_it(self):
        frameworks = sparkle_frameworks()
        if frameworks is None:
            self.skipTest('Sparkle.framework from the contribs not found (set MXR_SPARKLE_FRAMEWORKS)')
        binary = self.root / 'sparkle'
        compile_test(binary, frameworks)
        FeedHandler.requests = 0
        server = http.server.HTTPServer(('127.0.0.1', 0), FeedHandler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        base = f'http://127.0.0.1:{server.server_port}'
        # A throwaway host bundle: Sparkle keeps its state in this identifier's defaults, which
        # start empty and are removed afterwards (file included: cfprefsd may leave it behind).
        identifier = 'io.github.lemelson.vlc-redesign.deferral-test'
        def forget():
            subprocess.run(['defaults', 'delete', identifier], capture_output=True)
            (Path.home() / f'Library/Preferences/{identifier}.plist').unlink(missing_ok=True)
        forget()
        host = self.root / 'Host.bundle'
        (host / 'Contents').mkdir(parents=True)
        with (host / 'Contents/Info.plist').open('wb') as target:
            plistlib.dump({'CFBundleIdentifier': identifier, 'CFBundleName': 'VLC Redesign',
                           'CFBundlePackageType': 'BNDL', 'CFBundleShortVersionString': '1.0.1',
                           'CFBundleVersion': '1.0.1', 'SUFeedURL': base + '/appcast.xml',
                           'SUPublicEDKey': 'cj29JUYuTRrmVrzx5gmBV82+3/sgPJq3g7sNbC44vEA=',
                           'SUEnableAutomaticChecks': True}, target)
        self.addCleanup(forget)
        result = subprocess.run([str(binary), str(host), base], capture_output=True, text=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS: update deferral', result.stdout)
        self.assertEqual(FeedHandler.requests, 1)


if __name__ == '__main__':
    unittest.main()
