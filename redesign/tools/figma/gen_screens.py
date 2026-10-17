"""Generate redesign/design/SCREENS.md (single source: rerun this, never hand-edit the file).

    python3 redesign/tools/figma/gen_screens.py [--parity PARITY.json] [--out PATH] [--check]

The 'Parity · live' column is the worst offscreen verdict per S-id from the parity judges'
JSON (default: the latest final-polish run) plus the live real-window notes in LIVE below.
"""
import sys,os,json,re,argparse; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from common import *
from desc import IDX
from collections import Counter
ap=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument('--parity',default=REPO+'/redesign/research/final-polish/results/resume/parity.json')
ap.add_argument('--out',default=None,help='write here instead of redesign/design/SCREENS.md')
ap.add_argument('--check',action='store_true',help='exit 1 if SCREENS.md differs from the generated text')
ARGS=ap.parse_args()
d=load(); top=d['document']['children'][0]['children']
DES=REPO+'/redesign/design'
FRAMES=REPO+'/../reference/video/frames'
# render map
cnt=Counter(); RN={}
for c in top:
    k=cnt[c['name']]; cnt[c['name']]+=1; RN[c['id']]=c['name']+('' if k==0 else '-%d'%k)+'.png'
topids={c['id'] for c in top}
def toplevel(nid):
    n,p=IDX[nid]
    while n['id'] not in topids:
        n=IDX[n['id']][1]
    return n['id']
# spec anchors
def slugs(path):
    out={}; seen=Counter()
    for line in open(path,encoding='utf-8'):
        m=re.match(r'^(#{1,6})\s+(.*?)\s*$',line)
        if not m: continue
        t=m.group(2); s=t.lower(); s=re.sub(r'[^\w\- ]','',s); s=s.replace(' ','-')
        a=s if seen[s]==0 else '%s-%d'%(s,seen[s]); seen[s]+=1
        out.setdefault(t,a)
    return out
SL={'1':slugs(DES+'/spec/spec-part1.md'),'2':slugs(DES+'/spec/spec-part2.md')}
problems=[]
def spec(ref):
    part,h=ref
    if h not in SL[part]: problems.append('heading not found: %s %s'%ref); return h
    short=re.sub(r'\s*\(.*?\)\s*$','',h) if len(h)>45 else h
    return '[p%s §%s](spec/spec-part%s.md#%s)'%(part,short.replace('|','/'),part,SL[part][h])
def vid(f):
    if not os.path.exists(os.path.join(FRAMES,f)): problems.append('missing video frame '+f)
    return '[`%s`](../../../reference/video/frames/%s)'%(f,f)
def fig(nid):
    t=toplevel(nid)
    r=RN[t]
    link='[%s](figma/renders/%s)'%(r if t==nid else 'in '+r,r.replace(' ','%20'))
    return '`%s` %s'%(nid,link)
