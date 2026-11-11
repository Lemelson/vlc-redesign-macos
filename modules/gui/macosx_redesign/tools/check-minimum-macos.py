#!/usr/bin/env python3
"""Refuse an app in which any Mach-O slice needs a newer macOS than the app promises.

Usage: tools/check-minimum-macos.py <app> [--minimum 14.0]

The promise is the app's LSMinimumSystemVersion (or --minimum). Every Mach-O file in the bundle
(the main executable, frameworks, plugins, helpers), every architecture slice of it, is read with
`otool -l`: the macOS minimum of LC_BUILD_VERSION (platform 1, macOS) or LC_VERSION_MIN_MACOSX must
not be newer. A slice with no macOS minimum at all is refused too.

1.0.0 and 1.0.1 shipped with every Objective-C binary at minos 27.2, the SDK they were built with
(libtool's Objective-C tag dropped -mmacosx-version-min from OBJC; configure.m4, GitHub issue #2):
Finder showed the app as unsupported on every macOS before 27.2 although Info.plist said 14.0.
make-universal.py and package-dmg.sh run this check, so such a build can no longer be packaged.
"""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess
import sys

MACHO_MAGICS = {bytes.fromhex(magic) for magic in ('feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca')}
PLATFORM_MACOS = '1'


def parse_version(text):
    if not re.fullmatch(r'\d+(\.\d+){0,2}', text):
        raise ValueError(f'not a macOS version: {text!r}')
    parts = [int(part) for part in text.split('.')]
    return tuple(parts + [0] * (3 - len(parts)))


def is_macho(path):
    with path.open('rb') as source:
        return source.read(4) in MACHO_MAGICS


def slice_minimums(path, arch):
    """macOS minimums named by one slice's load commands (normally exactly one)."""
    output = subprocess.run(['otool', '-arch', arch, '-l', str(path)], capture_output=True, text=True,
                            check=True).stdout
    found = []
    for command in re.split(r'\nLoad command \d+\n', output):
        fields = dict(re.findall(r'^\s*(\w+) (\S+)', command, re.MULTILINE))
        if fields.get('cmd') == 'LC_BUILD_VERSION' and fields.get('platform') == PLATFORM_MACOS:
            found.append(fields['minos'])
        elif fields.get('cmd') == 'LC_VERSION_MIN_MACOSX':
            found.append(fields['version'])
    return found


def archs(path):
    return subprocess.run(['lipo', '-archs', str(path)], capture_output=True, text=True,
                          check=True).stdout.split()


def app_minimum(app):
    with (app / 'Contents/Info.plist').open('rb') as source:
        value = plistlib.load(source).get('LSMinimumSystemVersion')
    if not value:
        raise ValueError(f'{app}: Info.plist has no LSMinimumSystemVersion')
    return value


def check(app, minimum=None):
    """Return the number of slices checked; raise ValueError naming every slice that needs more."""
    minimum = minimum or app_minimum(app)
    limit = parse_version(minimum)
    wrong, checked = [], 0
    for path in sorted(app.rglob('*')):
        if not path.is_file() or path.is_symlink() or not is_macho(path):
            continue
        for arch in archs(path):
            checked += 1
            versions = slice_minimums(path, arch)
            name = f'{path.relative_to(app)} ({arch})'
            if not versions:
                wrong.append(f'{name}: no macOS minimum')
            elif any(parse_version(version) > limit for version in versions):
                wrong.append(f'{name}: minos {", ".join(versions)}')
    if wrong:
        raise ValueError(f'{len(wrong)} slice(s) need a newer macOS than {minimum}:\n  ' + '\n  '.join(wrong))
    return checked


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('app', type=Path)
    parser.add_argument('--minimum', help='default: the app\'s LSMinimumSystemVersion')
    args = parser.parse_args()
    try:
        minimum = args.minimum or app_minimum(args.app)
        count = check(args.app, minimum)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'FAIL: {error}\n')
    print(f'PASS: all {count} Mach-O slices run on macOS {minimum}')
