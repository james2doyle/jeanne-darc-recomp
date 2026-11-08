# Decisions

Lightweight log of direction calls that would otherwise live only in chat history.
Newest first.

## 003 — Pin psprecore to our fork (2026-11-08)

**Context.** The runtime fixes this project needs live in psprecore PRs
#1–#4 against AdamFull/psprecore (terminate unwind, media HLE, BEZIER
tessellation, fill-screen rendering) — all open, none merged.

**Alternatives considered.**
- *Pin upstream, patch locally.* Rejected: a pinned commit must exist
  where the submodule URL points, or fresh clones fail to check out.
- *Wait for upstream to merge.* Rejected: blocks the public repo and
  every new checkout on someone else's review queue.

**Decision.** The submodule points at james2doyle/psprecore, whose master
is upstream plus our fixes. Upstream stays the target: the PRs remain open
and the pin moves back if they merge.

**Consequences.**
- `git submodule update --init --recursive` works on a fresh clone.
- Keep fork master a fast-forward superset of upstream until the PRs
  land; no unrelated work on it.

## 002 — Substitute host font for dialog text (2026-11-08)

**Context.** Dialog needs glyphs, but the disc has no usable font data:
`LIBFONT.PRX` is encrypted and the PSP system fonts live in flash, not on
the UMD. PPSSPP and MHForever solve this with real PGF parsing, Yakumo with
a substitute-font HLE.

**Alternatives considered.**
- *Ship a real PGF* (extract Sony's ltn5.pgf). Rejected: no license to
  redistribute console firmware files.
- *Port PPSSPP/MHForever font code.* Rejected: GPL-licensed, unusable under
  this project's MIT terms.
- *`GAME_FUNC` decomp patch for layout.* Rejected as the fix: the missing
  piece is glyph data, not layout — the game's cache/pen logic is correct
  once metrics are sane (word-touching traced to fake `maxSize`, not code).
- *Yakumo-style substitute HLE* (clean-room metrics + host-face raster).
  Chosen: no encumbered data or code, and PPSSPP's PGF source/docs serve as
  a behavioral reference without copying implementation.

**Decision.** Serve libfont from a host TrueType face (stb_truetype):
26.6 CharInfo advances, blank+zero for control chars, in-place Clip
rasterization, and real-ltn5 `maxSize` so word gaps lay out. Host face via
`PSPRECORE_FONT`, else system-font fallback; without one, text stays blank
but layout proceeds.

**Consequences.**
- Dialog renders without any Sony font file or GPL code in tree.
- `ascender/descender` stay at host-pixel scale: full 26.6 header values
  fault the boot text converter (open root cause; don't "fix" by reverting
  `maxSize` — that re-collapses spaces).
- The game never queries 0x20, so no HLE value can add spaces by itself;
  spacing lives or dies in `GetFontInfo` (verified against PPSSPP logs).

## 001 — Keep cooked movies (2026-11-08)

**Context.** Movies are PSMF (H.264 + ATRAC3plus in 2048-byte packs). Playback today
reads pre-cooked `movies/<fnv1a64>.ivf` (AV1/dav1d) + `.ogg` (Vorbis). Android shipped
without `cooked/` on-device, so videos rendered black — a packaging gap, not a
playback bug.

**Alternatives considered.**
- *Direct PMF playback* (Yakumo / sims2-psp-recomp pattern: own PSMF demuxer +
  FFmpeg libavcodec for H.264 and ATRAC, MIT-licensed, proven portable once already).
  Zero user friction, zero media duplication — but adds an FFmpeg third-party build
  for every target and weakens cross-device determinism (replays, state hashes,
  picture comparisons need frame-exact output; decoder output varies by version
  and HW vs SW path).
- *On-device re-encoding* (pick ROM → cook on phone). Rejected: SVT-AV1 is far too
  heavy for a one-time phone job and drags an encoder into the APK.

**Decision.** Keep cooked videos. They buy portability (one software path, no
platform codecs), determinism (content-keyed, byte-identical everywhere), and the
decode stack already ships and is verified (boot ident, DEMO0000 cutscene).

**Consequences.**
- The friction to kill is distribution, not format: one-command cook + push
  (`jdcook`, then install-data). A missing `cooked/` must stay a loud, diagnosable
  state (`sceMpeg: no cooked movie ...`), never a silent one.
- Revisit only if FFmpeg becomes a dependency for other reasons (e.g. direct
  ATRAC audio), which would reopen the decode-side cost.