P1,P2,P3,P4,P5='P1','P2','P3','P4','P5'
SCR=[
# name, phase, figma nodes, spec refs, video frames, vlc, inventory#
('Player window, default layout (top bar, framed video, control bar; play/pause states)',P1,['247:445','491:1779','848:1712'],[('1','NEW: final control bar (as seen in native frames from 04:06 on)'),('1','NEW: top bar (final form)'),('1','NEW: video canvas and window frame')],['04-subtitle-audio-buttons/04m10.91s.jpg','04-subtitle-audio-buttons/04m06.72s.jpg','06-subtitle-import-dialog/06m24.41s.jpg','10-network-streams-open-dialogs/12m56.59s.jpg'],'vlc_player pause/resume/state, time+length, seek; vlc_playlist prev/next; vout embedded in an NSView',[1]),
('Time labels: editable current time, elapsed/remaining toggle',P1,['1904:7238','1905:7312'],[('1','NEW: final control bar (as seen in native frames from 04:06 on)')],['04-subtitle-audio-buttons/04m10.91s.jpg'],'vlc_player_SetTime / vlc_player_GetTime / vlc_player_GetLength',[]),
('Seek thumbnail preview (hover/drag on seek bar)',P1,['2151:9673'],[('1','NEW: seek thumbnail preview')],['02-control-bar-seekbar-volume/03m29.34s.jpg'],'vlc_preparser thumbnail request at time (vlc_preparser_GenerateThumbnail)',[]),
('Volume cone slider + volume tooltip (0-200 %)',P1,['244:184','2245:9805'],[('1','NEW: final control bar (as seen in native frames from 04:06 on)')],['02-control-bar-seekbar-volume/03m08.39s.jpg','04-subtitle-audio-buttons/04m30.41s.jpg'],'vlc_player_aout_SetVolume / GetVolume / ToggleMute',[]),
('Fullscreen and hover-reveal of top/control bars',P1,['247:445'],[('1','03 — Top bar, fullscreen, hover behavior (03:30–04:00)'),('1','Behavior')],['03-top-bar-fullscreen-hover/03m47.56s.jpg','03-top-bar-fullscreen-hover/03m53.56s.jpg','04-subtitle-audio-buttons/04m00.66s.jpg'],'vlc_player_vout_SetFullscreen (or NSWindow fullscreen) + pointer-idle tracking',[]),
('Hide UI mode (Ctrl + backslash)',P1,['3328:11554'],[('1','NEW: Hide UI')],['05-menus-right-click/05m29.01s.jpg'],'UI state only (no core call); hotkey binding',[]),
('"⋯" app menu (final list incl. Profile, Keyboard Shortcuts)',P1,['6062:13354','2107:5935'],[('2','B. "⋯" app menu (the main menu that replaces the menubar)'),('1','NEW: `⋯` menu (top-bar menu)')],['05-menus-right-click/05m08.96s.jpg','10-network-streams-open-dialogs/13m08.59s.jpg','15-customization-onboarding/19m29.39s.jpg'],'dispatch: open file/folder → vlc_playlist_Append; dialogs; settings',[12]),
('Open Recent submenu',P1,[],[('2','B. "⋯" app menu (the main menu that replaces the menubar)')],[],'vlc_ml_list_history (global history) / recent MRL list',[14]),
('Right-click (context) menu on the video',P1,['6065:13616'],[('1','NEW: right-click (context) menu')],['05-menus-right-click/05m23.01s.jpg'],'vlc_player Pause/Stop, vlc_player_SetRecordingEnabled; vlc_playlist_Prev/Next',[]),
('Right-click submenus: Playback, Video, Audio, Subtitle, More Settings, Playlist, Open Media (not designed)',P1,[],[('1','NEW: right-click (context) menu')],[],'vlc_player rate/tracks/aspect/crop/deinterlace/zoom, mirroring VLC 3 menus',[]),
('Native macOS menu bar mirroring the ⋯ menu (platform requirement)',P1,[],[('1','NEW: `⋯` menu (top-bar menu)')],[],'NSMenu bound to the same actions as S07/S09',[]),
('Continue-watching toast + resume marker on seek bar (Figma: hidden layer `continue` inside the frame, not visible in the render; spec measurements from the video)',P1,['1919:9580'],[('2','12 Continue-watching prompt')],['12-continue-watching/14m09.81s.jpg'],'vlc_ml media playback position (progress / restore-playback-pos) → vlc_player_SetTime',[18]),
('OSD message showing the pressed key',P1,[],[('2','B. OSD message with pressed key')],['14-settings-hotkeys/15m27.09s.jpg'],'vlc_player_osd_Message (vout OSD) with action + key name',[22]),
('Track popover: Subtitles tab (embedded + external tracks)',P2,['491:2216'],[('1','NEW: track popover')],['06-subtitle-import-dialog/06m21.67s.jpg'],'vlc_player track list (SPU): GetTrackCount/GetTrackAt/SelectTrack; AddAssociatedMedia',[]),
('Track popover: Audio tab (tracks + output device)',P2,['496:2495'],[('1','NEW: track popover')],['04-subtitle-audio-buttons/04m36.41s.jpg','04-subtitle-audio-buttons/04m42.41s.jpg'],'vlc_player track list (AUDIO_ES); output devices via aout_DevicesList / aout_DeviceSet',[]),
('Track popover: Video tab',P2,['498:2674'],[('1','NEW: track popover')],['04-subtitle-audio-buttons/04m54.76s.jpg'],'vlc_player track list (VIDEO_ES) select',[]),
('Settings sidebar: Playback tab (subtitle timeline toggle, reverse, sleep timer, visualizer, speed)',P2,['2238:9432','2372:8639'],[('1','NEW: settings sidebar')],['07-sidebar-subs-audio-video-playback/09m12.97s.jpg'],'vlc_player_ChangeRate; audio visualizer = "audio-visual" var; sleep timer app-side; reverse playback not supported by core (flag)',[]),
('Settings sidebar: Video tab + filter cards (Essential, Crop, Colors) + HDR dropdown',P2,['498:2937','536:1855','543:990','614:1430','2372:8733'],[('1','NEW: settings sidebar')],['07-sidebar-subs-audio-video-playback/09m00.97s.jpg','07-sidebar-subs-audio-video-playback/09m06.97s.jpg'],'vout vars: video-filter (adjust, transform, ...), crop, aspect-ratio, zoom/autoscale, deinterlace; HDR tone-mapping options',[]),
('Settings sidebar: Audio tab + EQ / Compressor / Spatializer / Stereo Widener cards + EQ presets',P2,['536:1059','6114:13610','536:1513','536:1703','612:1223','2372:8487'],[('1','NEW: settings sidebar')],['07-sidebar-subs-audio-video-playback/08m42.97s.jpg','07-sidebar-subs-audio-video-playback/08m48.97s.jpg','07-sidebar-subs-audio-video-playback/08m54.97s.jpg'],'audio-filter equalizer/compressor/spatializer/stereo_widen vars; vlc_player_SetAudioDelay; stereo-mode',[]),
('Settings sidebar: Subtitles tab + presets picker',P2,['763:1958','2372:8834','804:1208'],[('1','NEW: settings sidebar')],['07-sidebar-subs-audio-video-playback/07m47.87s.jpg','07-sidebar-subs-audio-video-playback/07m52.89s.jpg','07-sidebar-subs-audio-video-playback/07m58.89s.jpg','07-sidebar-subs-audio-video-playback/08m36.97s.jpg'],'vlc_player_SetSubtitleDelay, sub-fps, freetype-* / sub text scale; presets stored app-side',[]),
('Subtitle timeline mode of the seek bar (cue blocks, ‹ − + › nudges)',P2,['3744:12361'],[('1','NEW: subtitle timeline mode (seek bar)')],['07-sidebar-subs-audio-video-playback/07m04.19s.jpg','07-sidebar-subs-audio-video-playback/06m58.19s.jpg'],'vlc_player_SetSubtitleDelay; cue times are not exposed by vlc_player (parse the subtitle file / SPU ES)',[]),
('Right panel: Queue tab (sort, repeat, shuffle, −, +; drag from library)',P2,['491:1781'],[('2','A. Right sidebar: Queue / Bookmarks / Chapters'),('1','NEW: queue panel (introduced here, final look in 08)')],['08-media-library/09m30.06s.jpg','16-final-showcase/20m21.37s.jpg','08-media-library/11m45.76s.jpg'],'vlc_playlist items/Move/Remove/Sort, playback repeat + order (random)',[19]),
('Right panel: Bookmarks tab',P2,['6320:13763'],[('2','A. Right sidebar: Queue / Bookmarks / Chapters')],[],'vlc_ml bookmarks (vlc_ml_media_add_bookmark / list) or player bookmarks; Ctrl+B',[21]),
('Right panel: Chapters tab',P2,['6321:14024'],[('2','A. Right sidebar: Queue / Bookmarks / Chapters')],['13-bookmarks-chapters-osd/15m16.67s.jpg','13-bookmarks-chapters-osd/15m15.09s.jpg'],'vlc_player title/chapter list (vlc_player_GetTitleList, vlc_player_SelectChapterIdx)',[20]),
('Add Subtitles: batch To This Folder / Playlist, From Computer (auto-match rows)',P2,['1911:7545','1915:8397','1959:5325','1963:5465'],[('1','NEW: "Add Subtitles" dialog')],['06-subtitle-import-dialog/06m02.47s.jpg','06-subtitle-import-dialog/06m08.47s.jpg','06-subtitle-import-dialog/06m14.47s.jpg','06-subtitle-import-dialog/06m20.47s.jpg'],'vlc_ml_media_add_external_mrl (subtitle) per media + vlc_player_AddAssociatedMedia for current; fuzzy name match',[]),
('Add Subtitles: To This File, From Computer (pick language files)',P2,['1919:8707','1919:9121'],[('1','NEW: "Add Subtitles" dialog')],['06-subtitle-import-dialog/06m02.47s.jpg'],'vlc_player_AddAssociatedMedia (SPU, select)',[]),
('Add Subtitles: From OpenSubtitles (search + language)',P2,['1919:9278'],[('1','NEW: "Add Subtitles" dialog')],[],'no core API: OpenSubtitles REST download, then vlc_player_AddAssociatedMedia',[]),
('Compact library panel: Videos folder list (breadcrumb, count, sort/view/search)',P3,['848:1996','2404:9167','2425:13624'],[('1','NEW: player with compact library (the primary flow)')],['08-media-library/11m56.96s.jpg','08-media-library/11m45.76s.jpg'],'vlc_ml folders / entry points + media per folder, playback progress',[4]),
('File context menu (row ⋯)',P3,['2404:13340'],[('1','NEW: full library window')],[],'vlc_ml_media_set_played / favorite, vlc_ml_playlist_append, vlc_playlist_Append, reveal in Finder',[45]),
('Folder context menu (library header ⋯ "more")',P3,['2139:8935'],[('1','NEW: full library window')],['08-media-library/10m55.49s.jpg'],'vlc_ml_add_entry_point / reload (Resync), media info',[45]),
('Playlist context menu',P3,['2459:9389'],[('1','NEW: full library window')],[],'vlc_ml playlist: play, shuffle, export (m3u via playlist export), favorite',[45]),
('Sort menu + View options menu',P3,['856:2215','858:3290'],[('1','NEW: full library window')],['08-media-library/10m49.49s.jpg'],'vlc_ml_query_params sort (VLC_ML_SORTING_*); watched-first ordering app-side',[]),
('Compact library: Music root, Songs, My Songs folder',P3,['858:5001','4767:23606','4778:24990'],[('2','09 Music')],['09-music/12m12.39s.jpg','09-music/12m06.39s.jpg'],'vlc_ml_list_audio_media / albums / artists / genres',[3]),
('Music now playing (cover art, blurred backdrop, waveform seek bar)',P3,['4767:23726','4778:25123','4778:26181','2139:8124'],[('2','09 Music')],['09-music/12m18.39s.jpg'],'vlc_player media meta + artwork URL; waveform needs a separate audio decode pass (not in core)',[2]),
('Compact library: Network streams category',P3,['858:5294'],[('2','A. Network category (compact panel)')],['10-network-streams-open-dialogs/12m28.36s.jpg','11-playlists-pins-recent-home/13m18.66s.jpg'],'saved streams as vlc_ml playlists/MRLs; m3u expanded via vlc_preparser',[5]),
('Open Network Stream dialog',P3,['6216:13614'],[('2','C. Open Network Stream dialog (NEW)')],['11-playlists-pins-recent-home/13m17.76s.jpg'],'vlc_playlist_Append(MRL); optional vlc_ml_playlist_create',[15]),
('Open Disc / Capture Device / Convert / Stream / Open from Clipboard dialogs (not designed; reuse dialog chrome)',P3,[],[('2','Open questions (10)')],[],'disc MRLs (dvd://, bluray://, cdda://), avcapture, sout transcode/stream chains',[16]),
('Compact library: Playlists category',P3,['858:5374','187:328','2459:9352'],[('2','A. Playlists category (compact)')],['11-playlists-pins-recent-home/13m24.66s.jpg','16-final-showcase/20m20.84s.jpg'],'vlc_ml_list_playlists',[6]),
('New Playlist dialog',P3,['6259:14954'],[('2','B. New Playlist dialog')],['11-playlists-pins-recent-home/13m26.14s.jpg'],'vlc_ml_playlist_create + vlc_ml_playlist_append (thumbnail app-side)',[17]),
('Compact library: Home (Continue Watching / Listen Again)',P3,['1106:5633'],[('2','D. Home (compact panel)')],['11-playlists-pins-recent-home/13m47.17s.jpg'],'vlc_ml_list_history + in-progress media',[7]),
('Compact library: Recent (not designed)',P3,[],[('2','Open questions (11)')],[],'vlc_ml_list_history',[8]),
('Library icon rail with Home, categories, Recent, pins, + add pin',P3,['848:1996'],[('2','C. Rail with pins')],['11-playlists-pins-recent-home/13m41.17s.jpg','11-playlists-pins-recent-home/13m47.17s.jpg'],'pins persisted app-side (ML ids / MRLs)',[9]),
('Full-window library: Home',P3,['6261:15078'],[('2','E. Home (full-window library)')],['11-playlists-pins-recent-home/13m57.34s.jpg'],'vlc_ml history, audio, folders, playlists, artists',[10]),
('Full-window library: folder grid view (watched states, unwatched-first)',P3,['970:4028','970:2703'],[('2','F. Full-window folder grid (final showcase)'),('1','NEW: full library window')],['08-media-library/10m57.64s.jpg','16-final-showcase/20m14.84s.jpg'],'vlc_ml folder media + vlc_ml_media_generate_thumbnail + progress',[11]),
('Full-window library: list view',P3,['970:3308'],[('1','NEW: full library window')],['08-media-library/11m48.27s.jpg'],'vlc_ml folder media (list)',[]),
('Mini player (hover controls, queue expansion, corner snapping)',P3,['970:3091','970:3792'],[('1','NEW: full library window')],['08-media-library/11m48.27s.jpg','08-media-library/11m54.27s.jpg'],'vout re-parented into the mini player view; vlc_playlist',[]),
('Library search results and detail view (not designed)',P3,[],[('1','NEW: full library window')],[],'vlc_ml_search_media / search params',[]),
('Settings window chrome: search, category nav, Advanced Options bar, ⓘ info',P4,['999:5047','3021:9835'],[('2','A. Settings window: chrome')],['14-settings-hotkeys/17m40.87s.jpg'],'config_GetInt/PutInt/GetPsz, config_SaveConfigFile; search app-side',[]),
('Settings: General (theme, accent color, startup, diagnostics; Advanced)',P4,['999:5047','3046:9282'],[('2','B. Settings categories: every readable row')],['14-settings-hotkeys/17m40.87s.jpg','14-settings-hotkeys/17m50.07s.jpg','15-customization-onboarding/18m51.06s.jpg'],'config: verbose, stats, file-logging/logfile; app theme + accent prefs',[23]),
('Settings: General in Light theme',P4,['999:5047','2425:13624'],[('2','B. Settings categories: every readable row')],['14-settings-hotkeys/17m42.54s.jpg','14-settings-hotkeys/17m44.01s.jpg'],'app-side theme switch',[24]),
('Settings: Interface (+Advanced)',P4,['3046:10057','3062:11379'],[('2','B. Settings categories: every readable row')],[],'config: embedded video, video-on-top, autoresize, fullscreen screen, auto-hide; app prefs',[25]),
('Settings: Privacy',P4,['3062:11911'],[('2','B. Settings categories: every readable row')],['14-settings-hotkeys/17m56.07s.jpg'],'config: save-recentplay, restore-playback-pos, metadata-network-access, lastfm-* (audioscrobbler)',[26]),
('Settings: Controls (mouse, keyboard, remotes)',P4,['6536:14482'],[('2','B. Settings categories: every readable row')],[],'config: very-short/short/medium/long-jump-size; http intf (http-port); mouse prefs app-side',[27]),
('Settings: Playback (+Advanced)',P4,['3062:12552','3072:13408'],[('2','B. Settings categories: every readable row')],['14-settings-hotkeys/18m02.07s.jpg'],'config: rate, random/loop/repeat, play-and-exit/stop, input-fast-seek, dvd/cd device, avi-index, input-timeshift-*',[28]),
('Settings: Video (+Advanced)',P4,['3073:14187','3073:15375'],[('2','B. Settings categories: every readable row')],['14-settings-hotkeys/18m02.07s.jpg'],'config: video, fullscreen, disable-screensaver, video-wallpaper, adjust, deinterlace, aspect-ratio, crop, snapshot-*',[29]),
('Settings: Audio (+inline Equalizer, startup volume, Advanced)',P4,['3073:15879','3180:17398','3178:16769','3176:16556'],[('2','B. Settings categories: every readable row')],['14-settings-hotkeys/18m08.07s.jpg','16-final-showcase/20m36.74s.jpg'],'config: audio, aout device, volume-save, replay gain, equalizer-*, spatializer, stereowiden, compressor, audio-visual, spdif, audio-resampler',[30]),
('Settings: Subtitles incl. On-Screen Messages (+Advanced)',P4,['3180:17989','6536:13908','6456:13892'],[('2','B. Settings categories: every readable row')],['14-settings-hotkeys/18m14.07s.jpg','14-settings-hotkeys/17m30.96s.jpg'],'config: spu, sub-language, subsdec-encoding, sub-autodetect-*, freetype-*, osd, video-title-show/timeout',[31]),
('Settings: Library (Playlists, Folders & Files)',P4,['6542:15251'],[('2','B. Settings categories: every readable row')],[],'config: one-instance, playlist-enqueue, recursive, show-hidden-files, metadata-network-access; vlc_ml entry points',[32]),
('Settings: Network',P4,['6543:15649'],[('2','B. Settings categories: every readable row')],[],'config: file/disc/network/live-caching, http-proxy (Windows-only in core), gnutls-system-trust',[33]),
('Settings: Performance (+Advanced)',P4,['6571:15958'],[('2','B. Settings categories: every readable row')],['14-settings-hotkeys/18m20.07s.jpg'],'config: hw decoding (videotoolbox), postproc, avcodec-skiploopfilter, avcodec-threads, drop-late-frames, plugin cache reset, clock-*',[34]),
('Settings: Recording, Casting & Streaming Out',P4,['6571:16429'],[('2','B. Settings categories: every readable row')],[],'config: input-record-path, sout-*; vlc_renderer_discovery (Chromecast)',[35]),
('Settings: Extensions ("Add-ons & Scripts")',P4,['6575:17137'],[('2','B. Settings categories: every readable row')],['14-settings-hotkeys/18m26.07s.jpg'],'Lua extensions manager, addons_manager',[36]),
('Settings dropdown popup (with ✓) and generic dropdown',P4,['2372:8300','6456:13892'],[('2','A. Settings window: chrome')],['14-settings-hotkeys/17m30.96s.jpg'],'none (control)',[37]),
('Keyboard Shortcuts dialog',P4,['2437:14832'],[('2','C. Keyboard Shortcuts dialog (NEW)')],['14-settings-hotkeys/16m02.76s.jpg'],'hotkey config key-* / global-key-* (vlc_actions)',[38]),
('About VLC (not designed; include CC BY 4.0 design credit)',P4,[],[('2','Full screen / dialog / panel inventory (implementation list)')],[],'VLC_Version(), license, authors',[44]),
('Customize Player mode (dashed outlines + tile dialog, drag sequence)',P5,['2107:5604','2160:6137','2160:6564','2160:7005','2160:7437','2160:7869','6587:19923'],[('2','A. Customize Player mode')],['15-customization-onboarding/19m12.39s.jpg','15-customization-onboarding/19m18.39s.jpg','15-customization-onboarding/19m20.29s.jpg','15-customization-onboarding/19m26.29s.jpg','16-final-showcase/20m41.42s.jpg'],'none (layout model persisted per profile)',[39]),
('Customized alternate layout result (two-row bottom bar)',P5,['2160:8301','2160:8732'],[('2','A. Customize Player mode')],['15-customization-onboarding/19m27.56s.jpg'],'none (layout model)',[40]),
('Profiles submenu + New profile',P5,['6648:20666'],[('2','B. Profiles')],['15-customization-onboarding/19m29.39s.jpg','15-customization-onboarding/19m35.39s.jpg'],'per-profile config file (config_LoadConfigFile / SaveConfigFile) + layout',[13]),
('Onboarding 1: Welcome + media folder',P5,['1899:3055'],[('2','C. Onboarding')],['15-customization-onboarding/19m46.67s.jpg'],'vlc_ml_add_entry_point (media folder)',[41]),
('Onboarding 2: Theme + accent color (9 accents)',P5,['1902:3670','1902:4020','1902:4325','1902:4634','1902:4940','1902:5245','1902:5550','1902:6160','1902:6465'],[('2','C. Onboarding')],[],'app theme/accent prefs',[42]),
('Onboarding 3: Basic keyboard shortcuts',P5,['1902:6770'],[('2','C. Onboarding')],['15-customization-onboarding/19m52.67s.jpg'],'read hotkey config (key-*) for display',[43]),
('Light theme across the app',P5,['2425:13624'],[('2','Global open questions')],['14-settings-hotkeys/17m42.54s.jpg'],'none (theme tokens)',[]),
]
# Parity: worst verdict per S-id over every judged check that names the S-id.
RANK={'missing':4,'major-diff':3,'minor-diff':2,'match':1,'not-checked':0}
LABEL={'missing':'missing','major-diff':'major diff','minor-diff':'minor diff','match':'match','not-checked':'not checked'}
PAR=json.load(open(ARGS.parity)); WORST={}; TOTAL=Counter()
for g in PAR:
    for s_ in g['screens']:
        v=s_['verdict']; TOTAL[v]+=1
        if v not in RANK: problems.append('unknown verdict %r in %s'%(v,ARGS.parity)); continue
        owners=set(re.findall(r'\b[A-J]-[a-z-]+[a-z]',s_.get('owner','')))
        for sid in set(re.findall(r'\bS(\d\d)\b',s_['screen'])):
            cur=WORST.get(sid)
            if cur is None or RANK[v]>RANK[cur[0]]: WORST[sid]=(v,owners)
            elif RANK[v]==RANK[cur[0]]: cur[1].update(owners)
