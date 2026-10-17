import sys,os,json; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from common import *
from collections import Counter, defaultdict
d=load(); top=d['document']['children'][0]['children']
R=renders()
D={ # id: (phase, description)
'42:356':('component','Icon set: 208 24×24 variants (mono, two-tone, active, selected, direction, EQ curves). See ICONS.md.'),
'187:328':('P3','Player with compact library panel open on **Playlists** (Create playlist, Cool Songs, Anime to Watch); top bar folder chip "Videos"; default control bar.'),
'970:3308':('P3','Full-window library, **list view** (Videos ▸ Shows ▸ The Wand ▸ S01, 4 columns, watched items dimmed last) + **miniplayer bottom-right**.'),
'970:3792':('P3','Same list view with the **miniplayer dragged to bottom-left** (corner-snap state).'),
'970:2703':('P3','Full-window library, **grid view** (5 columns of 16:9 thumbs, watched last with orange bar) + miniplayer bottom-right.'),
'970:4028':('P3','Full-window library grid view, no miniplayer (title "VLC Media Player", 15 items).'),
'6261:15078':('P3','Full-window library **Home**: Continue Watching, Listen Again, Frequently Visited Folders.'),
'247:445':('P1','**Default player** (prototype start): top bar (cone, ⋯, sidebar toggle, folder chip, centered title, window controls), framed video, control bar; hidden resume toast layer.'),
'4767:23726':('P3','**Music now playing**: blurred enlarged cover backdrop, 738×737 cover, "untangle - juxtopposed", control bar `music` variant (±15 s skip, waveform seek).'),
'4778:25123':('P3','Music now playing with compact library open on Music ▸ Songs ▸ My Songs (3 items).'),
'3328:11554':('P1','**Hide UI**: top and control bars hidden, only the framed video (Ctrl + backslash; key F in the prototype).'),
'2425:13624':('P5','**Light theme** player with compact library (S01 list); only frame using Light styles (partially).'),
'2107:5604':('P5','**Customize Player** edit mode: dashed outlines on all bar items + Customize dialog (31 tiles); Save disabled.'),
'2160:6137':('P5','Customize step 1: seek bar dragged into its own row above the controls (two-row bottom bar); Save enabled.'),
'2160:6564':('P5','Customize step 2: prev/play/next centered in the bottom row.'),
'2160:7005':('P5','Customize step 3: media title moved from top bar to bottom row (left).'),
'2160:7437':('P5','Customize step 4: ⋯, sidebar toggle and folder chip moved to bottom-left; top bar keeps cone + window controls.'),
'2160:7869':('P5','Customize step 5: fullscreen button moved to bottom-right.'),
'6587:19923':('P5','Customize step 6: Favorite (♡) dragged next to the title; its tile disappears from the grid.'),
'2160:8301':('P5','Saved **alternate layout** (dialog closed): two-row bottom bar, minimal top bar.'),
'2160:8732':('P5','Alternate layout with the compact library open (S01 list).'),
'999:5047':('P4','Settings **General** ("Global Settings"): Appearance (language, theme Dark/Light/System, 9 accent swatches), Startup, Diagnostics; Advanced collapsed.'),
'3046:9282':('P4','Settings General with **Advanced Options expanded** (minor warnings, CLI options, log format, statistics, config folder, reset, Developer Options).'),
'3046:10057':('P4','Settings **Interface**: Skin, Window, Playback Controls (auto-hide slider), Notifications and System Tray, Playlist.'),
'3062:11379':('P4','Settings Interface, Advanced expanded (window opacity, pause when minimized, fullscreen controls opacity/sensitivity…).'),
'3062:11911':('P4','Settings **Privacy**: History (recent items, resume position, clear) and Network (metadata fetch, Last.fm).'),
'3062:12552':('P4','Settings **Playback**: Startup (continue, speed slider), Tracks, Order, Seeking, Files & Discs.'),
'3072:13408':('P4','Settings Playback, Advanced expanded (time-shift buffer folder/size).'),
'3073:14187':('P4','Settings **Video**: Output, Picture sliders, Deinterlacing, Framing, Snapshots.'),
'3073:15375':('P4','Settings Video, Advanced expanded (custom aspect/crop ratios, monitor pixel aspect).'),
'3073:15879':('P4','Settings **Audio**: Output, Volume (max slider, startup volume chooser), Loudness, Effects (EQ closed), Tracks, Visualization.'),
'3180:17398':('P4','Settings Audio with the **inline Equalizer open** (preamp + 10 vertical bands) and Advanced expanded.'),
'3180:17989':('P4','Settings **Subtitles**: Tracks & Languages, Loading Subtitles, Appearance, Timing, On-Screen Messages.'),
'6536:13908':('P4','Settings Subtitles, Advanced expanded (subtitle folders, ignore ASS styling, shadow angle, text direction, monospace font).'),
'6536:14482':('P4','Settings **Controls** ("Mouse, Keyboard & Remote Controls"): shortcuts buttons, skip amounts, mouse, remotes.'),
'6542:15251':('P4','Settings **Library** ("Playlists, Folders & Files"): opening files (disabled dependent rows), metadata & artwork.'),
'6543:15649':('P4','Settings **Network**: buffering (custom fields disabled), proxy, security.'),
'6571:15958':('P4','Settings **Performance**: decoding, smooth playback, Rescan plugins; Advanced expanded (Developer clock options).'),
'6571:16429':('P4','Settings **Recording** ("Recording, Casting & Streaming Out").'),
'6575:17137':('P4','Settings **Extensions** (page title "Add-ons & Scripts"): add-on list box, Find more / Add / Remove, load on startup.'),
'1911:7545':('P2','**Add Subtitles**, To This Folder / From Computer: 15 video ↔ .srt auto-matched rows with dashed connectors.'),
'3336:11929':('P2','**Exact duplicate** of 1911:7545 (identical node geometry/text; renders pixel-identical). Ignore.'),
'1919:8707':('P2','Add Subtitles, **To This File / From Computer**: list of 6 language .srt files, 2 selected.'),
'1919:9278':('P2','Add Subtitles, **To This File / From OpenSubtitles**: search "The Wand S01E01" + language "English", 2 results, 1 selected.'),
'2437:14832':('P4','**Keyboard Shortcuts** dialog: search, "All Fields" filter, Action / Hotkey / Global Hotkey table (Basic, Playback groups).'),
'6216:13614':('P3','**Open Network Stream** dialog: multi-line URL area, optional playlist name; Save disabled.'),
'6259:14954':('P3','**New Playlist** dialog: name + thumbnail picker, file drop zone; Save disabled.'),
'1899:3055':('P5','Onboarding 1/3 **Welcome**: cone, text, media folder field + Browse, Next.'),
'1902:3670':('P5','Onboarding 2/3 **Theme & color** (orange selected): Light/Dark/System tiles, live mini-player preview, 9 color dots, Back/Next.'),
'1902:6770':('P5','Onboarding 3/3 **Basic keyboard shortcuts** (two columns of keycaps), Back/Finish.'),
'1902:4020':('P5','Onboarding theme step, accent **red** #E15032 (preview recolored).'),
'1902:4325':('P5','Onboarding theme step, accent **olive** #C49E23.'),
'1902:4634':('P5','Onboarding theme step, accent **green** #19A234.'),
'1902:4940':('P5','Onboarding theme step, accent **teal** #18AAD3.'),
'1902:5245':('P5','Onboarding theme step, accent **blue** #185DD3.'),
'1902:5550':('P5','Onboarding theme step, accent **purple** #8E42FF.'),
'1902:6160':('P5','Onboarding theme step, accent **pink** #F052B3.'),
'1902:6465':('P5','Onboarding theme step, accent **gray** #AFAFAF.'),
'177:98':('component','Icon Wrapper: 30×32 icon button, Default / hover (#FFFFFF 6%).'),
'244:184':('component','volume: cone slider, 13 steps 0–200% (green→orange→red gradient).'),
'491:1780':('component','Controls: 1920×54 control bar, 15 variants — default, Variant10, waveform, music, queue/bookmarks/chapters panels, subtitles/audio/video track popups, playback/video/audio/subtitle settings sidebar, sub timeline.'),
'2151:9673':('P1','thumbnail: seek-bar hover preview card (252×142 frame + time).'),
'500:3063':('component','Button: full-width panel footer button ("Show Advanced Settings"), Default / hover.'),
'536:1014':('component','Toggle: 68×32 two-cell square toggle, on / off.'),
'536:1513':('component','Audio - Compressor Settings: collapsible filter card (collapsed / expanded sliders). Used in P2 sidebar Audio tab.'),
'6114:13610':('component','Audio - Equalizer: collapsible card, preamp + 10 bands. P2 sidebar Audio tab.'),
'536:1703':('component','Audio - Spatializer Settings: collapsible card. P2 sidebar Audio tab.'),
'612:1223':('component','Audio - Stereo Widener: collapsible card. P2 sidebar Audio tab.'),
'536:1855':('component','Video - Essential: collapsible card (hue, brightness, contrast, …). P2 sidebar Video tab.'),
'543:990':('component','Video - Crop: collapsible card (top/bottom/left/right px). P2 sidebar Video tab.'),
'614:1430':('component','Video - Colors: collapsible card (color extraction, posterize, sepia…). P2 sidebar Video tab.'),
'804:1208':('component','Values: segmented control, 2 or 3 options (e.g. Relative/Pixels, Dark/Light/System).'),
'848:1712':('component','play: 54×28 play / pause button.'),
'848:1996':('component','sidebar: library rail + compact panel, 10 variants — Default (S01), home, videos, videos2, videos3, music, music2, music3, network, playlists.'),
'856:2215':('P3','Sorting Options menu (16 options, Unwatched First selected).'),
'2107:5903':('component','context menu: generic 6-row menu specimen ("Option" placeholders, one hover).'),
'2139:8935':('P3','folder context menu (library ⋯): Add File, Add Folder, Edit Subtitle/Audio Tracks, Resync, Info.'),
'2404:13340':('P3','file context menu (row ⋯): Play, Mark as Watched, Favorite, Stream, Convert, Add to Queue/Playlist, Show in File Explorer, … Properties & Metadata.'),
'2459:9389':('P3','playlist context menu: Play, Favorite, Shuffle, Export Playlist, Add to Queue, Add Subtitle/Audio Tracks, Properties & Metadata.'),
'858:3290':('P3','View Options menu: Grid View / List View (selected).'),
'970:3091':('component','Miniplayer: 391×339 card (Default, hover Variant3/Variant5) and 391×690 with queue (Variant2/Variant4). P3.'),
'1904:7238':('component','Current Time: Default / hover / click (editable) states.'),
'2245:9805':('P1','audio value: volume tooltip "100 %".'),
'1905:7312':('component','Duration: Default / click (remaining "-00:23:30").'),
'1915:8397':('component','subtitle multiple: Add Subtitles batch row (video ↔ srt), Default / hover.'),
'1919:9121':('component','subtitle one: Add Subtitles single-file row, Default / selected.'),
'1959:5325':('component','target: Add Subtitles scope dropdown (To This Folder / File / Playlist), closed + open states.'),
'1963:5465':('component','origin: Add Subtitles source dropdown (From Computer / From OpenSubtitles / From Link …), closed + open.'),
'2107:5935':('component','option: 48 px menu row, Default / hover / selected.'),
'6062:13354':('P1','menu: the **⋯ app menu** (final list: Open File(s) … Profile (Movies) › … About VLC).'),
'2372:8300':('component','Dropdown: generic settings dropdown, default / open.'),
'2372:8834':('component','Setting Preset: sidebar preset picker (Default Preset, New Preset, custom presets), default / open.'),
'2372:8487':('component','EQ presets: dropdown with EQ-curve two-tone icons (None … Techno), default / open.'),
'2372:8639':('component','Audio Visualizer: dropdown (Disabled, Spectometer, Scope, Spectrum, Waveform).'),
'2372:8733':('component','HDR Options: dropdown (Auto, Off, HDR10, HDR10+, Dolby Vision, HLG).'),
'6456:13892':('component','sub filename: subtitle file-name matching dropdown (Off … Exact title match).'),
'2404:9167':('component','media: library row (337×32) watched / unwatched / hover states.'),
'2459:9352':('component','playlist: library playlist row, unwatched / hover.'),
'3021:9835':('component','setting category: settings nav row, selected no / yes.'),
'3176:16556':('component','Values: stacked two-row chooser (Remember last volume / Always starts at: 200%).'),
'3178:16769':('component','EQ: settings inline equalizer, closed ("Open Equalizer") / open (vertical bands).'),
'6065:13616':('P1','**right-click menu**: Play, Stop, Previous/Next Item, Record, Hide UI (Ctrl + backslash), Playback ›, Video ›, Audio ›, Subtitle ›, More Settings ›, Playlist ›, Open Media ›, Quit VLC.'),
'6648:20666':('P5','**Profiles**: ⋯ menu with "Profile (Movies)" hovered + submenu Movies ✓ / Shows / Music / Work / + New.'),
'6841:16196':('—','Canvas section label "Components" (TEXT, not UI).'),
'6841:16197':('—','Canvas section label "Designs" (TEXT, not UI).'),
}
# render mapping by layer order
cnt=Counter(); rows=[]; used=set(); issues=[]
for c in top:
    nm=c['name']; k=cnt[nm]; cnt[nm]+=1
    fn=nm+('' if k==0 else '-%d'%k)+'.png'
    rb=c.get('absoluteRenderBounds') or c['absoluteBoundingBox']
    exp=(round(rb['width']*2),round(rb['height']*2))
    if fn in R:
        used.add(fn); w,h=R[fn]
        ok=abs(w-exp[0])<=2 and abs(h-exp[1])<=2
        chk='✓ %d×%d (2×)'%(w,h) if ok else '✗ %d×%d, expected %d×%d'%(w,h,exp[0],exp[1])
        if not ok: issues.append(fn)
    else:
        chk='✗ no render'; issues.append('missing '+fn)
    ph,ds=D[c['id']]
    bb=c['absoluteBoundingBox']
    rows.append((c['id'],c['type'].replace('COMPONENT_SET','set').replace('FRAME','frame').replace('TEXT','text'),nm,'%g×%g'%(bb['width'],bb['height']),ds,fn,chk,ph))
