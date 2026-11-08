# Testing: recordings, replays, comparisons

Recording and replaying play sessions (for bug reports and regression tests):

```
jdarc <game> --record session.txt          # play normally; input is written down
jdarc <game> --headless --replay session.txt --state-hash 1000 --screenshot-every 600:shots/f
```

A recording stores the guest clock it started with and snapshots the save folder
(`session.txt.saves`), so a replay reproduces the run exactly.

- `scripts/regress.sh` replays every recording in `data/recordings` (with `NAME.state`
  references, written by `--update`) and reports any difference in the game's RAM state.
- `scripts/pictures.sh` compares a fixed set of pictures with a reference set (for changes that
  must not alter what is drawn). The runs are placeholders: point them at your own recordings.
- `scripts/smooth-check.sh` replays recordings with `--smooth-check` and lists the draws smooth
  motion drew apart. The runs are placeholders: point them at your own recordings.
- The game's state also matches between the PC and Android: `--state-hash N` on both gives the
  same hashes for the same recording.

Android's `--smoke` checks that the game boots for 120 guest vblanks; it does not verify rendered
pixels. For display changes, also inspect a movie centered at its original 480:272 aspect ratio,
the `TITLE.GIM` screen, and a 3D scene with complete character silhouettes and HUD/dialog overlays.
Check both the original aspect ratio and Fill the screen at a wider aspect ratio, using desktop as a
convenient control before an on-device check. Replay completion, state hashes, and image comparisons
support but do not replace manual visual QA of these cases.

Recordings and references stay local (they derive from the game and your saves).