# Live real-window results (checks the offscreen renders cannot make). Run 1 drove the
# installed fae8f04dc0 build (results/parity/live-run-1-window.json); later live waves
# write to ../build/evidence/final5/live — update these notes from them.
LIVE_RUN='run 1, fae8f04dc0'
LIVE={
 1:'PASS (C3, A-05-S01, CPU, PiP)',
 5:'FAIL: fullscreen top edge shows only the macOS menu bar, not the app top bar (bottom reveal and cursor hide PASS)',
 6:'PASS',
 12:'NOT-RUN (no resume prompt with the 60 s media)',
 17:'PASS (C5: sidebar overlays the video)',
 22:'PASS (queue over the video, OSD beside it)',
 72:'FAIL: Light bars ~#BCBBB8 vs #ABABAA, library tinted by the video, video rescaled when the library opens',
}
def parity(i):
    sid='%02d'%i
    if sid in WORST:
        v,o=WORST[sid]
        c=LABEL[v]+(' (%s)'%', '.join(sorted(o)) if v not in ('match','not-checked') and o else '')
    else: c='not judged'
    return c+(' · live %s [%s]'%(LIVE[i],LIVE_RUN) if i in LIVE else '')
PARITY_REL=os.path.relpath(os.path.abspath(ARGS.parity),DES)
L=[]
L.append('# Screens and implementation coverage (master list)\n')
L.append('<!-- Generated by redesign/tools/figma/gen_screens.py. Do not edit by hand: change the generator and rerun it. -->\n')
L.append('Single source of truth for what to build. It merges the 45-item inventory of `spec/spec-part2.md` (column **Inv#**), the screens and panels of `spec/spec-part1.md`, every Figma frame/component set (see `figma/INDEX.md`) and the SrDouglax node inventory (`../research/from-forks/srdouglax/reference/inventory.json`, same node ids). Design: VLC Redesign by Juxtopposed, Figma community file https://www.figma.com/community/file/1691465999134370980, CC BY 4.0 (attribution required).\n')
L.append('Columns:')
L.append('- **Figma**: node id and render. "in X.png" = the node is a variant inside that component-set render (find it by node id in `figma/figma_file.json`). Empty = not designed; build from the spec and the shared tokens/components.')
L.append('- **Spec**: section link (`p1` = spec-part1, `p2` = spec-part2). **Video**: keyframes under `../reference/video/frames/` (local only, not in git; links are relative to this file).')
L.append('- **VLC**: the core functionality each screen needs (libvlc core / vlc_player / vlc_playlist / vlc_ml / config names). "app-side" = no VLC API, store in the app.')
L.append('- **Phase**: P1 player shell & controls · P2 side panels & subtitles · P3 library/music/streams/playlists · P4 settings/hotkeys · P5 customization/onboarding/profiles. Shared tokens: `tokens/`; icons: `figma/ICONS.md`.\n')
L.append('## Implementation status\n')
L.append('Updated 2026-10-17 for branch `claude/final` (checkout `.`).\n')
L.append("""- **Status** `implemented UI`: the native SwiftUI/AppKit state exists and its supported
  actions reach the VLC backend. At `ddd9d23a9d` every area passed independent
  verification (505 Swift tests, all native suites, install). It does not by itself mean
  visual acceptance.
- **Parity · live**: visual parity against Figma and the video, from the eight offscreen
  parity judges (`%s`,
  %d checks: %d match, %d minor, %d major, %d missing, %d not checked;
  worst verdict per S-id, owning area in brackets; `not judged` = no check named the
  screen). The judges ran on the tree committed as `ddd9d23a9d`; fixes of the final-polish
  wave after it are not yet re-judged. Live results (in square brackets: which run and
  build) come from real-window groups (`../research/final-polish/results/parity/live-run-1-window.json`;
  run 1 screenshots lost, measurements stand). Every kept difference must be covered by a
  `DECISIONS.md` entry.
- Unsupported operations are not offered (D035); an operation that exists but cannot
  run now shows why.
"""%(PARITY_REL,sum(TOTAL.values()),TOTAL['match'],TOTAL['minor-diff'],TOTAL['major-diff'],TOTAL['missing'],TOTAL['not-checked']))
L.append("""Capability limits: S17 reverse playback is unavailable; S18 HDR stays Auto-only (owner,
2026-10-16) and unsupported resolution overrides are not offered; S20 unsupported
subtitle styles are not offered and cached renderer fields apply to the next media; S21
cue timelines support readable local SRT, WebVTT and ASS/SSA sources; S27 online
OpenSubtitles needs an API key/proxy; S37 physical disc/camera/microphone inputs need
hardware validation; S62 installs, removes, enables and runs local Lua extensions through
the bridge's extension-dialog provider (D039, D045), and the online add-on catalog is
not offered.
""")
for ph,title in ((P1,'P1 — Player shell & controls'),(P2,'P2 — Side panels & subtitles'),(P3,'P3 — Library, music, streams, playlists'),(P4,'P4 — Settings & hotkeys'),(P5,'P5 — Customization, onboarding, profiles')):
    L.append('## %s\n'%title)
    L.append('| ID | Screen / panel / dialog / menu | Figma node(s) → render | Spec | Video frames | VLC functionality | Inv# | Status | Parity · live |\n|---|---|---|---|---|---|---|---|---|')
    for i,s in enumerate(SCR,1):
        if s[1]!=ph: continue
        name,_,nodes,sp,vf,vlc,inv=s
        L.append('| S%02d | %s | %s | %s | %s | %s | %s | implemented UI | %s |'%(i,name,'<br>'.join(fig(n) for n in nodes) or '—','<br>'.join(spec(r) for r in sp) or '—','<br>'.join(vid(f) for f in vf) or '—',vlc,', '.join(map(str,inv)) or '—',parity(i)))
    L.append('')
