#!/usr/bin/env bash
# Runs the game with the repository's layout: the disc from data/original, cooked media from data/cooked, and run/
# as the working directory (settings, saves, mods, the shader cache, dumps). Game arguments follow --.
#
#   scripts/run.sh                                                    # play
#   scripts/run.sh -- --replay ../data/recordings/boot.txt --unthrottled  # replay a recording
#   scripts/run.sh --preset linux-x64-debug --perf
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

preset=linux-x64-release
while [ $# -gt 0 ]; do
    case "$1" in
        --preset) preset="$2"; shift 2 ;;
        --) shift; break ;;
        -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
        *) break ;;
    esac
done

exe="$root/build/$preset/jdarc"
[ -x "$exe" ] || { echo "$exe not found; build first (scripts/build.sh --preset $preset)" >&2; exit 1; }
mkdir -p "$root/run"
cd "$root/run"
exec "$exe" "$root/data/original" --cooked "$root/data/cooked" "$@"
