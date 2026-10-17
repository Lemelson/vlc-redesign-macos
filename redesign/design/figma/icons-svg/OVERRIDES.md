# Documented SVG source overrides

The exported SVGs normally remain untouched. These exceptions reconcile an export with the licensed Figma render used for visual acceptance.

## `video.svg` — mono video icon

The local `Icon.png` render of component `999:4810` shows a connected clapperboard: a rounded outer outline, horizontal cap divider and two slanted separators. The original `video.svg` export and cached JSON contain only the outer rounded rectangle, so the generated native icon was incomplete. The export index identifies a different copy of the same community file; see `../ICONS.md` under Notes and inconsistencies.

The override preserves the exported outer `Rectangle 16` path, 24 × 24 view box, 1.5 px stroke and mono `Dark/FG/A2` paint `#8F8F8F`. It restores only the three missing cap strokes to match the canonical rendered mono component. The related `5886:24408` two-tone SVG was examined, but flattening it would create a detached solid cap, which does not match the mono reference. The generator is unchanged and remains the sole producer of the native rendition.

Validation uses `figma_ref.py 999:4810 --scale 2` (48 × 48 px canonical crop) and `rsvg-convert` at the same size, composited over black. Mean maximum-channel difference improves from 7.50 to 0.52/255; pixels with a maximum-channel difference greater than 16 improve from 150 to 12 out of 2,304. Remaining differences are confined to cap stroke edges. This is a documented render-based correction, not an unmodified SVG export.

Design: VLC Redesign by Juxtopposed, CC BY 4.0. Only the mono video variant is overridden; active and two-tone variants retain their exported source geometry.
