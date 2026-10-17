#!/bin/sh
# Optional engine patch series (DECISIONS.md D031). Our checkout keeps src/
# identical to upstream; these patches are only ever applied to copies.
#
#   engine-patches.sh check [SOURCE]
#       Fail if a patch is already present in SOURCE (merged upstream, or src/
#       was edited against D031). Warn if a patch no longer applies.
#   engine-patches.sh files OUT [SOURCE]
#       Write only the files the series touches, patched, under OUT.
#       Fail loudly if a patch does not apply or is already present.
#   engine-patches.sh copy DEST [SOURCE]
#       Mirror SOURCE into DEST and apply the series there. Unchanged files
#       keep their timestamps, so a build configured against DEST stays
#       incremental. Used by tools/build-native.sh when MXR_ENGINE_PATCHES=1.
#
# SOURCE defaults to the checkout that contains this script. It is never
# modified.
set -eu
# Lists below are newline-separated, so paths with spaces stay whole.
IFS='
'

mxr_patch_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
mxr_default_source=$(CDPATH= cd -- "$mxr_patch_dir/../../.." && pwd -P)

mxr_die() { printf 'engine-patches: %s\n' "$*" >&2; exit 1; }

mxr_series() {
    for mxr_p in "$mxr_patch_dir"/[0-9][0-9][0-9][0-9]-*.patch; do
        [ -f "$mxr_p" ] && printf '%s\n' "$mxr_p"
    done
}

# Paths touched by the series, relative to the source root.
mxr_touched() {
    mxr_series | while IFS= read -r mxr_p; do
        sed -n 's|^+++ b/||p' "$mxr_p"
    done | sort -u
}

# git apply must not discover a repository above the directory it patches.
mxr_apply() {
    mxr_dir=$1; shift
    (cd "$mxr_dir" && GIT_CEILING_DIRECTORIES=$(dirname -- "$(pwd -P)") \
        git apply "$@")
}

mxr_check() {
    mxr_source=$(CDPATH= cd -- "${1:-$mxr_default_source}" && pwd -P)
    # git apply only sees paths below the directory it runs in: require the top level.
    mxr_top=$(git -C "$mxr_source" rev-parse --show-toplevel 2>/dev/null) || mxr_top=
    if [ -z "$mxr_top" ] || [ "$(CDPATH= cd -- "$mxr_top" && pwd -P)" != "$mxr_source" ]; then
        echo "engine-patches: $mxr_source is not the top of a git checkout; check skipped" >&2
        return 0
    fi
    mxr_status=0
    for mxr_p in $(mxr_series); do
        mxr_name=$(basename -- "$mxr_p")
        if git -C "$mxr_source" apply --check --reverse "$mxr_p" 2>/dev/null; then
            printf '%s\n' \
                "engine-patches: $mxr_name is already present in $mxr_source." \
                "  If upstream merged it, delete the patch from redesign/patches/engine/." \
                "  Otherwise src/ was edited: restore it to upstream (D031)." >&2
            mxr_status=1
        elif ! git -C "$mxr_source" apply --check "$mxr_p" 2>/dev/null; then
            echo "engine-patches: warning: $mxr_name no longer applies; refresh it before building with MXR_ENGINE_PATCHES=1" >&2
        fi
    done
    return "$mxr_status"
}