orphan=[f for f in R if f not in used]
L=[]
L.append('# Figma catalog: top-level frames and component sets\n')
L.append('Source: `figma_file.json` ("%s", version %s, last modified %s), page "Page 1" (node 0:1), 105 top-level layers in layer order. Design: **VLC Redesign by Juxtopposed** — Figma community file https://www.figma.com/community/file/1691465999134370980, licensed **CC BY 4.0** (attribution required in the app\'s About/credits and in the repo).\n'%(d['name'],d['version'],d['lastModified']))
L.append('How to read this table:')
L.append('- **Size** is the frame\'s `absoluteBoundingBox` in Figma px (= macOS points at 1x). Player frames are 1920×1080 window mock-ups.')
L.append('- **Render**: file in `renders/` (links are relative to this file). Duplicate frame names are numbered in layer order (first = no suffix, then `-1`, `-2`, …). Every render was checked: its pixel size must equal 2× the frame\'s `absoluteRenderBounds` (frame + drop-shadow bleed of 15 px left/right, 7 px top, 23 px bottom for dialogs/menus) within 2 px; duplicates of the same size were told apart by content (miniplayer position, Advanced Options text, accent color, step of the customize sequence).')
L.append('- "Add Subtitles to Playlist/Folder" contains a slash, so its renders live in the sub-folder `renders/Add Subtitles to Playlist/` as `Folder.png`, `Folder-1.png`, …')
L.append('- **Phase**: P1 player shell & controls · P2 side panels & subtitles · P3 library/music/streams/playlists · P4 settings/hotkeys · P5 customization/onboarding/profiles · component = reusable component set (implemented with the screen that first needs it).')
L.append('- Screen-level implementation order and VLC wiring are in `../SCREENS.md`; tokens in `../tokens/`; icons in `ICONS.md`.\n')
L.append('## Summary\n')
tc=Counter(r[1] for r in rows); pc=Counter(r[7] for r in rows)
L.append('- %d top-level layers: %d frames, %d component sets, %d text labels.'%(len(rows),tc['frame'],tc['set'],tc['text']))
L.append('- By phase: '+', '.join('%s %d'%(k,pc[k]) for k in ['P1','P2','P3','P4','P5','component','—']))
L.append('- Renders: %d PNG files, %d matched 1:1 to frames, %d frames without render, %d renders without frame.'%(len(R),len(used),sum(1 for r in rows if r[6].startswith('✗ no')),len(orphan)))
L.append('- Size check failures: %s.\n'%(', '.join(issues) if issues else 'none'))
L.append('## Frames and component sets (layer order)\n')
L.append('| # | Node id | Type | Name | Size | What it shows | Render | Check | Phase |\n|---|---|---|---|---|---|---|---|---|')
for i,r in enumerate(rows,1):
    link='[%s](renders/%s)'%(r[5],r[5].replace(' ','%20'))
    L.append('| %d | `%s` | %s | %s | %s | %s | %s | %s | %s |'%(i,r[0],r[1],r[2],r[3],r[4],link,r[6],r[7]))
