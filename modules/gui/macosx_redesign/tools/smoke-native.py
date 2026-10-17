#!/usr/bin/env python3
"""Run a real VLC start/play/next/quit smoke test from an isolated app bundle."""
import pathlib
import plistlib
import subprocess
import sys

if len(sys.argv) < 4:
    raise SystemExit(f"usage: {sys.argv[0]} VLC.app log media [media ...]")
app = pathlib.Path(sys.argv[1]).resolve()
log = pathlib.Path(sys.argv[2]).resolve()
with (app / "Contents/Info.plist").open("rb") as source:
    bundle_id = plistlib.load(source).get("CFBundleIdentifier")
if not bundle_id or bundle_id == "org.videolan.vlc":
    raise SystemExit("refusing to launch a stock VLC bundle identity")
plugins = app / "Contents/Frameworks/plugins"
if (plugins / "libmacosx_plugin.dylib").exists():
    raise SystemExit("stock interface is present in the redesign bundle")
command = [str(app / "Contents/MacOS/VLC"), "--verbose=2",
           "--no-media-library", "--run-time=4", "--play-and-exit", *sys.argv[3:]]
with log.open("wb") as output:
    try:
        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=45)
    except subprocess.TimeoutExpired:
        raise SystemExit(f"FAIL: start/play/quit exceeded 45 seconds; inspect {log}")
text = log.read_text(errors="replace")
required = ['using interface module "macosx_redesign"',
            'using vout window module "macosx_redesign"',
            'using vout display module "samplebufferdisplay"',
            'using video decoder module "videotoolbox"',
            'using audio output module "auhal"', 'Received first picture', 'exiting',
            'macosx_redesign interface closed']
if any(pathlib.Path(media).with_suffix(".srt").is_file() for media in sys.argv[3:]):
    required += ['autodetected subtitle:', 'using spu decoder module "subsdec"']
missing = [message for message in required if message not in text]
if text.count('Received first picture') < len(sys.argv[3:]):
    missing.append('first video picture for every playlist item')
if 'stale plugins cache' in text:
    missing.append('fresh plugin cache (stale entries were logged)')
if result.returncode or missing:
    raise SystemExit(f"FAIL: exit={result.returncode}, missing={missing}; inspect {log}")
print(f"PASS: native interface, native video surface, hardware video, audio, clean exit; {log}")
