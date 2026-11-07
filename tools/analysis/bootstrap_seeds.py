#!/usr/bin/env python3
# Bootstraps seeds.txt: runs the game headless, collects "no function at 0xXXXXXXXX" addresses
# (missed indirect calls/callbacks), appends the real ones, regenerates and rebuilds. Repeats until the run
# gets past all missing functions or --rounds runs out. Usage from the repo root:
#   python tools/analysis/bootstrap_seeds.py [--rounds N] [--vblanks N]
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SEEDS = ROOT / 'seeds.txt'
GEN = ROOT / 'data' / 'generated'
PSPRECOMP = ROOT / 'build' / 'linux-x64-debug' / 'psprecore' / 'tools' / 'psprecomp' / 'psprecomp'
JDARC = ROOT / 'build' / 'linux-x64-debug' / 'jdarc'
GAME = ROOT / 'data' / 'original'


def run(*cmd, timeout=300):
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    return (p.stdout or '') + (p.stderr or '')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rounds', type=int, default=10)
    ap.add_argument('--vblanks', type=int, default=1800)
    args = ap.parse_args()

    for i in range(args.rounds):
        print(f'--- round {i + 1}: run', flush=True)
        out = run(str(JDARC), str(GAME), '--headless', '--no-audio', '--vblanks', str(args.vblanks),
                  timeout=600)
        missing = sorted({int(m, 16) for m in re.findall(r'no function at 0x([0-9A-Fa-f]{8})', out)})
        known = set()
        if SEEDS.exists():
            for tok in SEEDS.read_text().split():
                if tok.startswith('#'):
                    continue
                try:
                    known.add(int(tok, 16))
                except ValueError:
                    pass
        new = [a for a in missing if a not in known]
        tail = '\n'.join(out.strip().splitlines()[-8:])
        print(tail)
        if not new:
            print('no new missing functions')
            # stop when the run also ends cleanly (no abort/trap); otherwise keep looking at the tail
            if 'recomp_trap' not in out and 'dumped core' not in out and 'Aborted' not in out:
                print('BOOTSTRAP COMPLETE')
                return 0
            print('(run still fails; needs manual analysis)')
            return 1
        with SEEDS.open('a') as f:
            for a in new:
                f.write(f'{a:08X}  # round {i + 1}\n')
        print(f'{len(new)} new seeds: ' + ' '.join(f'{a:08X}' for a in new), flush=True)
        print('--- regenerate', flush=True)
        print(run(str(PSPRECOMP), str(ROOT / 'data' / 'original' / 'PSP_GAME' / 'SYSDIR' / 'BOOT.BIN'),
                  str(GEN), '--overrides', str(ROOT / 'src' / 'decomp'), '--seeds', str(SEEDS),
                  timeout=600).strip().splitlines()[-1:])
        print('--- rebuild', flush=True)
        r = subprocess.run(['cmake', '--build', '--preset', 'linux-x64-debug', '--target', 'jdarc'],
                           cwd=ROOT, capture_output=True, text=True, timeout=1800)
        if r.returncode != 0:
            print(r.stdout[-2000:] + r.stderr[-2000:])
            return 1
    print('rounds exhausted')
    return 1


sys.exit(main())
