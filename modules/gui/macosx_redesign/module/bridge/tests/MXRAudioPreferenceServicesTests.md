# Native audio preference verification

The helper binds the app's audio switches to VLC's existing `audio-filter` chain.
`availabilityForOption:` checks the actual module bank and required configuration;
missing modules and bit-exact bypass return unavailable. The settings bridge calls
`applyOption:value:error:` before persisting the app flag and merges `snapshotValues`
over app defaults. Snapshots read the held current audio output, falling back to
config when playback has not created one. Existing effects therefore appear in both
the Effects panel and Settings. After an Effects `setAudioEffects` command succeeds,
the central bridge calls `reconcileAfterEffectsChange` to persist those actual
states in the app opt-ins. Disabled effects then stay disabled on the next startup,
and manual compressor edits clear a stale night-mode opt-in.

After `config_ResetAll`, the central bridge calls `resetAfterConfigurationReset`.
This discards Night restoration state and applies the real newly reset filter
parameters and chain to the held output. It does not restore the pre-reset custom
compressor or leave cached equalizer gains behind. Stereo/mix and other output
preferences are handled by the central reset service.

Enabling Equalizer supplies nonempty gains from the configured bands or VLC's
actual named preset table. It preserves separate live and configured preamp values;
filter availability alone does not bypass Equalizer's native initialization rules.

| App option suffix | VLC filter or parameters |
| --- | --- |
| normvol | normvol, using norm-max-level |
| equalizer | equalizer |
| compressor | compressor |
| stereo-widen | stereo_widen |
| chorus | chorus_flanger |
| karaoke | karaoke |
| spatial-audio / spatial-mode=headphones | headphone (headphone_channel_mixer plug-in file) |
| spatial-audio / spatial-mode=spatializer | spatializer |
| night-mode | compressor preset below |

Night mode uses RMS/peak 0.2, attack 5 ms, release 200 ms, threshold -20 dB,
ratio 8:1, knee 6 dB and makeup gain 6 dB through `compressor-rms-peak`,
`compressor-attack`, `compressor-release`, `compressor-threshold`, `compressor-ratio`,
`compressor-knee` and `compressor-makeup-gain`. Turning it off restores the prior
parameters in the current session if the preset has not been manually edited,
and preserves a separately enabled compressor. Manual parameter edits make the
night-mode snapshot false and survive turning night mode off. A persisted night
mode reapplies its preset on startup; the prior session's custom parameters are
not separately serialized. Disabling the Compressor switch also disables night
mode. The night-mode snapshot requires an active night-mode request, a compressor
in the actual chain, and matching live preset values.

Persisted true app flags add filters on initialization. False defaults do not
remove filters already configured by VLC. Preference changes persist the real
engine chain and update the current aout variable, whose callback restarts the
filter pipeline. They preserve unrelated filters, media, queue, volume and rate.
Spatial mode changes replace only the two spatial filters. With spatial audio
disabled the preferred mode is remembered without enabling an effect.

Run from `modules/gui/macosx_redesign` against a configured, built engine:

```sh
python3 tools/native-tests.py --engine-build "$BUILD" --suite audio
```

The runner compiles `MXRAudioPreferenceServices.m` with its runtime test and feeds it the
generated stereo WAV, with isolated data, user data and plug-in directories.
```

The test asserts `--ignore-config`, selects `adummy`, and runs the real queue,
demuxer, decoder and filters. Its engine log callback requires successful filter
module activation and subsequent played PCM buffers, with no pipeline errors.
It also checks native parameter values, Effects/settings synchronization, night
restoration, invalid inputs, bit-exact availability and shutdown. A second run
with a temporary plugin directory excluding only karaoke and argument
`--expect-no-karaoke` verifies that missing modules never become writable switches.
No GUI or physical audio device is opened. Hardware listening is separate from
this headless engine proof. All generated fixtures and logs stay outside Git.
Dummy output can report volume -1 because hardware volume is unsupported; the
harness checks that the reported value remains unchanged. Hardware volume and
audibility are not established by this test.

The helper owns no callbacks, worker or engine object. All calls run on the main
thread. Held audio outputs are released before returning; `shutdown` invalidates
the borrowed player before the central bridge disposes its engine. The private
VLC `aout_internal.h` header provides the immutable output owner's bit-exact state:
changing global config alone cannot make an existing bit-exact output run filters.
This dependency stays inside the Objective-C helper and is compiled against the
same VLC source/config as the linked engine; it never crosses the Swift boundary.
