# Builds the LBN map for sce_lbn raw-sector reads: walks the ISO9660 tree of a PSP disc image and writes
# one line per file: "<lbn hex> <size hex> <disc-relative path>". The game reads FILEINFO.DAT (name -> LBN),
# then opens disc0:/sce_lbn<LBN>_size<SIZE>; the runtime serves those ranges from the extracted files using
# this map (data/original/lbn.tsv, pushed to the device with the game).
#
#   python tools/analysis/lbn.py game.iso data/original/lbn.tsv
import struct
import sys

src, out = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()


def record(off):
    ln = d[off]
    rec = d[off:off + ln]
    extent, size = struct.unpack('<II', rec[2:6] + rec[10:14])
    return ln, extent, size, rec[25], rec[33:33 + rec[32]]


root = d[0x8000 + 156:0x8000 + 190]
assert root[0] == 34, 'not a PSP PVD root record'
_, root_ext, root_sz, _, _ = record(0x8000 + 156)


def walk(ext, size, prefix):
    off, end, out = ext * 2048, ext * 2048 + size, []
    while off < end:
        if d[off] == 0:
            off += 1
            continue
        ln, fe, fs, flags, name = record(off)
        if name not in (b'\0', b'\x01'):
            path = (prefix + '/' if prefix else '') + name.decode()
            out += walk(fe, fs, path) if flags & 2 else [(fe, fs, path)]
        off += ln
    return out


files = walk(root_ext, root_sz, '')
dups = {p for _, _, p in files if sum(1 for _, _, q in files if q == p) > 1}
assert not dups, f'multi-extent files unsupported: {sorted(dups)[:5]}'
with open(out, 'w') as f:
    f.write('# lbn(hex) size(hex) disc-relative path (from tools/analysis/lbn.py; never commit an ISO)\n')
    for fe, fs, path in sorted(files):
        f.write(f'{fe:08x} {fs:08x} {path}\n')
print(len(files), 'files ->', out)
