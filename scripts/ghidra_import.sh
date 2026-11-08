#!/usr/bin/env bash
# Builds a Ghidra project for BOOT.BIN: relocated image at this game's load base + all recovered symbols.
#
#   scripts/ghidra_import.sh [--ghidra ~/ghidra_12.1.4_PUBLIC] [--language MIPS:LE:32:default]
#
# Needs a debug build (scripts/build.sh), data/nids.tsv (see README) and a JDK supported by your Ghidra
# (Ghidra 12 requires JDK 21; set JAVA_HOME if several JDKs are installed).
# The default language comes from the ghidra-allegrex extension (Allegrex integer + FPU + VFPU), installed in
# ~/.config/ghidra/<ghidra version>/Extensions. Without it, pass --language MIPS:LE:32:default (stock MIPS
# does not know the VFPU, so functions using vector instructions are only partly disassembled).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ghidra="${GHIDRA_HOME:-}"
language=Allegrex:LE:32:default
base=0x08804000
preset=linux-x64-debug
while [ $# -gt 0 ]; do
    case "$1" in
        --ghidra) ghidra="$2"; shift 2 ;;
        --language) language="$2"; shift 2 ;;
        --base) base="$2"; shift 2 ;;
        --preset) preset="$2"; shift 2 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
[ -n "$ghidra" ] || { echo "pass --ghidra <dir> or set GHIDRA_HOME" >&2; exit 2; }

boot="$root/data/original/PSP_GAME/SYSDIR/BOOT.BIN"
psprx="$root/build/$preset/psprecore/tools/psprx/psprx"
out="$root/build/ghidra"
mkdir -p "$out"
[ -x "$psprx" ] || { echo "$psprx not found; build first (scripts/build.sh --preset $preset)" >&2; exit 1; }

"$psprx" image "$boot" "$base" "$out/boot_${base}.bin"
"$psprx" symbols "$boot" "$root/data/nids.tsv" "$out/symbols.tsv" "$base" "$out/ghidra_symbols.txt"

"$ghidra/support/analyzeHeadless" "$out" JDARC -overwrite \
    -import "$out/boot_${base}.bin" -loader BinaryLoader -loader-baseAddr "$base" -processor "$language" \
    -scriptPath "$root/tools/ghidra" -preScript ImportJDARCSymbols.java "$out/ghidra_symbols.txt"
echo "Ghidra project: $out/JDARC.gpr"
