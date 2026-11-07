# SPF container survey: header fields and entry table candidates.
#   python spf.py <file.SPF>            -> header fields, entropy, embedded magics
#   python spf.py <file.SPF> <other>    -> compare headers across SPF kinds
import struct
import sys


def header(d):
    if d[:4] != b'SFP\x00':
        sys.exit('not an SPF file (magic %r)' % d[:4])
    # Observed on WMAP.SPF, SOUND/SYS.SPF, SOUND/SKL100.SPF, all size-consistent so far:
    #   u32@8: entry count (5 on all three); u32@0x10: table byte size; u32@0x20: data start.
    count = struct.unpack('<I', d[8:12])[0]
    table_size = struct.unpack('<I', d[0x10:0x14])[0]
    data_start = struct.unpack('<I', d[0x20:0x24])[0]
    return count, table_size, data_start


def survey(path):
    d = open(path, 'rb').read()
    count, table_size, data_start = header(d)
    print(f'{path}: size {len(d):#x}, count {count}, table {table_size:#x} bytes, data @{data_start:#x}')
    table = d[0x24:0x24 + table_size]
    print('  table head:', table[:64].hex(' '))
    # Entry candidates: pairs of (offset, size) pointing inside the file.
    for width, fmt in ((8, '<II'),):
        hits = 0
        for o in range(0, len(table) - width + 1, 4):
            off, size = struct.unpack(fmt, table[o:o + width])
            if 0 < off < len(d) and 0 < size <= len(d) - off and off >= data_start:
                hits += 1
                if hits <= count + 2:
                    print(f'  candidate entry @{o:#x}: off {off:#x} size {size:#x} head {d[off:off+16].hex(" ")}')
        print(f'  {hits} (off,size) pairs point inside the file (count says {count})')
    body = d[data_start:]
    magics = {}
    for o in range(0, len(body) - 4):
        if body[o:o + 4] in (b'RIFF', b'GIM\x00', b'\x00GMO', b'GMO\x00', b'PSMF'):
            magics[body[o:o + 4]] = magics.get(body[o:o + 4], 0) + 1
    print('  embedded magics:', {k.decode('ascii', 'replace'): v for k, v in magics.items()} or '(none found)')


for path in sys.argv[1:] or sys.exit('usage: spf.py <file.SPF> [...]'):
    survey(path)
