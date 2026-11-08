#!/usr/bin/env bash
# Configure, build and (optionally) test a Linux preset.
#
#   scripts/build.sh                              # linux-x64-debug, build + tests
#   scripts/build.sh --preset linux-x64-release --no-test
#   scripts/build.sh --preset linux-x64-profile --no-test   # RelWithDebInfo + Tracy (port 8086)
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

preset=linux-x64-debug
no_test=0
targets=()
while [ $# -gt 0 ]; do
    case "$1" in
        --preset) preset="$2"; shift 2 ;;
        --target) targets+=("$2"); shift 2 ;;
        --no-test) no_test=1; shift ;;
        -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

# A profile preset's first configure takes the third-party sources its release preset fetched (no second download).
reused=()
case "$preset" in
    *-profile)
        deps="$root/build/${preset%-profile}-release/_deps"
        if [ -d "$deps" ]; then
            for d in "$deps"/*-src; do
                [ -d "$d" ] || continue
                name="$(basename "$d")"; name="${name%-src}"
                reused+=("-DFETCHCONTENT_SOURCE_DIR_${name^^}=$d")
            done
        fi
        ;;
esac

cd "$root"
cmake --preset "$preset" "${reused[@]}"
if [ "${#targets[@]}" -gt 0 ]; then
    cmake --build --preset "$preset" --target "${targets[@]}"
else
    cmake --build --preset "$preset"
fi
if [ "$no_test" -eq 0 ] && [ "${#targets[@]}" -eq 0 ]; then
    ctest --preset "$preset"
fi
