#!/usr/bin/env bash
# Regression check: replays every recording headless and compares the game's RAM state hashes with the stored
# references (determinism and behaviour after a change). Recordings and references stay local (they derive from
# the game and your saves): <dir>/NAME.txt from --record, with NAME.state next to it.
#
#   scripts/regress.sh                  # check every recording that has a reference
#   scripts/regress.sh --update         # (re)write the references from the current build
#   scripts/regress.sh --dir /mnt/rec --exe build/linux-x64-debug/jdarc
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

dir=data/recordings
exe=build/linux-x64-release/jdarc
game_dir=data/original
cooked_dir=data/cooked   # movie frames reach the game's RAM: replays need the same cooked media
every=500               # vblanks between hashes
update=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dir) dir="$2"; shift 2 ;;
        --exe) exe="$2"; shift 2 ;;
        --game-dir) game_dir="$2"; shift 2 ;;
        --cooked-dir) cooked_dir="$2"; shift 2 ;;
        --every) every="$2"; shift 2 ;;
        --update) update=1; shift ;;
        -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

cd "$root"
[ -x "$exe" ] || { echo "$exe not found; build first (scripts/build.sh)" >&2; exit 1; }

recordings=()
for r in "$dir"/*.txt; do
    [ -f "$r" ] || continue
    head -n 1 "$r" | grep -qE '^(psprecore|jdarc)-input ' || continue
    if [ "$update" -eq 0 ]; then
        [ -f "${r%.txt}.state" ] || continue
    fi
    recordings+=("$r")
done
[ "${#recordings[@]}" -gt 0 ] || { echo "no recordings${update:+} in $dir" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pids=()
for r in "${recordings[@]}"; do
    last="$(tail -n 1 "$r" | cut -d' ' -f1)"
    out="$tmp/$(basename "$r" .txt).hashes"
    "$exe" "$game_dir" --headless --cooked "$cooked_dir" --replay "$r" --vblanks "$last" --state-hash "$every" \
        2>&1 | grep 'state vblank ' > "$out" &
    pids+=($!)
done
for p in "${pids[@]}"; do wait "$p" || true; done

failed=0
for r in "${recordings[@]}"; do
    name="$(basename "$r" .txt)"
    ref="${r%.txt}.state"
    hashes="$tmp/$name.hashes"
    if [ ! -s "$hashes" ]; then echo "FAIL  $name (no state hashes; the replay did not run)"; failed=$((failed + 1)); continue; fi
    if [ "$update" -eq 1 ]; then
        cp "$hashes" "$ref"
        echo "wrote $name ($(wc -l < "$hashes") hashes)"
        continue
    fi
    if cmp -s "$ref" "$hashes"; then
        echo "ok    $name ($(wc -l < "$ref") hashes)"
    else
        echo "FAIL  $name  first difference: expected '$(head -n 1 "$ref")', got '$(head -n 1 "$hashes")'"
        failed=$((failed + 1))
    fi
done
[ "$failed" -eq 0 ] || { echo "$failed recording(s) differ" >&2; exit 1; }
