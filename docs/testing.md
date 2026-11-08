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
  must not alter what is drawn). The runs are placeholders until real recordings exist.
- `scripts/smooth-check.sh` replays recordings with `--smooth-check` and lists the draws smooth
  motion drew apart. The runs are placeholders until real recordings exist.
- The game's state also matches between the PC and Android: `--state-hash N` on both gives the
  same hashes for the same recording.

Recordings and references stay local (they derive from the game and your saves).
