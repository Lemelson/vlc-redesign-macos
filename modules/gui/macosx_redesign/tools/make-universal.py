#!/usr/bin/env python3
"""Merge an arm64 and an x86_64 VLC Redesign.app into one universal app.

Usage: tools/make-universal.py arm64.app x86_64.app out-dir --cachegen <vlc-cache-gen>

Both apps must come from the same source and configuration: the same files, the same bytes in
every file that is not code. Each Mach-O pair is joined with `lipo -create`; any other difference
is reported and nothing is written, with two exceptions that are listed in the output:
- a plugin built for one architecture only (libdeinterlace_x86_plugin, libi420_rgb_sse2_plugin,
  libdeinterlace_sve_plugin: SIMD variants of plugins that have a portable version) is left out.
  Kept, the other architecture tries to load it from plugins.dat or the plugin folder and logs
  "cannot load plug-in ... incompatible architecture" on every launch;
- arch-independent files that VideoLAN's per-architecture contrib builders package differently
  (Sparkle.framework resources, libbluray's .jar files, the skins2 .vlt archive) are taken from
  the arm64 app. The result is re-signed ad hoc in the order of
extras/package/macosx/codesign.sh through finalize-app.py (code first, then a fresh plugins.dat,
then the bundle seal) and verified: both architectures in every binary, no slice newer than LSMinimumSystemVersion
(check-minimum-macos.py), `finalize-app.py
--verify-only`, `codesign --verify --deep --strict`.

The cache generator may be either build's `bin/vlc-cache-gen` (an x86_64 one runs under
Rosetta and so loads every plugin's Intel slice); plugins.dat has the same layout on both 64-bit
little-endian architectures. Writes `<out-dir>/VLC Redesign.app`; an existing one is replaced
only when it carries the redesign identity.
"""
import argparse
import importlib.util
from fnmatch import fnmatch
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

TOOLS = Path(__file__).resolve().parent
IDENTITY = 'io.github.lemelson.vlc-redesign'
ARCHS = {'arm64', 'x86_64'}
APP_NAME = 'VLC Redesign.app'
MACHO_MAGICS = {bytes.fromhex(magic) for magic in ('feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca')}
# Rewritten after the merge: every signature and the plugin cache (it records plugin sizes).
REGENERATED = ('_CodeSignature', 'plugins.dat')
PLUGINS = Path('Contents/Frameworks/plugins')
# Same contrib version, built and archived on another machine: embedded build machine, SDK or zip
# timestamps differ. Code in these paths is still merged with lipo like any other Mach-O.
BUILDER_DIFFERENCES = ('Contents/Frameworks/Sparkle.framework/*', '*.jar', '*.vlt')


def regenerated(relative):
    return any(part in REGENERATED for part in relative.parts)


def is_macho(path):
    with path.open('rb') as source:
        return source.read(4) in MACHO_MAGICS


def check_app(app, label):
    if app.is_symlink() or not app.is_dir():
        raise ValueError(f'{label}: not an application directory: {app}')
    with (app / 'Contents/Info.plist').open('rb') as source:
        identity = plistlib.load(source).get('CFBundleIdentifier')
    if identity != IDENTITY:
        raise ValueError(f'{label}: unexpected application identity {identity!r} (expected {IDENTITY})')
    if not (app / 'Contents/Frameworks/plugins/libmacosx_redesign_plugin.dylib').is_file():
        raise ValueError(f'{label}: missing the redesign interface plugin')


def inventory(app):
    """Relative path -> ('dir'|'file'|'link', link target or None), signatures and cache excluded."""
    entries = {}
    for path in app.rglob('*'):
        relative = path.relative_to(app)
        if regenerated(relative):
            continue
        if path.is_symlink():
            entries[relative] = ('link', os.readlink(path))
        elif path.is_dir():
            entries[relative] = ('dir', None)
        elif path.is_file():
            entries[relative] = ('file', None)
        else:
            raise ValueError(f'unsupported file type: {path}')
    return entries


def archs(path):
    result = subprocess.run(['lipo', '-archs', str(path)], capture_output=True, text=True, check=True)
    return set(result.stdout.split())


