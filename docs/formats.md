# Formats (working notes)

What is known so far about this game's files (UCUS98700). Updated as formats get documented; analysis
scripts that produced these notes live in `tools/analysis/` (throwaway, game-specific) and
`psprecore/tools/analysis/` (generic: `strs.py`, `elf.py`, `sfo.py`, `nids_from_ppsspp.py`).

## Executables

- `PSP_GAME/SYSDIR/BOOT.BIN`: unencrypted ELF/PRX. Entry `0x088088e4`; one `LOAD` segment,
  file `0x54..0x1175D3` -> `vaddr 0x08804000`, `memsz 0x382F80`. Load base for recompilation: `0x08804000`.
- `PSP_GAME/USRDIR/MODULE/JDB.PRX`: unencrypted ELF (loads from `disc0:/PSP_GAME/USRDIR/MODULE/JDB.PRX`;
  strings mention `Jeanne_Browser`, Berkeley DB — probably saves/persistence).
- `PSP_GAME/USRDIR/MODULE/LIBFONT.PRX`, `PSMF.PRX`: encrypted (`~SCE`); the runtime's HLE covers
  fonts/video instead of loading these.

## Containers

- `.SPF` (`SFP\0` magic, ~2.5k files): sound (`SOUND/SKL*.SPF`, `SYS.SPF`), maps (`WMAP.SPF`,
  `MAP/MAP*.SPF`). Header has a count at `u32@8`; the entry table layout is not yet documented.
- `.PAC` (`LOGIC.PAC`, skill packs): starts with zeros; format still open.
- `.DAT` (maps, `BASEMAP.DAT`, `MAPINFO.DAT`): raw tables; format still open.

## Models / textures / movies / audio

- `.GMO` (models) / `.GIM` (textures): standard PSP formats, readable with existing GIM/GMO tools.
  `DATA/TITLE.GIM` is a 512x256 CLUT8 image (256-color palette, swizzled indices) holding the logo,
  menu texts and a `[ Debug ]` column in one texture. The game never draws it whole: it samples
  sub-rectangles through GE `BEZIER` patches (`TEXSCALE`/`TEXOFFSET` select logo, blinking
  `PRESS ANY BUTTON`, copyright), so a full-texture draw shows duplicate menus and debug text.
- Textures are edited by hand in `assets/textures` (unpacked layout still to be defined for this game's
  formats), and the build packs the edited ones into `data/cooked/textures`, which the game draws instead
  of the originals (the "HD textures" setting switches them off and on). `psptex` does the packing and
  matching; see the Crisis Core project's docs for the workflow until this game's unpack tool exists.
- `.PMF` (`MOVIE/DEMO*.PMF`, `CI.PMF`): standard PSMF movies (H.264 480x272); the runtime's sceMpeg HLE plays them from
  cooked media (`movies/<fnv1a64-of-2048-byte-header>.ivf` + `.ogg`). Missing tracks are reported as
  `sceMpeg: no cooked movie ... showing black` or `sceMpeg: no cooked audio ... silent`. `jdcook` demuxes
  the H.264 and private-stream ATRAC3plus itself (FFmpeg does not detect the latter in these PMF files),
  then converts them with SVT-AV1 and Vorbis:
  `build/linux-x64-debug/tools/jdcook/jdcook data/original data/cooked`.
  The player covers the game's direct-sceMpeg path including the YCbCr/Csc presentation used for
  cutscenes (`AvcInitYCbCr`/`AvcDecodeYCbCr`/`AvcDecodeStopYCbCr(mpeg, buffer, status*)`/`AvcCsc`,
  `QueryStreamSize`, `scePsmfSetPsmf/GetVideoInfo` — PPSSPP-faithful signatures; the Stop form takes no
  frame width, its status word is signaled on completion).
  Ringbuffer space is freed per drained stream; a registered stream the game stops pulling (e.g. the
  boot ident's audio) is ignored after ~2 s so it cannot pin the buffer and stall feeding. End of movie
  is detected by bytes fed vs the header's stream size; drained readers then get PPSSPP-style
  `dts=-1` + `NO_DATA`.
- Non-movie audio is still being documented; `jdcook` currently handles only PSMF movies. FFmpeg's
  ATRAC3plus decoder repeats input timestamps, so movie Ogg timestamps are regenerated with
  `asetpts=N/SR/TB`.

## Text

Dialog text renders through the runtime's substitute-font HLE
(`psprecore/runtime/src/hle_font.cpp`): the disc carries no system fonts
(`LIBFONT.PRX` is encrypted), so glyphs come from a host TrueType face
(`PSPRECORE_FONT`, else a system DejaVu/Arial/Roboto/Noto) rasterized with
stb_truetype. Verified with `data/recordings/fonts.txt` at vblank 3200
("Two pretty girls like you", name tag "jacques").

ABI notes (all verified against PPSSPP's PGF implementation and header):
- `GetCharInfo` reports PGFCharInfo with 26.6 advances (`advance<<6`);
  control chars (<0x20) return blank + zero advance (real PGF zeroes
  info for `charCode < firstGlyph`).
- `GetCharGlyphImage_Clip` rasterizes in place into the game's buffer
  (saturating add, clipped, 4bpp/8bpp only); the x fraction of `xPos64`
  blends, the y fraction is discarded. The game builds a glyph-cache
  texture at boot (cells at 20px stride) and draws dialog as textured
  quads, so no per-dialog Clip calls occur.
- The game never queries 0x20 (space, confirmed in both our log and
  PPSSPP's): word gaps derive from `GetFontInfo` maxSize, which must be
  real PGF values (ltn5.pgf, the serif-bold Latin font the game opens:
  1509x1210 in 26.6). ascender/descender stay at host-pixel scale — the
  full 26.6 header values (863/-196) fault the boot text converter
  (root cause open).
