#!/usr/bin/env python3
"""make-appcast.py with a throwaway key: the signature is checked by an independent Ed25519
implementation (RFC 8032 §6 in pure Python), so a CryptoKit/Sparkle format slip cannot pass
by verifying with the code that signed. Sparkle's own acceptance is the E2E run in
build/evidence/release-1.0 (updater-report.md)."""
import base64
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

TOOLS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('make_appcast', TOOLS / 'make-appcast.py')
make_appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(make_appcast)
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'

# RFC 8032 §6 reference verification (Ed25519), independent of CryptoKit.
P = 2 ** 255 - 19
L = 2 ** 252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P
SQRT_M1 = pow(2, (P - 1) // 4, P)


def _add(a, b):
    x1, y1, z1, t1 = a
    x2, y2, z2, t2 = b
    A, B = (y1 - x1) * (y2 - x2) % P, (y1 + x1) * (y2 + x2) % P
    C, Dd = t1 * 2 * D * t2 % P, z1 * 2 * z2 % P
    E, F, G, H = B - A, Dd - C, Dd + C, B + A
    return (E * F % P, G * H % P, F * G % P, E * H % P)


def _mul(s, point):
    q = (0, 1, 1, 0)
    while s > 0:
        if s & 1:
            q = _add(q, point)
        point = _add(point, point)
        s >>= 1
    return q


def _equal(a, b):
    return (a[0] * b[2] - b[0] * a[2]) % P == 0 and (a[1] * b[2] - b[1] * a[2]) % P == 0


def _recover_x(y, sign):
    if y >= P:
        return None
    x2 = (y * y - 1) * pow(D * y * y + 1, P - 2, P)
    if x2 == 0:
        return None if sign else 0
    x = pow(x2, (P + 3) // 8, P)
    if (x * x - x2) % P != 0:
        x = x * SQRT_M1 % P
    if (x * x - x2) % P != 0:
        return None
    return P - x if (x & 1) != sign else x


def _decompress(data):
    y = int.from_bytes(data, 'little')
    sign, y = y >> 255, y & ((1 << 255) - 1)
    x = _recover_x(y, sign)
    return None if x is None else (x, y, 1, x * y % P)


G_Y = 4 * pow(5, P - 2, P) % P
G = (_recover_x(G_Y, 0), G_Y, 1, _recover_x(G_Y, 0) * G_Y % P)


def ed25519_verify(public, message, signature):
    A, R = _decompress(public), _decompress(signature[:32])
    s = int.from_bytes(signature[32:], 'little')
    if A is None or R is None or s >= L:
        return False
    h = int.from_bytes(hashlib.sha512(signature[:32] + public + message).digest(), 'little') % L
    return _equal(_mul(s, G), _add(R, _mul(h, A)))


class MakeAppcastTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scratch = tempfile.TemporaryDirectory(prefix='mxr-appcast-test-')
        cls.root = Path(cls.scratch.name)
        cls.helper = make_appcast.build_helper(cls.root)
        cls.key = cls.root / 'throwaway.key'
        cls.public = subprocess.run([str(cls.helper), 'generate-key', str(cls.key)], check=True,
                                    capture_output=True, text=True).stdout.strip()
        cls.feed = dict(make_appcast.feed_config(), publicEDKey=cls.public)

    @classmethod
    def tearDownClass(cls):
        cls.scratch.cleanup()

    def dmg(self, name, **info):
        folder = Path(tempfile.mkdtemp(dir=self.root))
        contents = folder / 'src/VLC Redesign.app/Contents'
        contents.mkdir(parents=True)
        plist = {'CFBundleName': 'VLC Redesign', 'CFBundleShortVersionString': '1.0.1', 'CFBundleVersion': '1.0.1',
                 'LSMinimumSystemVersion': '14.0', 'SUPublicEDKey': self.public, 'SUFeedURL': self.feed['feedURL']}
        plist.update(info)
        with (contents / 'Info.plist').open('wb') as target:
            plistlib.dump(plist, target)
        (folder / 'src/Applications').symlink_to('/Applications')
        dmg = folder / name
        subprocess.run(['hdiutil', 'create', '-quiet', '-fs', 'HFS+', '-format', 'UDZO', '-volname', 'VLC Redesign',
                        '-srcfolder', str(folder / 'src'), str(dmg)], check=True)
        return dmg

    def make(self, dmg, **options):
        out = dmg.with_suffix('.xml')
        make_appcast.make_appcast(dmg, self.key, out, feed=self.feed, helper=self.helper, **options)
        return ET.parse(out).getroot()

    def test_appcast_item_is_signed_sized_and_linked_to_the_release(self):
        dmg = self.dmg('VLC-Redesign-1.0.1.dmg')
        item = self.make(dmg, version='1.0.1').find('channel/item')
        enclosure = item.find('enclosure')
        self.assertEqual(enclosure.get('url'),
                         'https://github.com/Lemelson/vlc-redesign-macos/releases/download/v1.0.1/VLC-Redesign-1.0.1.dmg')
        self.assertEqual(int(enclosure.get('length')), dmg.stat().st_size)
        self.assertEqual(item.findtext(f'{SPARKLE}version'), '1.0.1')
        self.assertEqual(item.findtext(f'{SPARKLE}shortVersionString'), '1.0.1')
        self.assertEqual(item.findtext(f'{SPARKLE}minimumSystemVersion'), '14.0')
        self.assertEqual(item.findtext(f'{SPARKLE}releaseNotesLink'),
                         'https://github.com/Lemelson/vlc-redesign-macos/releases/tag/v1.0.1')
        signature = base64.b64decode(enclosure.get(f'{SPARKLE}edSignature'))
        public = base64.b64decode(self.public)
        self.assertEqual((len(public), len(signature)), (32, 64))
        data = dmg.read_bytes()
        self.assertTrue(ed25519_verify(public, data, signature), 'RFC 8032 rejects the CryptoKit signature')
        tampered = bytearray(data)
        tampered[len(tampered) // 2] ^= 1
        self.assertFalse(ed25519_verify(public, bytes(tampered), signature))

    def test_notes_are_inline_with_the_release_page_as_full_notes(self):
        dmg = self.dmg('VLC-Redesign-1.0.2.dmg', CFBundleShortVersionString='1.0.2', CFBundleVersion='1.0.2')
        notes = self.root / 'notes.html'
        notes.write_text('<ul><li>Fixes</li></ul>')
        item = self.make(dmg, download_base='http://127.0.0.1:8000').find('channel/item')
        self.assertEqual(item.find('enclosure').get('url'), 'http://127.0.0.1:8000/VLC-Redesign-1.0.2.dmg')
        item = self.make(dmg, notes=notes).find('channel/item')
        self.assertIn('Fixes', item.findtext('description'))
        self.assertTrue(item.findtext(f'{SPARKLE}fullReleaseNotesLink').endswith('/releases/tag/v1.0.2'))

    def test_refuses_a_key_or_app_the_shipped_app_could_not_verify(self):
        dmg = self.dmg('other-key.dmg', SUPublicEDKey='AAAA')
        with self.assertRaisesRegex(make_appcast.AppcastError, 'SUPublicEDKey'):
            self.make(dmg)
        dmg = self.dmg('wrong-version.dmg')
        with self.assertRaisesRegex(make_appcast.AppcastError, 'the app in the DMG is 1.0.1'):
            self.make(dmg, version='1.0.2')
        with self.assertRaisesRegex(make_appcast.AppcastError, 'does not match publicEDKey'):
            make_appcast.make_appcast(dmg, self.key, self.root / 'x.xml', feed=dict(self.feed, publicEDKey='AAAA'),
                                      helper=self.helper)

    def test_generate_key_never_overwrites_and_keeps_the_key_private(self):
        self.assertEqual(self.key.stat().st_mode & 0o777, 0o600)
        result = subprocess.run([str(self.helper), 'generate-key', str(self.key)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn(self.key.read_text().strip(), result.stdout + result.stderr)

    def test_shipped_public_key_is_a_valid_ed25519_point(self):
        raw = base64.b64decode(make_appcast.feed_config()['publicEDKey'])
        self.assertEqual(len(raw), 32)
        self.assertIsNotNone(_decompress(raw))


if __name__ == '__main__':
    unittest.main()