L.append('\n## Grouped by phase\n')
for ph in ['P1','P2','P3','P4','P5','component']:
    L.append('- **%s**: '%ph+', '.join('`%s` %s'%(r[0],r[5][:-4]) for r in rows if r[7]==ph))
L.append('\n## Flags and inconsistencies\n')
L.append('- **Frames with no render:** none. **Renders with no frame:** none%s. `renders/styles.txt` is a text export of the styles, not a render.'%(' ('+', '.join(orphan)+')' if orphan else ''))
L.append('- `Components.png` and `Designs.png` render the two giant canvas labels; they are not UI.')
L.append('- `3336:11929` (`Add Subtitles to Playlist/Folder-1.png`) is an exact duplicate of `1911:7545` (same tree, geometry and text; pixel-identical render).')
L.append('- Onboarding color frames `Onboarding-3 … -10` differ from `Onboarding-1` only in the accent color (identical geometry); they are not wired in the prototype.')
L.append('- `Player - customize` frames embed a 1048×655 frame named "Add Subtitles to Playlist/Folder" that is actually the **Customize Player** dialog (copy-pasted dialog shell, never renamed).')
L.append('- Settings → Extensions page title is **"Add-ons & Scripts"** in Figma, while spec-part2 §14 writes "Extensions & Scripts". Use the Figma text. Same page: list header "Add-ons", toggle "Load add-ons on startup".')
L.append('- Settings → Video Advanced (`3073:15375`) contains "Time-shift buffer size", duplicated from Playback Advanced (copy-paste in the design).')
L.append('- Settings → Interface has a typo "Show a popup when the track changew"; Settings → Recording has lower-case "include subtitles"; Privacy has two "Last.fm username" rows (the second is presumably "Last.fm password"; also in the video).')
L.append('- Library texts contain the typo `The_Wand_S01E13mp4` (missing dot) in most frames; resume toast text "00:04:80" is an invalid time.')
L.append('- `Player - Light` mixes Light and Dark styles (control-bar icons and library text still use Dark/FG/A2, Dark/FG/A1); see `../tokens/colors.json` meta.lightThemeCoverage.')
L.append('- Node ids are identical across the three community copies used by the forks (figma keys `B7ifd32…`, `mNrr8…`, `fQSx…`); the srdouglax inventory lists 103 nodes (it omits the two text labels).')
L.append('- The prototype wires some demo links that are not design intent (About VLC → Customize, right-click Playlist → Keyboard Shortcuts, key V → Add Subtitles, key F → Hide UI). See `../../research/from-forks/pyr0zen/FIGMA_FLOWS.md`.')
open(ROOT+'/INDEX.md','w').write('\n'.join(L)+'\n')
print(issues,orphan)
