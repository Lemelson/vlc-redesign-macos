#!/usr/bin/env python3
"""Compile actual bridge contracts against an explicit configured VLC build.

Default contracts run parsers/validation and the schema gate, without playback.
Library, fixture capture, audio/media/extension runtime suites are explicit gates;
all generated files and runtime data stay under a fresh temporary directory,
removed after a passing run unless --keep is given.
No VLC build, app bundle, installation or user configuration is modified.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

PACKAGE = Path(__file__).resolve().parent.parent
REPO = PACKAGE.parents[2]
MODULE = PACKAGE / 'module'
BRIDGE = MODULE / 'bridge'
BRIDGE_KEYS = PACKAGE / 'Sources/MXRBridgeAPI/MXRBridgeKeys.m'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine-build', required=True, type=Path)
    parser.add_argument('--suite', choices=['contracts', 'schema', 'fixture', 'library', 'audio', 'media', 'extensions', 'subtitle-runtime', 'build-runtime', 'headless-regressions'], default='contracts')
    parser.add_argument('--output', type=Path, help='New fixture JSON path (fixture suite only; never overwrites)')
    parser.add_argument('--keep', action='store_true', help='keep the temporary work directory after a passing run')
    args = parser.parse_args()
    engine = args.engine_build.resolve()
    for required in ('config.h', 'src/.libs/libvlccore.dylib', 'modules/.libs'):
        if not (engine / required).exists():
            parser.error(f'not a configured/built VLC engine: missing {engine / required}')
    # Every suite indexes its bank (run_suite); skipping it silently brings the shutdown flake back.
    if not (engine / 'bin/vlc-cache-gen').exists():
        parser.error(f'missing {engine / "bin/vlc-cache-gen"}: the plugin bank must be indexed '
                     f'(plugins.dat); build it with make -C {engine / "bin"} vlc-cache-gen')
    if args.suite == 'fixture' and (not args.output or args.output.exists()):
        parser.error('fixture capture requires a new --output path')
    work = Path(tempfile.mkdtemp(prefix='mxr-native-contract-'))
    passed = False
    try:
        run_suite(args, parser, engine, work)
        passed = True
    finally:
        # A passing run leaves nothing behind; failures (and fixture captures,
        # whose provenance points at the work dir) keep their evidence.
        if passed and not args.keep and args.suite != 'fixture':
            shutil.rmtree(work, ignore_errors=True)
        else:
            print(f'Native evidence retained at {work}', flush=True)
    print(f'PASS: {args.suite}')


def run_suite(args, parser, engine, work):
    plugins = work / 'plugins'
    plugins.mkdir()
    # Parsers/schema do not need the GUI plugin. Fixture capture opts in to app
    # registrations; class aliases below prevent Objective-C class collisions.
    for path in (engine / 'modules/.libs').glob('*.dylib'):
        if args.suite == 'extensions' and path.name not in ('liblua_plugin.dylib', 'libadummy_plugin.dylib'):
            continue
        if 'macosx_redesign' not in path.name or args.suite == 'fixture':
            (plugins / path.name).symlink_to(path)
    env = {key: value for key, value in os.environ.items()
           if key not in ('CC', 'CFLAGS', 'CPPFLAGS', 'OBJCFLAGS', 'LDFLAGS', 'SDKROOT', 'MACOSX_DEPLOYMENT_TARGET')}
    for name in ('data', 'user', 'config', 'cache', 'module-cache'):
        (work / name).mkdir()
    env.update(DYLD_LIBRARY_PATH=str(engine / 'src/.libs'), VLC_PLUGIN_PATH=str(plugins),
               VLC_LIB_PATH=str(engine / 'modules'), VLC_LIBEXEC_PATH=str(engine / 'libexec'),
               VLC_DATA_PATH=str(work / 'data'), VLC_USERDATA_PATH=str(work / 'user'),
               XDG_CONFIG_HOME=str(work / 'config'), XDG_CACHE_HOME=str(work / 'cache'),
               CLANG_MODULE_CACHE_PATH=str(work / 'module-cache'),
               # Harnesses write deadline call graphs here (MXRNativeTestDiagnostics.h);
               # the work dir is kept after a failure, so the evidence survives.
               MXR_NATIVE_EVIDENCE_DIR=str(work))
    if args.suite == 'extensions':
        # Empty default bank plus the two explicit plugins above: no UI, device,
        # discovery or network plugins are available to this local-file gate.
        (work / 'modules/plugins').mkdir(parents=True)
        env['VLC_LIB_PATH'] = str(work / 'modules')
    def run(command, **kwargs):
        print('+ ' + ' '.join(map(str, command)), flush=True)
        began = time.monotonic()
        try:
            return subprocess.run(list(map(str, command)), env=env, check=True, timeout=120, **kwargs)
        finally:
            print(f'  ({time.monotonic() - began:.1f} s) {Path(str(command[0])).name}', flush=True)
    # Index the bank like the shipped bundle (plugins.dat, install-app.sh). Without the cache
    # the core dlopens every plugin at start and module_EndBank dlcloses all of them at
    # cleanup; dyld's per-unload bookkeeping makes that 1.5-2 s idle, >8 s under load.
    cache_gen = engine / 'bin/vlc-cache-gen'
    run([cache_gen, plugins])
    if not (plugins / 'plugins.dat').is_file():
        raise SystemExit(f'error: {cache_gen.name} did not write {plugins / "plugins.dat"}')
    flags = ['xcrun', 'clang', '-fobjc-arc', '-fobjc-exceptions', '-mmacosx-version-min=14.0',
             '-DHAVE_CONFIG_H', '-DMODULE_STRING="macosx_redesign"']
    for include in (engine, engine / 'include', REPO, REPO / 'include', REPO / 'lib', MODULE, BRIDGE, PACKAGE / 'Sources/MXRBridgeAPI/include'):
        flags += ['-I' + str(include)]
    link = ['-L' + str(engine / 'src/.libs'), '-lvlccore', '-framework', 'Cocoa',
            '-framework', 'AVFoundation', '-framework', 'AudioToolbox', '-framework', 'CoreMedia',
            '-framework', 'QuartzCore', '-framework', 'AVKit']
    # The real plugin gets vlc_module_name from its vlc_module_begin descriptor
    # (vlc_plugin.h); bridge helpers that log with msg_* need it in every harness.
    # Weak, so a harness that defines its own still links.
    module_name = work / 'harness-module-name.c'
    module_name.write_text('__attribute__((weak)) const char vlc_module_name[] = "macosx_redesign";\n')
    def compile(name, sources, aliases=False):
        extra = []
        if aliases:
            classes = set()
            for path in BRIDGE.glob('*'):
                if path.suffix in ('.h', '.m'):
                    classes.update(re.findall(r'@interface\s+(MXR\w+)', path.read_text()))
            for name_ in sorted(classes):
                extra += [f'-D{name_}=Contract{name_}']
        output = work / name
        # Typed service/command constants are shared by every native helper consumer.
        sources = list(dict.fromkeys([*sources, BRIDGE_KEYS, module_name]))
        run(flags + extra + [str(path) for path in sources] + link + ['-o', str(output)])
        return output
    suite = args.suite
    if suite == 'build-runtime':
        compile('library-contract', [MODULE / 'tests/library-contract.m', BRIDGE / 'MXRLibraryServices.m'])
        for name, helper in [('audio', 'MXRAudioServices'), ('audio-preferences', 'MXRAudioPreferenceServices'),
                             ('media', 'MXRMediaServices'), ('extensions', 'MXRExtensionServices')]:
            source = 'MXRMediaServices' if helper == 'MXRExtensionServices' else helper
            compile(name, [BRIDGE / (source + '.m'), BRIDGE / 'tests' / (helper + 'RuntimeTests.m')])
        helpers = [path for path in BRIDGE.glob('*.m') if path.name not in ('MXRPlayerBridge.m', 'MXRInterfaceBridge.m')]
        compile('bridge-smoke', [MODULE / 'tests/bridge-smoke.m'] + sorted(helpers), aliases=True)
    if suite in ('contracts', 'schema'):
        dump = compile('dumpconfig', [MODULE / 'tests/dumpconfig.m'])
        schema = work / 'schema.json'
        with schema.open('w') as out:
            run([dump], stdout=out)
        run(['python3', PACKAGE / 'tools/schema-drift.py', schema])
    if suite == 'contracts':
        run([compile('media-contract', [BRIDGE / 'MXRMediaServices.m', BRIDGE / 'tests/MXRMediaServicesTests.m'])])
        run([compile('subtitle-parser', [BRIDGE / 'MXRSubtitleCueServices.m', MODULE / 'tests/subtitle-cues.m'])])
    if suite in ('contracts', 'headless-regressions'):
        settings = work / 'settings-inheritance'
        run(['xcrun', 'clang', '-DHAVE_CONFIG_H', '-I' + str(engine), '-I' + str(REPO / 'include'),
             BRIDGE / 'tests/MXRSettingsInheritanceTests.c', '-L' + str(engine / 'src/.libs'), '-lvlccore',
             '-Wl,-rpath,' + str(engine / 'src/.libs'), '-o', settings])
        # This inheritance contract needs only the core's dummy in-process objects.
        # Prevent unrelated bank plugins from being loaded by this particular test.
        inherited_plugins = env['VLC_PLUGIN_PATH']
        empty_plugins = work / 'empty-plugins'
        empty_plugins.mkdir()
        env['VLC_PLUGIN_PATH'] = str(empty_plugins)
        try:
            run([settings])
        finally:
            env['VLC_PLUGIN_PATH'] = inherited_plugins
        for name, test in [('library-lifetime', 'NativeLibraryLifetimeRegression.m'),
                           ('library-import-sort', 'NativeLibraryImportSortRegression.m'),
                           ('library-playlist-order', 'NativeLibraryPlaylistOrderRegression.m')]:
            binary = work / name
            run(flags + ['-fblocks', '-D__PLUGIN__', '-I' + str(REPO / 'compat'),
                         str(BRIDGE / 'MXRLibraryServices.m'), str(PACKAGE / 'Tests' / test), str(BRIDGE_KEYS),
                         '-framework', 'Foundation', '-Wl,-undefined,dynamic_lookup', '-o', str(binary)])
            run([binary])
        swift_cache = work / 'swift-module-cache'
        swift_cache.mkdir()
        for name, source, test in [('magnification-policy', 'MXRFullscreenMagnification.swift', 'MagnificationPolicyTests.swift'),
                                   ('now-playing-clock', 'MXRNowPlayingClockGate.swift', 'NowPlayingClockTests.swift')]:
            binary = work / name
            run(['xcrun', 'swiftc', '-module-cache-path', swift_cache, '-parse-as-library',
                 PACKAGE / 'Sources/MXRPlugin' / source,
                 PACKAGE / 'Tests/MXRNativeInputTests' / test, '-o', binary])
            run([binary])
    if suite == 'library':
        if not shutil.which('ffmpeg'): parser.error('library gate requires ffmpeg')
        run([compile('library-contract', [MODULE / 'tests/library-contract.m', BRIDGE / 'MXRLibraryServices.m'])])
        # Edit/Add Audio Tracks: library soundtracks become selected audio slaves of a real input (D039).
        run([compile('library-soundtrack', [PACKAGE / 'Tests/NativeLibrarySoundtrackRuntime.m', BRIDGE / 'MXRLibraryServices.m'])])
    if suite == 'subtitle-runtime':
        binary = compile('subtitle-runtime', [BRIDGE / 'MXRSubtitleCueServices.m', MODULE / 'tests/subtitle-cues.m'])
        run([binary, '--native'])
        run([binary, '--native-live'])
    if suite == 'extensions':
        run([compile('extensions', [BRIDGE / 'MXRMediaServices.m', BRIDGE / 'tests/MXRExtensionServicesRuntimeTests.m'])])
        run([compile('extension-dialogs', [BRIDGE / 'MXRMediaServices.m', BRIDGE / 'MXRDialogServices.m', BRIDGE / 'tests/MXRExtensionDialogsRuntimeTests.m'])])
    if suite in ('fixture', 'audio', 'media'):
        if not shutil.which('ffmpeg'): parser.error(f'{suite} gate requires ffmpeg')
        audio = compile('audio', [BRIDGE / 'MXRAudioServices.m', BRIDGE / 'tests/MXRAudioServicesRuntimeTests.m'])
        wav, aac = work / 'tone.wav', work / 'tone.m4a'
        run([audio, '--write-tone', wav])
        run(['ffmpeg', '-v', 'error', '-i', wav, '-metadata', 'artist=Bridge Artist', '-metadata', 'album=Bridge Album', '-c:a', 'aac', aac])
        if suite == 'audio':
            run([audio, wav, aac])
            preference = compile('audio-preferences', [BRIDGE / 'MXRAudioPreferenceServices.m', BRIDGE / 'tests/MXRAudioPreferenceServicesRuntimeTests.m'])
            run([preference, wav])
        if suite == 'media':
            # The runtime harness checks produced files with ffprobe (valid container, durations).
            if not shutil.which('ffprobe'): parser.error('media gate requires ffprobe on PATH')
            ts = work / 'input.ts'
            # 25 fps with audio: the rate at which transcoding audio and video together used to abort (D036).
            run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc=size=320x180:rate=25:duration=4',
                 '-i', wav, '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-t', '4', '-f', 'mpegts', ts])
            destination = work / 'output'
            destination.mkdir()
            marker = work / 'extension-triggered'
            extension = work / 'user/lua/extensions/runtime-trigger.lua'
            extension.parent.mkdir(parents=True)
            extension.write_text(
                'function descriptor() return {title="MXR runtime trigger", capabilities={"trigger"}} end\n'
                'function trigger() local f=assert(io.open(' + json.dumps(str(marker)) +
                ',"w")); f:write("unexpected execution"); f:close() end\n')
            run([compile('media-runtime', [BRIDGE / 'MXRMediaServices.m', BRIDGE / 'tests/MXRMediaServicesRuntimeTests.m']), ts, destination, marker])
            # Subtitle safe inset (live run 1): a dummy vout's real "sub-margin" under UI overlays.
            run([compile('effects-runtime', [BRIDGE / 'MXREffectsServices.m', BRIDGE / 'tests/MXREffectsServicesRuntimeTests.m']), ts])
        if suite == 'fixture':
            helpers = [path for path in BRIDGE.glob('*.m') if path.name not in ('MXRPlayerBridge.m', 'MXRInterfaceBridge.m')]
            binary = compile('bridge-smoke', [MODULE / 'tests/bridge-smoke.m'] + sorted(helpers), aliases=True)
            fixture = work / 'fixture.json'
            env.update(MXR_SMOKE_AMEM_VOLUME='1', MXR_SMOKE_APP_OPTIONS='1')
            video = work / 'preview.mp4'
            run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc=size=320x180:rate=10:duration=4',
                 '-pix_fmt', 'yuv420p', '-c:v', 'libx264', video])
            run([binary, fixture, video, aac])
            args.output.parent.mkdir(parents=True, exist_ok=True)
            with args.output.open('xb') as target:
                target.write(fixture.read_bytes())
            provenance = {'engineBuild': str(engine), 'sourceTree': str(REPO),
                          'sha256': hashlib.sha256(fixture.read_bytes()).hexdigest(), 'work': str(work)}
            with args.output.with_suffix('.provenance.json').open('x') as target:
                target.write(json.dumps(provenance, indent=2) + '\n')


if __name__ == '__main__':
    main()
