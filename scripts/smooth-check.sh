#!/usr/bin/env bash
# Smooth motion check: replays recordings unthrottled with --smooth-check (every picture in between drawn) and lists
# the draws it flags: matched 3D draws drawn apart from a part of a model next to them that moved as they did.
# Fails when any are flagged. Logs stay in --out (they name vblanks to look at with --window-shot).
#
# The runs below are placeholders (vblanks picked during first boot): update them once recordings exist.
#
#   scripts/smooth-check.sh
#   scripts/smooth-check.sh --runs boot
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

runs=boot
out=build/smooth-check
dir=data/recordings
exe=build/linux-x64-release/jdarc
game_dir=data/original
cooked_dir=data/cooked
while [ $# -gt 0 ]; do
    case "$1" in
        --runs) runs="$2"; shift 2 ;;
        --out) out="$2"; shift 2 ;;
        --dir) dir="$2"; shift 2 ;;
        --exe) exe="$2"; shift 2 ;;
        --game-dir) game_dir="$2"; shift 2 ;;
        --cooked-dir) cooked_dir="$2"; shift 2 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

cd "$root"
[ -x "$exe" ] || { echo "$exe not found; build first (scripts/build.sh --preset linux-x64-release)" >&2; exit 1; }
exe="$(readlink -f "$exe")"; game="$(readlink -f "$game_dir")"; cooked="$(readlink -f "$cooked_dir")"
recordings="$(readlink -f "$dir")"
mkdir -p "$out"; out="$(readlink -f "$out")"

ini="$out/smooth-check.ini"
printf '%s\n' renderer=vulkan fullscreen=0 volume=0 frame_limit=1 vsync=1 refresh_60hz=1 show_fps=0 \
    frame_skip=1 hd_textures=1 fill_screen=0 smooth_motion=1 msaa=1 scale=2 > "$ini"

# name: recording, last vblank (placeholders)
rec_for_boot=boot.txt
last_for_boot=3600

mkdir -p "$root/run"
cd "$root/run"  # (test games run from run/: its pipeline cache and settings)
flagged=0
IFS=',' read -ra names <<< "$runs"
for name in "${names[@]}"; do
    case "$name" in
        boot) rec="$rec_for_boot"; last="$last_for_boot" ;;
        *) echo "unknown run $name (known: boot)" >&2; exit 2 ;;
    esac
    log="$out/$name.log"
    start="$(date +%s)"
    "$exe" "$game" --cooked "$cooked" --no-audio --unthrottled --smooth-check --settings "$ini" \
        --replay "$recordings/$rec" --vblanks "$last" > "$log" 2>&1
    lines="$(grep -c 'smooth check, ' "$log" || true)"
    flagged=$((flagged + lines))
    printf '%-6s %4d flagged  %ds\n' "$name" "$lines" "$(( $(date +%s) - start ))"
    grep 'smooth check, ' "$log" | head -n 10 | sed 's/^.*smooth check, /  /'
done
if [ "$flagged" -gt 0 ]; then echo "$flagged draws flagged (logs in $out)" >&2; exit 1; fi
echo 'nothing flagged'
