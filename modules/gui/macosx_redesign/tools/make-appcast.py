#!/usr/bin/env python3
"""Write the Sparkle appcast.xml for one release DMG (D059).

Reads the app inside the DMG (mounted read-only), checks that it carries our feed key and that
the private key matches it, signs the whole DMG with Ed25519 (tools/sparkle-ed25519.swift, Apple
CryptoKit; nothing is downloaded) and writes an appcast whose single item points at the DMG
attached to the GitHub release. The private key is read from a file and never printed.

    tools/make-appcast.py VLC-Redesign-1.0.1.dmg --key ~/…/sparkle-ed25519-private.key --out appcast.xml

Upload both the DMG and appcast.xml to the release `v<version>`; the app reads
releases/latest/download/appcast.xml, so publishing the release is what ships the update.
"""
import argparse
import email.utils
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from xml.sax.saxutils import escape, quoteattr

TOOLS = Path(__file__).resolve().parent
FEED = TOOLS.parent / 'Resources/update-feed.json'
HELPER = TOOLS / 'sparkle-ed25519.swift'
SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'


class AppcastError(Exception):
    pass


def feed_config(path=FEED):
    return json.loads(Path(path).read_text())


def build_helper(directory):
    """Compiles the CryptoKit helper once per run (a few seconds, no network)."""
    binary = Path(directory) / 'sparkle-ed25519'
    env_cache = Path(directory) / 'module-cache'
    subprocess.run(['xcrun', 'swiftc', '-O', '-module-cache-path', str(env_cache), str(HELPER), '-o', str(binary)],
                   check=True, capture_output=True)
    return binary


def helper_output(helper, *arguments):
    result = subprocess.run([str(helper), *map(str, arguments)], capture_output=True, text=True)
    if result.returncode != 0:
        raise AppcastError(result.stderr.strip() or f'{arguments[0]} failed')
    return result.stdout.strip()


def app_info(dmg, scratch):
    """Info.plist of the single .app at the root of the DMG."""
    mount = Path(scratch) / 'mount'
    mount.mkdir()
    subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen', '-quiet',
                    '-mountpoint', str(mount), str(dmg)], check=True)
    try:
        apps = sorted(p for p in mount.iterdir() if p.suffix == '.app' and not p.is_symlink())
        if len(apps) != 1:
            raise AppcastError(f'expected one .app at the root of the DMG, found {len(apps)}')
        with (apps[0] / 'Contents/Info.plist').open('rb') as source:
            return plistlib.load(source)
    finally:
        subprocess.run(['hdiutil', 'detach', '-quiet', str(mount)], check=False)


def appcast_xml(*, title, version, short_version, url, length, signature, minimum_system, release_page, notes_html=None, pub_date=None):
    pub_date = pub_date or email.utils.formatdate(usegmt=True)
    notes = (f'      <description><![CDATA[{notes_html}]]></description>\n'
             f'      <sparkle:fullReleaseNotesLink>{escape(release_page)}</sparkle:fullReleaseNotesLink>\n'
             if notes_html else
             f'      <sparkle:releaseNotesLink>{escape(release_page)}</sparkle:releaseNotesLink>\n')
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            f'<rss version="2.0" xmlns:sparkle="{SPARKLE_NS}">\n'
            '  <channel>\n'
            f'    <title>{escape(title)}</title>\n'
            '    <item>\n'
            f'      <title>Version {escape(short_version)}</title>\n'
            f'      <pubDate>{pub_date}</pubDate>\n'
            f'      <sparkle:version>{escape(version)}</sparkle:version>\n'
            f'      <sparkle:shortVersionString>{escape(short_version)}</sparkle:shortVersionString>\n'
            f'      <sparkle:minimumSystemVersion>{escape(minimum_system)}</sparkle:minimumSystemVersion>\n'
            + notes +
            f'      <enclosure url={quoteattr(url)} length="{length}" type="application/octet-stream"\n'
            f'                 sparkle:edSignature={quoteattr(signature)}/>\n'
            '    </item>\n'
            '  </channel>\n'
            '</rss>\n')


def make_appcast(dmg, key, out, *, version=None, tag=None, download_base=None, notes=None, feed=None, helper=None):
    dmg, key, out = Path(dmg), Path(key), Path(out)
    config = feed or feed_config()
    with tempfile.TemporaryDirectory(prefix='mxr-appcast-') as scratch:
        helper = helper or build_helper(scratch)
        public = helper_output(helper, 'public-key', key)
        if public != config['publicEDKey']:
            raise AppcastError('the private key does not match publicEDKey in update-feed.json')
        info = app_info(dmg, scratch)
        if info.get('SUPublicEDKey') != public:
            raise AppcastError('the app in the DMG does not carry this SUPublicEDKey; it could never verify the update')
        if info.get('SUFeedURL') != config['feedURL']:
            raise AppcastError(f'the app in the DMG reads another feed: {info.get("SUFeedURL")!r}')
        short_version = info.get('CFBundleShortVersionString', '')
        bundle_version = info.get('CFBundleVersion', '')
        if not short_version or not bundle_version:
            raise AppcastError('the app has no CFBundleShortVersionString/CFBundleVersion')
        if version and version != short_version:
            raise AppcastError(f'--version {version} but the app in the DMG is {short_version}')
        signature = helper_output(helper, 'sign', key, dmg)
        # Check what we publish the way the app will: with the public key alone.
        helper_output(helper, 'verify', config['publicEDKey'], dmg, signature)
    tag = tag or f'v{short_version}'
    base = (download_base or f'{config["releasesURL"]}/download/{tag}').rstrip('/')
    xml = appcast_xml(title=info.get('CFBundleName', 'VLC Redesign'), version=bundle_version, short_version=short_version,
                      url=f'{base}/{dmg.name}', length=dmg.stat().st_size, signature=signature,
                      minimum_system=info.get('LSMinimumSystemVersion', config['minimumSystemVersion']),
                      release_page=f'{config["releasesURL"]}/tag/{tag}',
                      notes_html=Path(notes).read_text() if notes else None)
    out.write_text(xml)
    return xml


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('dmg', type=Path)
    parser.add_argument('--key', type=Path, required=True, help='file with the base64 Ed25519 seed (never in git)')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--version', help='expected CFBundleShortVersionString (a safety check)')
    parser.add_argument('--tag', help='GitHub release tag (default v<version>)')
    parser.add_argument('--download-base', help='URL the DMG is served from (default: the GitHub release); tests use a local server')
    parser.add_argument('--notes', type=Path, help='short HTML release notes shown in the update window')
    args = parser.parse_args()
    try:
        make_appcast(args.dmg, args.key, args.out, version=args.version, tag=args.tag,
                     download_base=args.download_base, notes=args.notes)
    except (AppcastError, OSError, subprocess.CalledProcessError, KeyError) as error:
        parser.exit(1, f'FAIL: {error}\n')
    print(f'wrote {args.out} for {args.dmg.name}')


if __name__ == '__main__':
    sys.exit(main())
