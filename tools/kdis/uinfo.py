"""Print names, imports, exports of a cooked UE4.27 .uasset. Usage: uinfo.py file.uasset [names|imports|exports|all]"""
import struct, sys

def fstr(b, o):
    n = struct.unpack_from('<i', b, o)[0]; o += 4
    if n == 0: return '', o
    if n < 0: return b[o:o - n * 2].decode('utf-16-le').rstrip('\0'), o - n * 2
    return b[o:o + n].decode('utf-8', 'replace').rstrip('\0'), o + n

def parse(path):
    b = open(path, 'rb').read()
    o = 4
    legacy = struct.unpack_from('<i', b, o)[0]; o += 4
    if legacy != -4: o += 4
    ue4, lic = struct.unpack_from('<ii', b, o); o += 8
    if legacy <= -2:
        n = struct.unpack_from('<i', b, o)[0]; o += 4 + n * 20
    o += 4  # TotalHeaderSize
    _, o = fstr(b, o)
    flags, ncount, noff = struct.unpack_from('<Iii', b, o); o += 12
    o += 8  # gatherable text
    ecount, eoff, icount, ioff = struct.unpack_from('<iiii', b, o)
    names = []
    p = noff
    for _ in range(ncount):
        s, p = fstr(b, p); p += 4; names.append(s)
    def fn(p):
        i, num = struct.unpack_from('<ii', b, p)
        return names[i] + (f'_{num - 1}' if num else '')
    imps = []
    for k in range(icount):
        p = ioff + k * 28
        imps.append((fn(p), fn(p + 8), struct.unpack_from('<i', b, p + 16)[0], fn(p + 20)))
    exps = []
    for k in range(ecount):
        p = eoff + k * 104
        ci, si, ti, oi = struct.unpack_from('<iiii', b, p)
        exps.append((ci, si, oi, fn(p + 16), struct.unpack_from('<q', b, p + 28)[0]))
    return names, imps, exps

def ref(i, imps, exps):
    if i < 0: return imps[-i - 1][3]
    if i > 0: return exps[i - 1][3]
    return '-'

def full(i, imps, exps):
    out = []
    while i:
        out.append(ref(i, imps, exps))
        i = imps[-i - 1][2] if i < 0 else exps[i - 1][2]
    return '.'.join(reversed(out))

if __name__ == '__main__':
    names, imps, exps = parse(sys.argv[1])
    what = sys.argv[2] if len(sys.argv) > 2 else 'all'
    if what in ('names', 'all'):
        print('# names'); [print(n) for n in names]
    if what in ('imports', 'all'):
        print('# imports')
        for k, (cp, cn, oi, on) in enumerate(imps):
            print(f'{cn:24} {full(-k - 1, imps, exps)}')
    if what in ('exports', 'all'):
        print('# exports')
        for ci, si, oi, on, sz in exps:
            print(f'{ref(ci, imps, exps):32} {full(exps.index((ci, si, oi, on, sz)) + 1, imps, exps)} super={ref(si, imps, exps)} size={sz}')
