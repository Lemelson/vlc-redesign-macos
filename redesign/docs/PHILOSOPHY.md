# Philosophy

This project gives VLC on macOS the interface proposed by **Juxtopposed** in
[“I Redesigned VLC After 25 Years”](https://www.youtube.com/watch?v=ERFeOgqk324)
(12 Oct 2026) and the accompanying
[Figma community file](https://www.figma.com/community/file/1691465999134370980)
(CC BY 4.0). It is an unofficial, community-driven fork. It is not affiliated
with VideoLAN or with Juxtopposed.

The pitch is simple. VLC plays everything, and people love it for that. Its
interface is the part people tolerate. The video lays out, point by point, what
a better VLC looks like without losing what makes VLC *VLC*. We build exactly
that on the Mac, natively, on top of an unmodified VLC engine.

## 1. The three sources of truth

Each source answers a different question. When they disagree, this is the order of precedence:

| Question | Source of truth | Where |
|---|---|---|
| **How does it look?** (size, color, spacing, icon, type) | The Figma file | `redesign/design/figma/`, `redesign/design/tokens/` |
| **Why, and how does it behave?** (intent, flows, what goes where) | The video | `redesign/docs/design/VIDEO_BREAKDOWN.md`, `redesign/design/spec/` |
| **What does it do?** (playback, formats, settings semantics) | Upstream VLC | the rest of this repository |

Pixel values come from Figma, never from video frames. Frames are compressed and
5–15% darker. Behavior that Figma cannot show (hover reveal, what a click does,
what is remembered) comes from the designer's words in the video. What a setting
*means* comes from VLC.

## 2. Engineering principles

1. **The engine is sacred.** We do not change `src/`, `lib/`, `include/`, codecs,
   demuxers, outputs or any other module except our own. If a feature truly cannot
   be built without an engine change, it goes through `DECISIONS.md` first and
   is written as a small, isolated, upstreamable patch.
2. **Additive, not invasive.** Our interface is a new module,
   `modules/gui/macosx_redesign/`. We do not edit upstream's macOS GUI
   (`modules/gui/macosx/`); we replace it in our app bundle. Touches to shared
   upstream files (build system, packaging) are kept to a handful of lines, listed in
   `ARCHITECTURE.md`. Goal: `git merge upstream/master` is boring.
3. **Native first.** It must feel like a Mac app: traffic-light window controls, the real menu
   bar, native fullscreen and Spaces, Picture in Picture, media keys and Now
   Playing, trackpad gestures, VoiceOver, Dynamic Type where sensible, and
   `prefers-reduced-motion`. The *look* is Juxtopposed's; the *manners* are macOS.
4. **As fast as stock VLC.** Video goes through the same video output as upstream.
   Our controls are an overlay and must not cost frames. Budgets: idle player under
   1% CPU, overlay animations at display refresh rate, cold start no slower than
   stock VLC.app. We measure, we don't guess.
5. **Swift, SwiftUI, AppKit.** SwiftUI for views. AppKit where SwiftUI is weak
   (window chrome, video host view, menus, complex lists). A thin C/Objective-C bridge
   to VLC's internal APIs. The UI talks to protocols, so every screen also runs
   against a mock backend for previews and visual checks.
6. **Verify visually.** Every screen gets compared against its Figma render. It
   does not need to match to the last pixel, but there must be no visible difference
   at normal viewing distance. See `WORKFLOW.md`.
7. **Small, explained changes.** Every commit says what and why, and points to the
   screen id (`S07`), spec section or decision it implements.

## 3. Design principles (from the video)

These guide every decision the design doesn't cover explicitly. Details and
frame references are in `docs/design/VIDEO_BREAKDOWN.md`.

1. **Keep VLC's identity.** The orange traffic cone and orange accent stay. Neutral
   grays and blacks. Rectangular but slightly softened corners, not
   pill-shaped like every other player. The volume control stays a cone.
2. **The UI gets out of the way.** A thin bar that doesn't cover the video. Top
   and bottom bars appear on hover near them and vanish immediately when the
   pointer leaves. This applies in fullscreen too, so the title stays reachable.
3. **Don't copy every other player.** The play button stays on the left of the bar,
   slightly bigger, with previous/next beside it. Most people use the keyboard to
   pause. The seek bar is thick and easy to hit, with thumbnails while seeking.
4. **Put things where people look.** Window/fullscreen controls on the top right.
   Subtitles and audio on the bottom right. The current show's name on the top.
5. **Fewer clicks for frequent tasks.** Subtitle track, audio track and audio
   output device are one click away. Settings you need *while watching*
   (subtitle delay and style, audio and video filters, speed) live in a sidebar
   next to the video, not in a modal covering it.
6. **Remember things for me.** Presets per show: subtitle delay, font, default
   tracks. Subtitles can be added to a whole folder or playlist at once. There's
   continue-watching, and "unwatched first" sorting.
7. **Queue ≠ playlist.** The queue is what plays next; playlists are collections.
   Drag anything into the queue.
8. **Never leave the video.** The library opens as a compact panel beside the
   video. A full library with a mini player exists for those who want it.
9. **Use your words.** No numeric magic values ("subtitle autodetect fuzziness: 3").
   Human-readable options, an info icon on every setting, and basic settings before
   advanced ones within each category.
10. **Expose the hidden superpowers.** VLC's best features (network streams,
    conversion, bookmarks, chapters, filters) get visible, clean entry points
    instead of being buried.
11. **Customization is optional.** Good defaults. A short onboarding (theme,
    accent, basic shortcuts). Drag-and-drop layout editing and profiles for
    those who want them.

## 4. When the design is silent

Some things are not in the video or in Figma: bookmarks tab contents, the Recent
page, Open Disc/Capture/Convert dialogs, About, most hover/pressed states,
animation timings. Then:

1. Look for the closest existing component in Figma and reuse it. Never invent a
   new visual language.
2. Apply the principles above.
3. Prefer the macOS convention when the choice is about *behavior*. Prefer the
   Figma style when the choice is about *appearance*.
4. Record the choice in `DECISIONS.md` so the next agent makes the same one.

## 5. Community

This fork exists because a lot of people watched the video and thought "yes,
that". Many forks have started on Windows and Linux (see
`redesign/research/FORKS.md`); this one is the macOS-native take. Credit goes
to Juxtopposed for the design and to VideoLAN for VLC. Contributions,
critique and design discussion are welcome. If upstream VideoLAN ever wants
any of it, the additive structure makes that possible.