def thin(path, arch, scratch):
    """The single-architecture slice of path (path itself when it is already thin)."""
    found = archs(path)
    if arch not in found:
        raise ValueError(f'{path} has no {arch} slice ({" ".join(sorted(found))})')
    if found == {arch}:
        return path
    handle, name = tempfile.mkstemp(dir=scratch, suffix='.' + arch)
    os.close(handle)
    out = Path(name)
    subprocess.run(['lipo', str(path), '-thin', arch, '-output', str(out)], check=True)
    return out


def single_arch_plugin(app, relative, entries):
    return (entries[relative][0] == 'file' and relative.is_relative_to(PLUGINS)
            and is_macho(app / relative))


def differences(arm, intel):
    """Every reason the two apps cannot be merged, the Mach-O files to join, the plugins of one
    architecture (relative path -> source app) and notes on accepted differences."""
    left, right = inventory(arm), inventory(intel)
    problems, notes, single = [], [], {}
    for path in sorted(left.keys() - right.keys()):
        if single_arch_plugin(arm, path, left):
            single[path] = arm
            notes.append(f'arm64-only plugin left out: {path}')
        else:
            problems.append(f'only in the arm64 app: {path}')
    for path in sorted(right.keys() - left.keys()):
        if single_arch_plugin(intel, path, right):
            single[path] = intel
            notes.append(f'x86_64-only plugin left out: {path}')
        else:
            problems.append(f'only in the x86_64 app: {path}')
    binaries = []
    for relative in sorted(left.keys() & right.keys()):
        kind, target = left[relative]
        if (kind, target) != right[relative]:
            problems.append(f'different kind or link target: {relative}')
            continue
        if kind != 'file':
            continue
        a, b = arm / relative, intel / relative
        code = is_macho(a), is_macho(b)
        if code == (True, True):
            binaries.append(relative)
        elif code != (False, False):
            problems.append(f'code in one app only: {relative}')
        elif a.read_bytes() != b.read_bytes():
            if any(fnmatch(str(relative), pattern) for pattern in BUILDER_DIFFERENCES):
                notes.append(f'contrib builder difference, arm64 copy kept: {relative}')
            else:
                problems.append(f'different contents: {relative}')
    return problems, binaries, single, notes


def signing_order(app):
    """What extras/package/macosx/codesign.sh signs before plugins.dat and the bundle seal."""
    frameworks = app / 'Contents/Frameworks'
    order = []
    sparkle = frameworks / 'Sparkle.framework'
    if sparkle.is_dir():
        # Sparkle 2 (codesign.sh: Autoupdate, Updater.app, the framework). Also any XPC service a newer
        # Sparkle carries, innermost first, so the framework seal never meets unsigned code.
        for version in sorted(path for path in (sparkle / 'Versions').iterdir() if not path.is_symlink()):
            loose = [path for path in version.iterdir()
                     if path.is_file() and path.name != 'Sparkle' and is_macho(path)]
            nested = [path for path in version.rglob('*') if path.suffix in ('.app', '.xpc') and path.is_dir()]
            order += sorted(loose) + sorted(nested, key=lambda path: (-len(path.parts), path))
        order.append(sparkle)
    order += sorted(path for path in (frameworks / 'plugins').rglob('*') if path.suffix in ('.dylib', '.jar'))
    order += sorted(path for path in frameworks.glob('*.dylib') if not path.is_symlink())
    if (frameworks / 'lua').is_dir():
        order += sorted(path for path in (frameworks / 'lua').rglob('*') if path.is_file() and not path.is_symlink())
    order += sorted(path for path in (app / 'Contents/MacOS').iterdir()
                    if path.is_file() and path.name != main_executable(app))  # the seal signs the main one
    return [path for path in order if path.exists()]


def main_executable(app):
    with (app / 'Contents/Info.plist').open('rb') as source:
        return plistlib.load(source).get('CFBundleExecutable', '')


