#!/usr/bin/env python3
"""Exercise the app hook against disposable bundles; never launch a stock VLC id."""
import base64
import hashlib
import json
import pathlib
import plistlib
import subprocess
import tempfile
import unittest

HOOK = pathlib.Path(__file__).with_name("app-bundle-hook.sh")


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="mxr-package-")
        self.addCleanup(self.scratch.cleanup)
        self.root = pathlib.Path(self.scratch.name)
        self.app = self.root / "VLC.app"
        self.plugins = self.app / "Contents/Frameworks/plugins"
        self.plugins.mkdir(parents=True)
        (self.plugins / "libmacosx_redesign_plugin.dylib").touch()
        resources = self.app / "Contents/Resources"
        for name in ("MXRCore", "MXRDesign"):
            (resources / f"MacOSXRedesign_{name}.bundle").mkdir(parents=True)
        self.info = self.app / "Contents/Info.plist"
        with self.info.open("wb") as target:
            plistlib.dump({"CFBundleIdentifier": "org.videolan.vlc", "CFBundleName": "VLC",
                           "NSMainNibFile": "MainMenu", "NSPrincipalClass": "VLCApplication",
                           "NSAccentColorName": "VLCAccentColor", "NSAppleScriptEnabled": True,
                           "SUFeedURL": "https://update.videolan.org/", "SUPublicEDKey": "stock-key",
                           "SUPublicDSAKeyFile": "dsa_pub.pem", "CFBundleShortVersionString": "4.0.0-dev",
                           "CFBundleVersion": "4.0.0-dev",
                           "NSHumanReadableCopyright": "Copyright (c) 1996-2026 VLC authors and VideoLAN"}, target)

    def run_hook(self, bundle_id="io.github.lemelson.vlc-redesign"):
        return subprocess.run(["/bin/sh", str(HOOK), str(self.app), str(self.root), bundle_id,
                               "VLC Redesign"], capture_output=True, text=True)

    def test_isolates_app_and_removes_stock_runtime_dependencies(self):
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        with self.info.open("rb") as source:
            info = plistlib.load(source)
        self.assertEqual(info["CFBundleIdentifier"], "io.github.lemelson.vlc-redesign")
        self.assertEqual(info["LSMinimumSystemVersion"], "14.0")
        self.assertEqual(info["NSPrincipalClass"], "NSApplication")
        self.assertFalse(info["NSAppleScriptEnabled"])
        self.assertIn("when you open Network or Cast", info["NSLocalNetworkUsageDescription"])
        self.assertIn("Music folder", info["NSAppleMusicUsageDescription"])
        for key in ("NSMainNibFile", "NSAccentColorName", "SUPublicDSAKeyFile"):
            self.assertNotIn(key, info)

    def test_app_version_comes_from_module_version_and_engine_version_is_kept(self):
        version = (HOOK.parent.parent / "VERSION").read_text().strip()
        self.assertRegex(version, r"^[0-9]+\.[0-9]+\.[0-9]+$")
        for run in range(2):  # packaging may run the hook again on the same Info.plist
            result = self.run_hook()
            self.assertEqual(result.returncode, 0, result.stderr)
        with self.info.open("rb") as source:
            info = plistlib.load(source)
        self.assertEqual(info["CFBundleShortVersionString"], version)
        self.assertEqual(info["CFBundleVersion"], version)
        self.assertEqual(info["MXREngineVersion"], "4.0.0-dev")

    def test_copyright_says_unofficial_and_keeps_videolan_copyright(self):
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        with self.info.open("rb") as source:
            notice = plistlib.load(source)["NSHumanReadableCopyright"]
        self.assertIn("unofficial build, not affiliated with or endorsed by VideoLAN", notice)
        self.assertIn("Copyright (c) 1996-2026 VLC authors and VideoLAN", notice)
        self.assertIn("VLC engine 4.0.0-dev", notice)
        self.assertIn("Juxtopposed", notice)
        self.assertEqual(notice.count("unofficial"), 1)

    def test_replaces_videolan_update_feed_with_ours(self):
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        with self.info.open("rb") as source:
            info = plistlib.load(source)
        feed = json.loads(HOOK.parent.parent.joinpath("Resources/update-feed.json").read_text())
        self.assertEqual(info["SUFeedURL"],
                         "https://github.com/Lemelson/vlc-redesign-macos/releases/latest/download/appcast.xml")
        self.assertEqual(info["SUFeedURL"], feed["feedURL"])
        self.assertEqual(info["SUPublicEDKey"], feed["publicEDKey"])
        self.assertEqual(len(base64.b64decode(info["SUPublicEDKey"])), 32)
        self.assertNotIn("videolan", info["SUFeedURL"])

    def test_ships_acknowledgements_with_sparkle_and_font_licenses_and_the_gpl(self):
        module = HOOK.parent.parent
        sparkle = module / "Resources/licenses/Sparkle-2.8.1-LICENSE.txt"
        # The LICENSE file of sparkle-project/Sparkle at tag 2.8.1, unchanged.
        self.assertEqual(hashlib.sha256(sparkle.read_bytes()).hexdigest(),
                         "389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe")
        for run in range(2):  # packaging may run the hook again on the same bundle
            result = self.run_hook()
            self.assertEqual(result.returncode, 0, result.stderr)
        resources = self.app / "Contents/Resources"
        text = (resources / "Acknowledgements.txt").read_text()
        fonts = module / "Sources/MXRDesign/Resources/Fonts"
        for source in (sparkle, fonts / "Inter-OFL.txt", fonts / "DMMono-OFL.txt"):
            self.assertEqual(text.count(source.read_text()), 1, source.name)
        for component in ("EXTERNAL LICENSES", "bsdiff", "sais-lite", "orlp/ed25519", "SUSignatureVerifier.m"):
            self.assertIn(component, text)
        self.assertIn("GNU General Public License, version 2 or later", text)
        self.assertIn("COPYING and COPYING.LIB next to this file", text)
        for license in ("COPYING", "COPYING.LIB"):
            self.assertEqual((resources / license).read_bytes(), (module.parents[2] / license).read_bytes())
        self.assertFalse((resources / "Acknowledgements.txt.tmp").exists())

    def test_rejects_stock_bundle_identity_before_modifying_it(self):
        before = self.info.read_bytes()
        result = self.run_hook("org.videolan.vlc")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stock VLC bundle identity", result.stderr)
        self.assertEqual(self.info.read_bytes(), before)

    def test_rejects_stock_interface_in_redesign_app(self):
        (self.plugins / "libmacosx_plugin.dylib").touch()
        result = self.run_hook()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stock interface must not", result.stderr)


if __name__ == "__main__":
    unittest.main()
