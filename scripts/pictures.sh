#!/usr/bin/env bash
# Picture check: replays recordings unthrottled and writes a fixed set of pictures, then compares them with a
# reference set. Next to regress.sh (the game's RAM): the pictures, for changes that must not alter what is drawn.
# Pictures and recordings stay local (they show the game).
#
# The runs below are placeholders (vblanks picked during first boot): update them with your own recordings (see docs/testing.md).
#
#   scripts/pictures.sh --out build/pictures-ref                          # write a reference set
#   scripts/pictures.sh --out build/pictures-new --reference build/pictures-ref   # write and compare
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

out=""
reference=""
dir=data/recordings
exe=build/linux-x64-release/jdarc
game_dir=data/original
cooked_dir=data/cooked
while [ $# -gt 0 ]; do
    case "$1" in
        --out) out="$2"; shift 2 ;;
        --reference) reference="$2"; shift 2 ;;
        --dir) dir="$2"; shift 2 ;;
        --exe) exe="$2"; shift 2 ;;
        --game-dir) game_dir="$2"; shift 2 ;;
        --cooked-dir) cooked_dir="$2"; shift 2 ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
[ -n "$out" ] || { echo "--out is required" >&2; exit 2; }

cd "$root"
[ -x "$exe" ] || { echo "$exe not found; build first (scripts/build.sh --preset linux-x64-release)" >&2; exit 1; }
exe="$(readlink -f "$exe")"; game="$(readlink -f "$game_dir")"; cooked="$(readlink -f "$cooked_dir")"
recordings="$(readlink -f "$dir")"
mkdir -p "$out"; out="$(readlink -f "$out")"
[ -n "$reference" ] && reference="$(readlink -f "$reference")"
rm -f "$out"/*.png  # (pictures this script wrote before)

# Settings without anything that differs from run to run (the FPS counter).
ini="$out/pictures.ini"
printf '%s\n' renderer=vulkan fullscreen=0 volume=0 frame_limit=1 vsync=1 refresh_60hz=1 show_fps=0 \
    button_glyphs=playstation frame_skip=1 hd_textures=1 fill_screen=0 smooth_motion=1 msaa=1 scale=2 scale=2 > "$ini"

# name, recording, settings, extra arguments, last vblank (placeholders: fill in with real runs)
mkdir -p "$root/run"
cd "$root/run"  # (test games run from run/: its pipeline cache and settings)
run_one() { # name rec settings extra... -- last
    local name="$1" rec="$2" settings="$3"; shift 3
    local start
    start="$(date +%s)"
    "$exe" "$game" --cooked "$cooked" --no-audio --unthrottled --settings "$settings" \
        --replay "$recordings/$rec" --vblanks "${@: -1}" "${@:1:$#-1}" > "$out/$name.log" 2>&1
    local count
    count="$(ls "$out/$name"*.png 2>/dev/null | wc -l)"
    printf '%-15s %3d pictures  %ds\n' "$name" "$count" "$(( $(date +%s) - start ))"
}
run_one boot boot.txt "$ini" --screenshot-every "300:$out/boot" 3600

if [ -n "$reference" ]; then
    differ=0
    total=0
    while IFS= read -r n; do
        total=$((total + 1))
        if [ ! -f "$reference/$n" ]; then echo "new      $n"; differ=$((differ + 1)); continue; fi
        if [ ! -f "$out/$n" ]; then echo "missing  $n"; differ=$((differ + 1)); continue; fi
        a="$(sha256sum "$reference/$n" | cut -d' ' -f1)"; b="$(sha256sum "$out/$n" | cut -d' ' -f1)"
        if [ "$a" != "$b" ]; then echo "differs  $n"; differ=$((differ + 1)); fi
    done < <(find "$reference" "$out" -maxdepth 1 -name '*.png' -printf '%f\n' 2>/dev/null | sort -u)
    if [ "$differ" -gt 0 ]; then echo "$differ of $total pictures differ from $reference" >&2; exit 1; fi
    echo "all $total pictures identical to $reference"
fi
