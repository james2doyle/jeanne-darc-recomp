# JDARCRECOMP

A native PC (Windows/Linux) and Android port of the PSP game *Jeanne d'Arc*,
built by static recompilation and progressive decompilation.

**This repository contains no game code or assets.** You need your own copy of the game
(UCUS-98700, USA). Everything derived from it is generated locally and never committed.

## Layout

```
src/            the game's own code (main, mods) and hand-written replacements (src/decomp)
libs/           the game's file formats (currently: SPF container check)
tools/          game-specific tools (analysis scripts; a jdcook media baker comes later)
tests/ docs/ scripts/ android/
psprecore/      the recompiler and runtime (submodule)
data/           your game copy and everything derived from it (git-ignored):
  original/       the disc folder (PSP_GAME/...) extracted from your own game.iso
  generated/      C code recompiled from BOOT.BIN (psprecomp)
  cooked/         what the game loads besides the disc: audio, movies, textures
  recordings/     play sessions for replays and regression tests
assets/         game assets unpacked for editing (textures/), high-resolution matches (textures-hd/), packed by
                the build (git-ignored)
run/            the working directory for playing: settings, saves, mods, shader cache (git-ignored)
build/          CMake output
```

The recompiler and runtime are [psprecore](https://github.com/AdamFull/psprecore), a git submodule
(it brings [nx-foundation](https://github.com/AdamFull/nx-foundation) along); this repository adds
what is specific to Jeanne d'Arc: its file formats and tools, the game's own code (`src/`),
translations later, the Android app and the scripts. Unlike Crisis Core, Jeanne d'Arc keeps loose files
on the disc (per-stage `DATA/AS*/` folders), so there is no archive tool: mods overlay whole files.

- Throwaway analysis scripts: [tools/analysis/](tools/analysis/) (generic ones in `psprecore/tools/analysis/`)

## Status

Boots through the opening movie to the title screen, and NEW GAME reaches the `DEMO0000`
cutscene (both verified frame-by-frame from cooked `movies/*.ivf`). The cathedral scene renders, and the
`TITLE.GIM` logo/prompt/copyright draw via GE `BEZIER` patches (the runtime tessellates them;
the old full-texture clear-quad overlay, which showed duplicate menus and `[ Debug ]`, is gone).
The runtime's sceMpeg HLE covers the game's direct-sceMpeg path (`scePsmfSetPsmf/GetVideoInfo`,
`AvcInitYCbCr`/`AvcDecodeYCbCr`/`AvcDecodeStopYCbCr`/`AvcCsc`, stream-size EOF with `dts=-1`),
and `sceKernelTerminateDeleteThread` unwinds parked host threads instead of hanging on join.
What is known about this copy:

- `PSP_GAME/SYSDIR/BOOT.BIN`: unencrypted PRX, entry `0x088088e4`, one loadable segment at `0x08804000`
  (the load base the game is recompiled for).
- `PSP_GAME/USRDIR/MODULE/JDB.PRX`: an unencrypted PRX the game loads (`Berkeley DB`, saves?);
  `LIBFONT.PRX`/`PSMF.PRX` are encrypted (`~SCE`) and will use the runtime's HLE instead.
- `.SPF` files start with `SFP\0` (sound, maps...); `.PAC`, `.DAT`, `.GMO`/`.GIM` formats still to
  document (PORT_PLAN.md, kept locally and never committed). `.PMF` movies and ATRAC audio are
  covered in [docs/formats.md](docs/formats.md) (cooked `movies/*.ivf` + `audio/*.ogg`).

## Requirements

- Your own `game.iso` (UCUS98700). Its SHA-1 is recorded in `.recomp.json` so you can check your copy:
  `sha1sum game.iso` should print `87b0e5fdbadaa0741adf5a5007d25d51639e6f9e`.
- CMake ≥ 3.25, Ninja, LLVM/Clang (and the Vulkan SDK, slangc). On Windows, also Visual Studio 2022
  (for the Windows SDK and CRT used by `clang-cl`). On Windows, `scripts\build.ps1` sets up that
  environment itself; otherwise run the CMake commands from an *x64 Native Tools / Developer* prompt.

## Building

Linux (Clang, Ninja, Vulkan SDK with `slangc`):

```
git submodule update --init --recursive
cmake --preset linux-x64-debug
cmake --build --preset linux-x64-debug
ctest --preset linux-x64-debug
```

Release: replace `linux-x64-debug` with `linux-x64-release` in the three commands above.
Single target: `cmake --build --preset linux-x64-debug --target jdarc`.

On Windows (Visual Studio 2022 with C++ x64 tools + LLVM):

```
scripts\build.ps1                     # windows-x64-debug: configure, build, run tests (-Preset, -NoTest)
```

The `jdarc` game target appears only after code is generated (see below); before that, the build still
produces `psprecomp`, `psprx`, `psptex` and the format/tests targets.

## Getting started

Extract your disc once (the game runs from the folder, never from the ISO):

```
7z x game.iso -odata/original PSP_GAME UMD_DATA.BIN
```

Inspect the executable and build its NID database (names for the imported system functions):

```
psprx info    data/original/PSP_GAME/SYSDIR/BOOT.BIN
psprx nids    "PSP SDK/pspsdk-MINPSPW/psp/sdk/lib" data/nids.tsv
psprx imports data/original/PSP_GAME/SYSDIR/BOOT.BIN data/nids.tsv
psprx disasm  data/original/PSP_GAME/SYSDIR/BOOT.BIN
```

Recompile it to C (output goes to the git-ignored `data/generated/` and is picked up by the build):

```
psprecomp data/original/PSP_GAME/SYSDIR/BOOT.BIN data/generated --overrides src/decomp --seeds seeds.txt
```

Cook the media the game loads besides the disc (ATRAC audio, PSMF movies become Ogg/IVF; needs the
FFmpeg command-line tool). Without it, music plays as silence and movies stay black. `jdcook` is not
written yet; until then `cccook` from the Crisis Core project is the reference implementation:

```
# jdcook data/original data/cooked   (planned; see docs/formats.md)
```

Run the game:

```
jdarc data/original --cooked data/cooked     # settings, saves: the working directory
scripts\run.ps1                              # the same with the repository's layout (run/ as cwd)
```

## Tools

`psprx` works on the game executable (`PSP_GAME/SYSDIR/BOOT.BIN`, an unencrypted PRX):

```
psprx info    BOOT.BIN                  # module info, segments, imports/exports, relocation stats
psprx nids    "PSP SDK/pspsdk-MINPSPW/psp/sdk/lib" data/nids.tsv   # NID names from local SDK stubs
psprx imports BOOT.BIN data/nids.tsv   # all imported system functions with names
psprx image   BOOT.BIN 0x08804000 build/boot.bin   # relocated memory image (this game's load base)
psprx disasm  BOOT.BIN                  # objdump-compatible listing (psprecore/scripts/check_allegrex.ps1 diffs it)
psprx symbols BOOT.BIN data/nids.tsv build/symbols.tsv 0x08804000 build/ghidra_symbols.txt
```

`psprecomp` translates BOOT.BIN into C (see [psprecore/docs/recompiler.md](psprecore/docs/recompiler.md)):

```
psprecomp data/original/PSP_GAME/SYSDIR/BOOT.BIN data/generated --overrides src/decomp --seeds seeds.txt
```

Game functions can be replaced by hand-written C++ in `src/decomp/` (`GAME_FUNC`); see
[docs/decompilation.md](docs/decompilation.md).

Textures are edited by hand in `assets/textures` (unpacked layout still to be defined for this game's
formats), and the build packs the edited ones into `data/cooked/textures`, which the game draws instead
of the originals (the "HD textures" setting switches them off and on). `psptex` does the packing and
matching; see the Crisis Core project's docs for the workflow until this game's unpack tool exists.

Recording and replaying play sessions (for bug reports and regression tests):

```
jdarc <game> --record session.txt          # play normally; input is written down
jdarc <game> --headless --replay session.txt --state-hash 1000 --screenshot-every 600:shots/f
```

A recording stores the guest clock it started with and snapshots the save folder (`session.txt.saves`), so a
replay reproduces the run exactly. `scripts\regress.ps1` replays every recording in `data\recordings`
(with `NAME.state` references, written by `-Update`) and reports any difference in the game's RAM state.
`scripts\pictures.ps1` compares a fixed set of pictures with a reference set; `scripts\smooth-check.ps1`
replays recordings with `--smooth-check` and lists the draws smooth motion drew apart. The game's state
also matches between the PC and Android: `--state-hash N` on both gives the same hashes for the same
recording.

Android: `scripts/build-android.ps1 -Install` builds and installs the APK (arm64, NDK r29). `-InstallData`
copies the game (`data/original`, as `Jeanne d'Arc/`) and `data/cooked` to
`Android/data/com.jdarcrecomp/files/` on the device. Logs go to logcat (tag `jdarc`) and `jdarc.log`
in the same folder.