def verify_archs(app):
    wrong = []
    for path in sorted(app.rglob('*')):
        if path.is_file() and not path.is_symlink() and is_macho(path):
            found = archs(path)
            if found != ARCHS:
                wrong.append(f'{path.relative_to(app)}: {" ".join(sorted(found)) or "none"}')
    if wrong:
        raise ValueError('not universal:\n  ' + '\n  '.join(wrong))


def verify_system_swift(app):
    """No slice may load the toolchain's back-deployment Swift libraries (@rpath/libswift*.dylib):
    the app does not ship them. Xcode 27's linker adds @rpath/libswiftCoreMedia.dylib to x86_64 code
    that links CoreMedia for macOS < 10.15, so an engine configured for 10.13 loses avcodec,
    VideoToolbox and other plugins on Intel (BUILD.md, release recipe)."""
    wrong = []
    for path in sorted(app.rglob('*')):
        if path.is_file() and not path.is_symlink() and is_macho(path):
            for arch in sorted(archs(path)):
                links = subprocess.run(['otool', '-arch', arch, '-L', str(path)], capture_output=True,
                                       text=True, check=True).stdout.splitlines()[1:]
                if any(line.strip().startswith('@rpath/libswift') for line in links):
                    wrong.append(f'{path.relative_to(app)} ({arch})')
    if wrong:
        raise ValueError('links back-deployed Swift libraries (@rpath/libswift*); configure that engine with '
                         '--with-macosx-version-min=11.0:\n  ' + '\n  '.join(wrong))


def verify_minimum_macos(app):
    """check-minimum-macos.py: no slice may need a newer macOS than LSMinimumSystemVersion."""
    spec = importlib.util.spec_from_file_location('check_minimum_macos', TOOLS / 'check-minimum-macos.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.check(app)


def make_universal(arm, intel, out_dir, cachegen, codesign='codesign'):
    check_app(arm, 'arm64 app')
    check_app(intel, 'x86_64 app')
    problems, binaries, single, notes = differences(arm, intel)
    if problems:
        raise ValueError('the apps differ beyond their code:\n  ' + '\n  '.join(problems))
    for note in notes:
        print('note:', note)
    out_dir.mkdir(parents=True, exist_ok=True)
    final = out_dir / APP_NAME
    if final.exists() or final.is_symlink():
        check_app(final, 'existing output')
    with tempfile.TemporaryDirectory(prefix='.vlc-redesign-universal.', dir=out_dir) as scratch:
        scratch = Path(scratch)
        stage = scratch / APP_NAME
        subprocess.run(['ditto', str(arm), str(stage)], check=True)
        for relative in binaries:
            target = stage / relative
            mode = target.stat().st_mode
            merged = scratch / 'merged'
            subprocess.run(['lipo', '-create', str(thin(arm / relative, 'arm64', scratch)),
                            str(thin(intel / relative, 'x86_64', scratch)), '-output', str(merged)], check=True)
            os.replace(merged, target)
            os.chmod(target, mode)
        for relative in single:
            (stage / relative).unlink(missing_ok=True)
        verify_archs(stage)
        verify_system_swift(stage)
        verify_minimum_macos(stage)
        signs = []
        for path in signing_order(stage):
            signs += ['--sign', str(path)]
        finalize = [sys.executable, str(TOOLS / 'finalize-app.py'), '--codesign', codesign]
        subprocess.run(finalize + [str(stage), str(cachegen)] + signs, check=True)
        subprocess.run(finalize + ['--verify-only', str(stage)], check=True)
        if final.exists():
            shutil.rmtree(final)
        os.rename(stage, final)
    print(f'PASS: {len(binaries)} binaries merged ({" + ".join(sorted(ARCHS))}), signed and verified: {final}')
    return final


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('arm64_app', type=Path)
    parser.add_argument('x86_64_app', type=Path)
    parser.add_argument('out_dir', type=Path)
    parser.add_argument('--cachegen', type=Path, required=True, help="a build's bin/vlc-cache-gen")
    parser.add_argument('--codesign', default='codesign')
    args = parser.parse_args()
    try:
        make_universal(args.arm64_app.absolute(), args.x86_64_app.absolute(), args.out_dir.absolute(),
                       args.cachegen.absolute(), args.codesign)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'FAIL: {error}\n')