mxr_files() {
    mxr_out=$1
    mxr_source=$(CDPATH= cd -- "${2:-$mxr_default_source}" && pwd -P)
    [ -n "$(mxr_series)" ] || mxr_die "no patches in $mxr_patch_dir"
    mkdir -p "$mxr_out"
    for mxr_f in $(mxr_touched); do
        [ -f "$mxr_source/$mxr_f" ] || mxr_die "$mxr_f is missing from $mxr_source"
        mkdir -p "$mxr_out/$(dirname -- "$mxr_f")"
        cp "$mxr_source/$mxr_f" "$mxr_out/$mxr_f"
    done
    for mxr_p in $(mxr_series); do
        mxr_name=$(basename -- "$mxr_p")
        if mxr_apply "$mxr_out" --check "$mxr_p" 2>/dev/null; then
            mxr_apply "$mxr_out" "$mxr_p"
        elif mxr_apply "$mxr_out" --check --reverse "$mxr_p" 2>/dev/null; then
            mxr_die "$mxr_name is already in the source (merged upstream?). Delete it from redesign/patches/engine/ or restore src/ (D031)."
        else
            mxr_apply "$mxr_out" --check "$mxr_p" || true
            mxr_die "$mxr_name no longer applies to $mxr_source; refresh the series against current upstream."
        fi
    done
}

mxr_copy() {
    mxr_dest=$1
    mxr_source=$(CDPATH= cd -- "${2:-$mxr_default_source}" && pwd -P)
    mkdir -p "$mxr_dest"
    mxr_dest=$(CDPATH= cd -- "$mxr_dest" && pwd -P)
    case "$mxr_dest/" in
        "$mxr_source/"*) mxr_die "the patched copy must be outside the checkout" ;;
    esac
    mxr_stage=$(mktemp -d "${TMPDIR:-/tmp}/mxr-engine-patches.XXXXXX")
    trap 'rm -rf "$mxr_stage"' EXIT HUP INT TERM
    mxr_files "$mxr_stage/patched" "$mxr_source"

    # Mirror everything except VCS data, Swift scratch, generated revision
    # files and the patched files (copied below only when their content changes).
    mxr_excludes="$mxr_stage/excludes"
    {
        printf '%s\n' '/.git' '.build/' '__pycache__/' '/src/revision.txt' '/src/revision.c'
        mxr_touched | sed 's|^|/|'
    } > "$mxr_excludes"
    rsync -a --delete --exclude-from="$mxr_excludes" "$mxr_source/" "$mxr_dest/"
    for mxr_f in $(mxr_touched); do
        if ! cmp -s "$mxr_stage/patched/$mxr_f" "$mxr_dest/$mxr_f"; then
            mkdir -p "$mxr_dest/$(dirname -- "$mxr_f")"
            cp "$mxr_stage/patched/$mxr_f" "$mxr_dest/$mxr_f"
        fi
    done

    # The copy has no .git: VLC's revision rule falls back to src/revision.txt,
    # which marks the build as engine-patched.
    mxr_revision=$(git -C "$mxr_source" describe --tags --long --match '?.*.*' --always 2>/dev/null || echo exported)
    printf '%s-engine-patches\n' "$mxr_revision" > "$mxr_stage/revision.txt"
    cmp -s "$mxr_stage/revision.txt" "$mxr_dest/src/revision.txt" \
        || cp "$mxr_stage/revision.txt" "$mxr_dest/src/revision.txt"

    {
        printf 'source %s\n' "$mxr_source"
        printf 'revision %s\n' "$(git -C "$mxr_source" rev-parse HEAD 2>/dev/null || echo unknown)"
        for mxr_p in $(mxr_series); do
            printf 'patch %s %s\n' "$(shasum -a 256 "$mxr_p" | cut -d' ' -f1)" "$(basename -- "$mxr_p")"
        done
    } > "$mxr_dest/.mxr-engine-patches"
    echo "engine-patches: $(mxr_series | wc -l | tr -d ' ') patches applied to $mxr_dest" >&2
}

case "${1:-}" in
    check) shift; mxr_check "$@" ;;
    files) [ "$#" -ge 2 ] || mxr_die "usage: $0 files OUT [SOURCE]"; shift; mxr_files "$@" ;;
    copy) [ "$#" -ge 2 ] || mxr_die "usage: $0 copy DEST [SOURCE]"; shift; mxr_copy "$@" ;;
    *) mxr_die "usage: $0 check [SOURCE] | files OUT [SOURCE] | copy DEST [SOURCE]" ;;
esac