unknown=sorted(set(WORST)-{'%02d'%i for i in range(1,len(SCR)+1)})
if unknown: problems.append('parity names unknown S-ids: %s'%unknown)
# coverage
inv=set(x for s in SCR for x in s[6]); miss=[i for i in range(1,46) if i not in inv]
if miss: problems.append('inventory items not mapped: %s'%miss)
ref=set(toplevel(n) for s in SCR for n in s[2]); refall=set(n for s in SCR for n in s[2])
unref=[c for c in top if c['id'] not in ref and c['type']!='TEXT']
L.append('## Coverage checks\n')
L.append('- spec-part2 inventory items 1–45: all mapped%s.'%('' if not miss else ' except %s'%miss))
L.append('- Top-level Figma layers not referenced by a screen above (components used through other screens, or not UI): '+', '.join('`%s` %s'%(c['id'],c['name']) for c in unref)+'.')
L.append('- `3336:11929` (Add Subtitles duplicate) is intentionally not referenced. The two TEXT labels "Components"/"Designs" are not UI.')
L.append('- Video frames referenced: %d, all present locally.'%len(set(f for s in SCR for f in s[4])) if not any('missing video' in p for p in problems) else '- Some video frames are missing locally; see problems.')
L.append('\n## Notes for implementers\n')
L.append('- macOS adaptation (spec-part2 global question 4): the design draws Windows-style minimize/maximize/close; decide traffic lights vs custom glyphs once in S01 and reuse.')
L.append('- Figma prototype placeholders that are not design intent (About VLC → Customize, right-click Playlist → Keyboard Shortcuts, key V → Add Subtitles, key F → Hide UI): see `../research/from-forks/pyr0zen/FIGMA_FLOWS.md`. Conflicts between the prototype and the video are listed there too (e.g. Playback tab rows, volume max 200 %).')
L.append('- The ⋯ menu final list (Figma `menu`) drops Stream, Open from Clipboard and Plugins & Extensions that appear in earlier video versions; implement the Figma list and keep Stream/Clipboard reachable from S37.')
TEXT='\n'.join(L)+'\n'
TARGET=ARGS.out or DES+'/SCREENS.md'
if ARGS.check:
    same=os.path.exists(TARGET) and open(TARGET,encoding='utf-8').read()==TEXT
    print('SCREENS.md is %s'%('up to date' if same else 'STALE: rerun gen_screens.py')); sys.exit(0 if same else 1)
open(TARGET,'w',encoding='utf-8').write(TEXT)
print('screens',len(SCR)); print('\n'.join(problems)); print('unref',[(c['id'],c['name']) for c in unref])
