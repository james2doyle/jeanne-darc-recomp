# JDARCRECOMP

A native PC (Windows/Linux) and Android port of the PSP game *Jeanne d'Arc*,
built by static recompilation and progressive decompilation.

**This repository contains no game code or assets.** You need your own copy of the game
(UCUS-98700, USA). Everything derived from it is generated locally and never committed.

## Layout

```
src/            the game's own code (main, mods) and hand-written replacements (src/decomp)
libs/           the game's file formats
tools/          game-specific tools (jdcook media baker, analysis scripts)
tests/ docs/ scripts/ android/
psprecore/      the recompiler and runtime (submodule)
data/           your game copy and everything derived from it (git-ignored):
  original/       the disc folder (PSP_GAME/...) extracted from your own game.iso
  generated/      C code recompiled from BOOT.BIN (psprecomp)
  cooked/         what the game loads besides the disc: audio, movies, textures
  recordings/     play sessions for replays and regression tests
assets/         game assets unpacked for editing (git-ignored)
run/            the working directory for playing: settings, saves, mods (git-ignored)
build/          CMake output
```

The recompiler and runtime are [psprecore](https://github.com/AdamFull/psprecore), a git submodule.
Jeanne d'Arc keeps loose files on the disc (per-stage `DATA/AS*/` folders), so there is no
archive tool: mods overlay whole files, and later mod folders win.

## Status

Boots through the opening movie to the title screen, and NEW GAME reaches the `DEMO0000`
cutscene. Media and code details live in [docs/formats.md](docs/formats.md) and
[docs/decompilation.md](docs/decompilation.md).

## Requirements

- Your own `game.iso` (UCUS98700). Its SHA-1 is recorded in `.recomp.json` so you can check your copy:
  `sha1sum game.iso` should print `87b0e5fdbadaa0741adf5a5007d25d51639e6f9e`.
- CMake ≥ 3.25, Ninja, LLVM/Clang (and the Vulkan SDK, slangc). On Windows, also Visual Studio 2022
  (for the Windows SDK and CRT used by `clang-cl`).

## Building

First checkout: `git submodule update --init --recursive`. Then use the wrapper scripts:

```
scripts/build.sh                              # Linux: linux-x64-debug, build + tests
scripts/build.sh --preset linux-x64-release --no-test
scripts/build.sh --preset linux-x64-debug --target jdarc   # single target
scripts\build.ps1 -Preset windows-x64-release -NoTest   # Windows (sets up the VS environment itself)
```

The `jdarc` game target appears only after code is generated (see below); before that, the build still
produces `jdcook`, `psprecomp`, `psprx`, `psptex` and the format/tests targets.

## Getting started

Extract your disc once (the game runs from the folder, never from the ISO):

```
7z x game.iso -odata/original PSP_GAME UMD_DATA.BIN
```

Recompile it to C (output goes to the git-ignored `data/generated/` and is picked up by the build;
see [docs/decompilation.md](docs/decompilation.md)):

```
psprecomp data/original/PSP_GAME/SYSDIR/BOOT.BIN data/generated --overrides src/decomp --seeds seeds.txt
```

Cook the movie media the game loads besides the disc (PSMF video becomes AV1/IVF and its ATRAC3plus audio
becomes Ogg). This needs FFmpeg with the SVT-AV1 and Vorbis encoders. Missing audio is silent and missing
video is black. Existing outputs are kept, so an interrupted cooking run can be resumed:

```
cmake --build --preset linux-x64-debug --target jdcook
build/linux-x64-debug/tools/jdcook/jdcook data/original data/cooked
```

Run the game (settings, saves: the working directory):

```
scripts/run.sh                              # the repository's layout (run/ as cwd)
scripts/run.sh -- --replay ../data/recordings/boot.txt --unthrottled
```

Or invoke the binary directly: `jdarc data/original --cooked data/cooked`.

Android: `scripts/build-android.sh --install` builds and installs the APK (arm64, NDK r29);
`--install-data` copies the game and `data/cooked` to the device. Logs go to logcat (tag `jdarc`).
