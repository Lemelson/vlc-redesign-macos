# Native audio service verification

Run from `modules/gui/macosx_redesign` against a configured, built engine (`$BUILD` is its
build directory; its `config.h` and `libvlccore` must belong to the same build):

```sh
python3 tools/native-tests.py --engine-build "$BUILD" --suite audio
```

The runner compiles `MXRAudioServices.m` with `MXRAudioServicesRuntimeTests.m`, writes the
stereo tone, encodes it to AAC with `ffmpeg`, and runs the harness with an isolated plug-in
directory and user data under a fresh temporary directory (kept only on failure or `--keep`).
The same suite also runs the audio-preference harness.

The runner's plug-in directory holds symlinks to the build's dylibs, so `.dSYM` bundles are
never treated as plug-ins. Generated media stays outside Git.
The runtime requires VLC's normal clock support; an engine built with the Darwin `sysctl`
clock fallback cannot run inside a sandbox which rejects `KERN_BOOTTIME`.

The harness asserts `ignore-config` on the real engine, uses `adummy`, and checks:

- The generated 2.5-second stereo PCM contains only a left signal, silence, then only a right
  signal, with 10 ms fades and a peak below 0.25 full scale.
- WAV and AAC are decoded into the requested number of normalized mono peak bins, with actual
  duration and silence intervals. Modified file timestamps invalidate the cache.
- Remote URLs and oversized requests return errors. Cache and active PCM-reader cancellation
  never return partial samples. A sparse long-duration WAV exercises cancellation after samples
  have actually been read, without allocating the complete PCM data.
- A separate VLC playlist decodes the tone and submits buffers to audio output. Inherited
  start/stop/run-time, playback speed, non-existent preferred track/id/language/resampler, and
  disabled statistics do not trim or silence the test. The generated WAV explicitly uses its
  first track, the WAV demuxer and PCM decoder, with local statistics for output verification.
  Finishing without decoded and played audio buffers returns an error. The main playlist, paused media,
  stereo mode, volume, and rate are preserved.
- Tone cancellation, shutdown during preparation, and off-main worker disposal complete once.

This is headless engine proof. Physical left/right audibility and device routing require
hardware verification. The auhal device-persistence preservation has source review evidence;
dummy output cannot exercise auhal's close path.

Waveforms support readable local files with audio that AVFoundation can decode and a finite
positive duration. WAV and AAC are verified. Other containers/codecs may return an unsupported
or decoder error; the optional Swift waveform adapter returns nil quietly. Audio is read in
mono float PCM chunks, with at most 4096 peak bins and 24 cached results keyed by URL, file size,
modification time, and bin count. No source PCM file is loaded into memory in full.
