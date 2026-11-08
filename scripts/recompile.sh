#!/usr/bin/env bash
# Recompiles BOOT.BIN to C (data/generated) with a host psprecomp build. Picks the preset for you:
# --preset wins, otherwise the first configured host build that already has psprecomp, otherwise the
# platform default. Android presets build no host tools, so they are rejected (recompilation always
# runs on the host, even when the game itself targets a device).
#
#   scripts/recompile.sh                              # auto-detect preset
#   scripts/recompile.sh --preset linux-x64-release -- --help  # extra args go to psprecomp
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

preset=""
boot=data/original/PSP_GAME/SYSDIR/BOOT.BIN
out=data/generated
while [ $# -gt 0 ]; do
    case "$1" in
        --preset) preset="$2"; shift 2 ;;
        --boot) boot="$2"; shift 2 ;;
        --out-dir) out="$2"; shift 2 ;;
        --) shift; break ;;
        -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
        *) break ;;
    esac
done

if [ -z "$preset" ]; then
    for c in linux-x64-debug linux-x64-release linux-x64-profile windows-x64-debug windows-x64-release; do
        if [ -x "$root/build/$c/psprecore/tools/psprecomp/psprecomp" ]; then preset="$c"; break; fi
    done
fi
if [ -z "$preset" ]; then
    case "$(uname -s)" in
        Linux*) preset=linux-x64-debug ;;
        *) preset=windows-x64-debug ;;
    esac
fi
case "$preset" in
    android-*) echo "$preset builds no host tools; pass a host preset (e.g. --preset linux-x64-debug)" >&2; exit 2 ;;
esac

cd "$root"
cmake --build --preset "$preset" --target psprecomp
exe="$root/build/$preset/psprecore/tools/psprecomp/psprecomp"
[ -x "$exe" ] || { echo "$exe not found after building psprecomp" >&2; exit 1; }
"$exe" "$boot" "$out" --overrides "$root/src/decomp" --seeds "$root/seeds.txt" "$@"
echo "done; re-run scripts/build.sh --preset $preset to pick up the generated code"
