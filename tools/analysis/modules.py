# Executable overview: BOOT.BIN and the USRDIR modules (unencrypted? entry? imports?).
#   python modules.py <disc folder>      -> one line per PRX/ELF on the disc
import struct
import sys
from pathlib import Path


def probe(path):
    d = path.read_bytes()
    if d[:4] == b'~SCE':
        return f'{path.name}: encrypted (~SCE), size {len(d)}'
    if d[:4] != b'\x7fELF':
        return f'{path.name}: not ELF (magic {d[:4]!r}), size {len(d)}'
    etype, machine = struct.unpack('<HH', d[16:20])
    entry, phoff = struct.unpack('<II', d[24:32])
    phnum = struct.unpack('<H', d[44:46])[0]
    segs = []
    for i in range(phnum):
        p = struct.unpack('<8I', d[phoff + i * 32:phoff + (i + 1) * 32])
        segs.append(f'vaddr {p[2]:#x} filesz {p[4]:#x} memsz {p[5]:#x} flags {p[6]:#x}')
    # Import libraries live in .rodata.sceModuleInfo; strings finds them cheaply.
    libs = sorted({s for s in ('sceLibFont', 'scePsmf', 'ModuleMgrForUser', 'sceUmdUser')
                   if s.encode() in d})
    return f'{path.name}: ELF entry {entry:#x}, {phnum} phdrs [{", ".join(segs)}] libs={libs or "?"}'


root = Path(sys.argv[1] if len(sys.argv) > 1 else sys.exit('usage: modules.py <disc folder>'))
for pat in ('PSP_GAME/SYSDIR/*.BIN', 'PSP_GAME/USRDIR/MODULE/*.PRX'):
    for path in sorted(root.glob(pat)):
        print(probe(path))
