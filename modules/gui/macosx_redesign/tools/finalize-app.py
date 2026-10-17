#!/usr/bin/env python3
"""Finalize or verify a redesign VLC.app bundle.

Default (dev-sync): re-sign only the --sign paths, regenerate VLC's plugin cache,
sign plugins.dat, then seal the bundle without recursive signing.
--verify-only: change nothing; check identity/containment, that plugins.dat is not
older than any plugin, and that the bundle signature verifies. `make VLC.app`
(extras/package/macosx/codesign.sh) already signs in that order, so the installer
only verifies its output instead of re-signing every Mach-O.
"""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess

def contained(root, path):
    resolved = path.resolve(strict=True)
    if not resolved.is_relative_to(root):
        raise ValueError(f'bundle path escapes application: {path}')
    return resolved


def validate_bundle_paths(app):
    if app.is_symlink():
        raise ValueError('application root must not be a symlink')
    root = app.resolve(strict=True)
    # Validate every link before any signing or cache write. Framework aliases
    # (Versions/Current, executable links) remain valid when they resolve inside.
    for path in app.rglob('*'):
        contained(root, path)
    for relative in ('Contents/Info.plist', 'Contents/MacOS', 'Contents/Frameworks/plugins'):
        contained(root, app / relative)
    cache = app / 'Contents/Frameworks/plugins/plugins.dat'
    if cache.exists() or cache.is_symlink():
        contained(root, cache)
    return root


def guard(app):
    root = validate_bundle_paths(app)
    with (app / 'Contents/Info.plist').open('rb') as source:
        identity_info = plistlib.load(source).get('CFBundleIdentifier')
    if not identity_info or identity_info == 'org.videolan.vlc':
        raise ValueError('refusing stock VLC bundle identity')
    plugins = app / 'Contents/Frameworks/plugins'
    if (plugins / 'libmacosx_plugin.dylib').exists():
        raise ValueError('stock interface must not be packaged with redesign')
    return root, plugins


def check_cache_fresh(plugins):
    cache = plugins / 'plugins.dat'
    if not cache.is_file() or cache.stat().st_size == 0:
        raise ValueError('bundle has no plugins.dat')
    stale = [path.name for path in plugins.rglob('*.dylib') if path.stat().st_mtime_ns > cache.stat().st_mtime_ns]
    if stale:
        raise ValueError('plugin cache predates plugin(s): ' + ', '.join(sorted(stale)))


def verify(app, codesign='codesign'):
    _, plugins = guard(app)
    check_cache_fresh(plugins)
    subprocess.run([codesign, '--verify', '--deep', '--strict', str(app)], check=True)
    print('PASS: redesign identity, fresh plugins.dat, valid bundle signature')


def finalize(app, cachegen, only, codesign='codesign', identity='-'):
    """Incremental update (dev-sync): re-sign only the replaced code, then follow the
    tail of extras/package/macosx/codesign.sh: vlc-cache-gen, sign plugins.dat, seal."""
    root, plugins = guard(app)
    if not only:
        raise ValueError('name at least one replaced file with --sign')
    def sign(path):
        contained(root, path)
        subprocess.run([codesign, '--force', '-s', identity, str(path)], check=True)
    for path in only:
        sign(path)
    def metadata():
        return {str(path.relative_to(plugins)): (path.stat().st_mtime_ns, path.stat().st_size)
                for path in plugins.rglob('*.dylib') if path.is_file()}
    signed_plugins = metadata()
    env = dict(os.environ, VLC_LIB_PATH=str(app / 'Contents/Frameworks'))
    validate_bundle_paths(app)
    subprocess.run([str(cachegen), str(plugins)], check=True, env=env)
    check_cache_fresh(plugins)
    # Contents/Frameworks may only hold signed items: the non-code plugins.dat carries
    # its own (xattr) signature, or the bundle seal fails with "code object is not signed".
    sign(plugins / 'plugins.dat')
    sign(app)
    subprocess.run([codesign, '--verify', '--deep', '--strict', str(app)], check=True)
    if metadata() != signed_plugins:
        raise ValueError('cached plugin changed after cache generation')
    print('PASS: re-signed replaced code, fresh signed plugins.dat, final nonrecursive bundle seal')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('cachegen', type=Path, nargs='?')
    parser.add_argument('--codesign', default='codesign')
    parser.add_argument('--identity', default='-')
    parser.add_argument('--verify-only', action='store_true', help='check an already signed bundle; change nothing')
    parser.add_argument('--sign', type=Path, action='append', help='replaced file to re-sign (repeatable, required unless --verify-only)')
    args = parser.parse_args()
    if not args.verify_only and not args.cachegen:
        parser.error('cachegen is required unless --verify-only')
    try:
        if args.verify_only:
            verify(args.app.absolute(), args.codesign)
        else:
            only = [path.absolute() for path in args.sign or ()]
            finalize(args.app.absolute(), args.cachegen.resolve(), only, args.codesign, args.identity)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'FAIL: {error}\n')
