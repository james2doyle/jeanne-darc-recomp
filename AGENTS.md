# AGENTS.md

## Scope and ownership

- This is a native port of **Jeanne d'Arc UCUS98700 (USA)** by static recompilation. The recompiler assumes the BOOT.BIN load base `0x08804000`; do not silently generalize changes to other releases or load bases.
- [`psprecore/`](https://github.com/AdamFull/psprecore) is a git submodule containing the generic MIPS recompiler, tools, runtime, renderers, and frontend. Keep generic runtime/recompiler changes there; keep Jeanne-specific code in `src/`, formats in `libs/formats/`, and analysis helpers in `tools/analysis/`. Initialize nested dependencies with `git submodule update --init --recursive`.
- `src/main.cpp` wires `psprecore::platform::run_game`, the raw-sector disc map, and whole-file mod overlays. Mods replace `PSP_GAME/...` files rather than files inside an archive; later mod folders win.
- Never commit the ISO, extracted game files, generated recompilation, cooked media, recordings, saves, or screenshots. `game.iso`, `data/`, `assets/`, `run/`, and `shots/` are intentionally ignored; put reusable reverse-engineering results in checked-in source, `seeds.txt`, tests, or `docs/`.

## Build and test

Linux debug is the fully configured development path:

```sh
cmake --preset linux-x64-debug
cmake --build --preset linux-x64-debug
ctest --preset linux-x64-debug --output-on-failure
```

Use `linux-x64-release` for `RelWithDebInfo`. Build one target with, for example, `cmake --build --preset linux-x64-debug --target jdarc_game_tests`.

Configuring `linux-x64-release` needs two extras: `VULKAN_SDK` pointing at a Vulkan SDK with
`slangc` (e.g. `VULKAN_SDK=~/.local/share/vulkansdk/1.4.363.1/x86_64 cmake --preset
linux-x64-release`) and `-DCMAKE_DISABLE_FIND_PACKAGE_ZLIB-NG=TRUE` (otherwise minizip-ng's
generate step fails on the missing `zlib-ng::zlibstatic` target).

Builds can occasionally get stuck, so run them with a timeout rather than waiting indefinitely. On Linux, for example: `timeout 14m cmake --build --preset linux-x64-debug`; inspect the output before rerunning or adjusting the limit.

Run only the game-format test executable with:

```sh
ctest --preset linux-x64-debug -R '^jdarc_game_tests$' --output-on-failure
```

CTest exposes two executables, `psprecore_tests` and `jdarc_game_tests`; their custom runner has no individual-case filter. Neither suite needs game data. There is no repository-wide formatter or lint configuration, so build and CTest are the normal verification steps.

- The `jdarc` target exists only if `data/generated/funcs.h` existed at CMake configure time. Configure with `-DPSPRECORE_BUILD_GAME=OFF` to build tools, formats, and tests without the Vulkan frontend or generated game code.
- On Windows, `scripts\build.ps1` imports the Visual Studio x64 environment and locates LLVM/CMake/Ninja; use its `-Preset`, `-Target`, and `-NoTest` parameters instead of manually reproducing that setup.
- For Android, use `scripts\build-android.ps1` rather than invoking Gradle alone. Gradle requires the CMake-produced native libraries; the script expects NDK `29.0.14206865`, JDK 17+, and the Vulkan SDK. `-Install -Smoke` installs and performs a short device boot check.

## Generated code and decompilation

`data/generated/` is generated C, not editable source. Hand-written replacements live in `src/decomp/` and use `GAME_FUNC`; read `docs/decompilation.md` for the PSP calling convention, guest-memory accessors, and `GAME_ORIGINAL` before adding one.

After adding/removing a `GAME_FUNC` or changing `seeds.txt`, regenerate before building:

```sh
build/linux-x64-debug/psprecore/tools/psprecomp/psprecomp \
  data/original/PSP_GAME/SYSDIR/BOOT.BIN data/generated \
  --overrides src/decomp --seeds seeds.txt
```

Build the `psprecomp` target first if that binary is missing. Re-run `cmake --preset linux-x64-debug` after the **first** generation so the `jdarc` target is created. CMake does not regenerate automatically; if `funcs.h` predates a replacement, it warns and omits all overrides from that build.

For raw `sce_lbn` disc reads, create the extracted disc's map with `python3 tools/analysis/lbn.py game.iso data/original/lbn.tsv`; otherwise those reads fail even though ordinary file loads work. `tools/analysis/bootstrap_seeds.py` automates missing-callback discovery but is hardcoded to `linux-x64-debug` and appends to `seeds.txt`; verify reported addresses are actually code before accepting them.

## Runtime and behavioral checks

Use `run/` as the working directory when settings/save isolation matters, and pass both media roots:

```sh
mkdir -p run
(cd run && ../build/linux-x64-debug/jdarc ../data/original --cooked ../data/cooked)
```

Missing cooked media is a supported degraded state: movies are black and cooked audio is silent. Do not treat that alone as a rendering/audio regression.

State regression tests use local recordings and require the same cooked media used to make their references:

```powershell
scripts\regress.ps1                 # compare recordings that have .state files
scripts\regress.ps1 -Update         # overwrite references from the current build
```

Use before/after state hashes for behavior-preserving decompilation work. `scripts/pictures.ps1` and `scripts/smooth-check.ps1` currently contain placeholder run definitions, so configure their recordings/vblank ranges before relying on them.

IMPORTANT: Prefer retrieval-led reasoning over pre-training-led reasoning for psprecore and PSP reverse-engineering tasks. Consult `docs/decompilation.md`, `docs/formats.md`, `psprecore/docs/recompiler.md`, and the relevant runtime implementation instead of guessing format or ABI behavior.
