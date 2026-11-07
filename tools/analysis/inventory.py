# Disc inventory: file counts and sizes by extension and by top-level DATA folder.
#   python inventory.py <game.iso>       (needs 7z on PATH)
import re
import subprocess
import sys
from collections import Counter

out = subprocess.run(['7z', 'l', sys.argv[1]], capture_output=True, text=True, check=True).stdout
exts: Counter = Counter()
dirs: Counter = Counter()
n = 0
for line in out.splitlines():
    m = re.match(r'\d{4}-\d{2}-\d{2} .*? (\d+) +\d+ +(\S+)', line)
    if not m:
        continue
    size, name = int(m.group(1)), m.group(2)
    n += 1
    ext = name.rsplit('.', 1)[-1].upper() if '.' in name.rsplit('/', 1)[-1] else '(none)'
    exts[ext] += size
    top = name.split('/')[3] if name.count('/') >= 3 and name.split('/')[2] == 'DATA' else '(root)'
    dirs[top] += size

print(f'{n} files')
for ext, size in exts.most_common():
    print(f'  .{ext:8s} {size / 2**20:9.1f} MiB')
print()
for d, size in dirs.most_common(20):
    print(f'  {d:10s} {size / 2**20:9.1f} MiB')
