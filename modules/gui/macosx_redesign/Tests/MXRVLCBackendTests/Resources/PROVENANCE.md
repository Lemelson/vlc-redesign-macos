# Native VLC fixtures

These JSON files were captured from the Objective-C bridge linked against the real VLC core. They are regression inputs for the production Swift decoders; they were not authored as simulated service replies.

- `native-service-fixture.json`: native service fixture v3, recorded after effect setter roundtrips and an actual PNG preview. It preserves Foundation JSON Boolean types and subtitle size/scale values.
- `native-media-effects-fixture.json`: byte-for-byte native service fixture v9, recorded after loading generated AAC media and completing the isolated stereo tone. It includes the composed output, extension, renderer and media-source snapshots. The native run requires both decoded audio and played audio buffers, even with a saved audio-track preference of 2. The final capture contains 48 of each. The main media remains selected. With `MXR_SMOKE_AMEM_VOLUME=1`, its real output callback receives the requested 2.5 volume (250%).
- `native-deinterlace-forced-auto.json`: a real effects snapshot with VLC deinterlace enabled and its default `auto` algorithm. This differs from the automatic enable policy.

The service harness is `module/tests/bridge-smoke.m`. It uses `--ignore-config`, an isolated temporary configuration file, `--no-media-library`, `--no-video`, `--no-plugins-cache`, `--no-metadata-network-access`, and `--no-auto-preparse`. Only selected setting metadata/values and hotkey actions are retained in the JSON. Generated media metadata is test data.

The v9 capture was generated with central bridge/smoke commit `2baac02af302d54da14fd1995be45e636d158385` atop `980d8ec462`, composed helper sources from `f9da69fab1`, and audio-preference helper commits `3a671c02e5` and `b67506af56`. `MXR_SMOKE_APP_OPTIONS=1` requires actual registered app options. Its log confirms configuration alias saving followed by a fresh VLC instance, live Reset All, accented history exclusions, and queue/hotkey/shutdown contracts. The installed GUI module registers options in the module bank; this run does not open an interface or launch a GUI.

Re-capture (writes a new file, never overwrites; the work directory and a `.provenance.json` with the SHA-256 are kept):

```sh
python3 tools/native-tests.py --engine-build "$BUILD" --suite fixture --output NEW.json
```

Historical v9 capture artifacts (temporary files of that run, no longer available; the hashes identify them):

- Original: `/private/tmp/native-service-fixture-v9.json`; SHA-256 `987ccc3a4d1eb8625c7446c95cc9d18f478c788169ff3639a9abbe5aa01c3586`.
- Native log: `/private/tmp/mxr-bridge-smoke-v9.log`; SHA-256 `c1208940b04a32d6966225a30a604e98c7be0b58efdb660044999059b529b31a`.
- Exact compile script: `/private/tmp/mxr-bridge-build-v9.sh`; SHA-256 `58915641aa8f6ac8adde4c415f8ebde09b9285838ee79451648f9963a160d048`.

Personal filesystem children are omitted by the capture harness; provider categories/events remain actual bridge output. The recorded extension catalog is unavailable and renderer items are empty. The fixture makes no claim that external providers are reachable.

Audio is exercised through VLC's dummy or memory output callbacks. These fixtures establish service/decoder contracts and engine buffer delivery, not physical speaker output.
