#!/bin/sh
# Recreates the local-only reference material next to the repo:
#   ../reference/video/       the video, transcript, scene frames sorted by topic
#   ../reference/standalone/  standalone (non-VLC-fork) implementations of the design
# The video and its frames are Juxtopposed's copyrighted material: they are used
# locally as a design reference and must never be committed.
# Requires: yt-dlp, ffmpeg, python3, git. Optional: parakeet-mlx (transcription).
# Usage: redesign/tools/fetch-reference.sh   (run from the repo root)
set -e

REF=$(cd "$(dirname "$0")/../../.." && pwd)/reference
VIDEO_URL=https://www.youtube.com/watch?v=ERFeOgqk324
mkdir -p "$REF/video" "$REF/standalone"
cd "$REF/video"

MP4=juxtopposed-vlc-redesign-1080p.mp4
if [ ! -f "$MP4" ]; then
    yt-dlp --ignore-config -f 'bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080]' \
        --merge-output-format mp4 -o "$MP4" "$VIDEO_URL"
fi

if [ ! -f audio.srt ] && command -v parakeet-mlx >/dev/null; then
    ffmpeg -v error -y -i "$MP4" -ac 1 -ar 16000 audio.wav
    parakeet-mlx --output-format srt audio.wav
    rm -f audio.wav
fi

if [ ! -d frames ]; then
    mkdir -p _all
    ffmpeg -hide_banner -an -i "$MP4" \
        -vf "select='gt(scene,0.08)+isnan(prev_selected_t)+gte(t-prev_selected_t,6)',showinfo" \
        -vsync vfr -q:v 2 _all/f_%04d.jpg 2>&1 | grep -o 'pts_time:[0-9.]*' > _times.txt
    python3 -I - <<'EOF'
import os, re, shutil
times = [float(t) for t in re.findall(r'pts_time:([\d.]+)', open('_times.txt').read())]
sections = [(0, '01-intro-colors-icons'), (90, '02-control-bar-seekbar-volume'),
    (210, '03-top-bar-fullscreen-hover'), (240, '04-subtitle-audio-buttons'),
    (300, '05-menus-right-click'), (330, '06-subtitle-import-dialog'),
    (390, '07-sidebar-subs-audio-video-playback'), (560, '08-media-library'),
    (720, '09-music'), (740, '10-network-streams-open-dialogs'),
    (795, '11-playlists-pins-recent-home'), (843, '12-continue-watching'),
    (853, '_sponsor-skip'), (895, '13-bookmarks-chapters-osd'), (925, '14-settings-hotkeys'),
    (1125, '15-customization-onboarding'), (1195, '16-final-showcase'), (1245, '_outro')]
for f, t in zip(sorted(os.listdir('_all')), times):
    name = [n for s, n in sections if t >= s][-1]
    os.makedirs(f'frames/{name}', exist_ok=True)
    shutil.move(f'_all/{f}', f'frames/{name}/{int(t // 60):02d}m{t % 60:05.2f}s.jpg')
EOF
    rm -rf _all _times.txt
fi

cd "$REF/standalone"
for r in Sayandeep1013/vlc-skins nirmaljosephukken/pylon-player nagasab221/vlc-redesign \
         Green-Skeleton/vlc-redesign-skin s1rd0/BettererVLC; do
    d=$(echo "$r" | tr / _)
    [ -d "$d" ] || git clone -q --depth 50 "https://github.com/$r.git" "$d"
done
echo "Reference material ready in $REF"
