#!/usr/bin/env python3
"""Exercise the app hook against disposable bundles; never launch a stock VLC id."""
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
                           "SUPublicDSAKeyFile": "dsa_pub.pem"}, target)

    def run_hook(self, bundle_id="org.example.vlc-redesign.test"):
        return subprocess.run(["/bin/sh", str(HOOK), str(self.app), str(self.root), bundle_id,
                               "VLC Redesign"], capture_output=True, text=True)

    def test_isolates_app_and_removes_stock_runtime_dependencies(self):
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        with self.info.open("rb") as source:
            info = plistlib.load(source)
        self.assertEqual(info["CFBundleIdentifier"], "org.example.vlc-redesign.test")
        self.assertEqual(info["LSMinimumSystemVersion"], "14.0")
        self.assertEqual(info["NSPrincipalClass"], "NSApplication")
        self.assertFalse(info["NSAppleScriptEnabled"])
        self.assertIn("when you open Network or Cast", info["NSLocalNetworkUsageDescription"])
        for key in ("NSMainNibFile", "NSAccentColorName", "SUFeedURL", "SUPublicEDKey", "SUPublicDSAKeyFile"):
            self.assertNotIn(key, info)

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
