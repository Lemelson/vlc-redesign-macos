#!/bin/sh
# Adds the community Qt redesign forks as read-only, blob-less git remotes
# so they can be diffed against upstream (see redesign/research/FORKS.md).
# Usage: redesign/tools/add-fork-remotes.sh   (run from the repo root)
set -e

add() {
    name=$1 url=$2; shift 2
    git remote remove "$name" 2>/dev/null || true
    git config "remote.$name.url" "$url"
    for b in "$@"; do
        git config --add "remote.$name.fetch" "+refs/heads/${b}:refs/remotes/${name}/${b}"
    done
    git config "remote.$name.tagOpt" --no-tags
    git config "remote.$name.promisor" true
    git config "remote.$name.partialclonefilter" blob:none
}

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/videolan/vlc.git

add fork-dsojevic       https://github.com/dsojevic/vlc.git                    juxtopposed-redesign
add fork-Pyr0zen        https://github.com/Pyr0zen/vlc.git                     redesign redesign-library
add fork-Olmo-Gutierrez https://github.com/Olmo-Gutierrez/VLC-juxtopposed.git  redesign
add fork-Geckostya      https://github.com/Geckostya/vlc-Juxtopposed-redesign.git 'redesign/stage1'
add fork-SrDouglax      https://github.com/SrDouglax/JuxtopposedVLC.git        'feat/m2'
add fork-Hamido212      https://github.com/Hamido212/vlc.git                   redesign adopt-dsojevic-preferences
add fork-ItsAhadun      https://github.com/ItsAhadun/vlc-redesign.git          'claude/magical-mccarthy-7co0gu'
add fork-KoalaNalle     https://github.com/KoalaNalle/vlc-juxtopposed.git      juxtopposed-playback-bar
add fork-floklein       https://github.com/floklein/jvlc.git                   'feat/redesign' 'research/*'
add fork-ExPikaPaka     https://github.com/ExPikaPaka/vlc-ui-redesign.git      'redesign/08-volume-wedge'
add fork-Green-Skeleton https://github.com/Green-Skeleton/vlc-redesign.git     redesign
add fork-stonepicaxe    https://github.com/stonepicaxe/vlc.git                 'redesign/figma-ui'
add fork-ldl1949        https://github.com/ldl1949/vlc-New-UI.git              redesign-phase2
add fork-webmaster94    https://github.com/webmaster94/vlc-redesign.git        redesign
add fork-lin-ycv        https://github.com/lin-ycv/vlc.git                     windows-figma-vlc-3.0.24
add fork-mholtzhausen   https://github.com/mholtzhausen/vlc.git                master

git fetch --multiple --filter=blob:none $(git remote | grep '^fork-')
