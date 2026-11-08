# Decisions

Lightweight log of direction calls that would otherwise live only in chat history.
Newest first.

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
