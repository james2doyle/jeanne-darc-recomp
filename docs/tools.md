# Tool reference

The game-specific tools live in `tools/` (thin wrappers over `psprecore/tools/`); the scripts in
`scripts/` drive the common workflows on Linux (`.sh`) and Windows (`.ps1`).

## psprx: inspecting the executable

`psprx` works on the game executable (`PSP_GAME/SYSDIR/BOOT.BIN`, an unencrypted PRX):

```
psprx info    BOOT.BIN                  # module info, segments, imports/exports, relocation stats
psprx nids    "PSP SDK/pspsdk-MINPSPW/psp/sdk/lib" data/nids.tsv   # NID names from local SDK stubs
psprx imports BOOT.BIN data/nids.tsv   # all imported system functions with names
psprx image   BOOT.BIN 0x08804000 build/boot.bin   # relocated memory image (this game's load base)
psprx disasm  BOOT.BIN                  # objdump-compatible listing (psprecore/scripts/check_allegrex.ps1 diffs it)
psprx symbols BOOT.BIN data/nids.tsv build/symbols.tsv 0x08804000 build/ghidra_symbols.txt
```

## psprecomp: translating it to C

`scripts/recompile.sh` translates BOOT.BIN into C (see
[psprecore/docs/recompiler.md](../psprecore/docs/recompiler.md)): it finds or builds a host
`psprecomp` and runs
`psprecomp data/original/PSP_GAME/SYSDIR/BOOT.BIN data/generated --overrides src/decomp --seeds seeds.txt`.
Android presets build no host tools, so recompilation always uses a host preset even when the
game itself targets a device.

Game functions can be replaced by hand-written C++ in `src/decomp/` (`GAME_FUNC`); see
[docs/decompilation.md](decompilation.md).

## Ghidra

`scripts/ghidra_import.sh` builds a Ghidra project for BOOT.BIN: the relocated image at the
load base plus all recovered symbols. Needs a debug build, `data/nids.tsv`, and a supported JDK
(Ghidra 12 requires JDK 21). The default language comes from the ghidra-allegrex extension
(Allegrex integer + FPU + VFPU); without it, pass `--language MIPS:LE:32:default` (stock MIPS
does not know the VFPU, so functions using vector instructions are only partly disassembled).

## Analysis scripts

Throwaway analysis scripts: [tools/analysis/](../tools/analysis/) (generic ones in
`psprecore/tools/analysis/`).
