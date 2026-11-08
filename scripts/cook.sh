#!/usr/bin/env bash
# Cooks the movie media the game loads besides the disc: PSMF video becomes AV1/IVF and its ATRAC3plus
# audio becomes Ogg (needs FFmpeg with the SVT-AV1 and Vorbis encoders). Existing outputs are kept, so an
# interrupted run can be resumed. Missing audio is silent and missing video is black at runtime.
#
#   scripts/cook.sh                                   # data/original -> data/cooked
#   scripts/cook.sh --preset linux-x64-release -- --force --limit 1
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

preset=linux-x64-debug
game_dir=data/original
cooked_dir=data/cooked
while [ $# -gt 0 ]; do
    case "$1" in
        --preset) preset="$2"; shift 2 ;;
        --game-dir) game_dir="$2"; shift 2 ;;
        --cooked-dir) cooked_dir="$2"; shift 2 ;;
        --) shift; break ;;
        -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
        *) break ;;
    esac
done

cd "$root"
cmake --build --preset "$preset" --target jdcook
exe="$root/build/$preset/tools/jdcook/jdcook"
[ -x "$exe" ] || { echo "$exe not found after building jdcook" >&2; exit 1; }
exec "$exe" "$game_dir" "$cooked_dir" "$@"
