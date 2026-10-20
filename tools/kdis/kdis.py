"""Linear Kismet bytecode listing for cooked UE4.27 Blueprint functions (research only; jump targets and line
numbers are in-memory offsets). Usage: python -I kdis.py file.uasset [function-substring ...] (reads the .uexp too)"""
import struct, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from uinfo import parse

def header_size(path):
    b = open(path, 'rb').read(64 * 1024)
    o = 4
    legacy = struct.unpack_from('<i', b, o)[0]; o += 4
    if legacy != -4: o += 4
    o += 8
    n = struct.unpack_from('<i', b, o)[0]; o += 4 + n * 20
    return struct.unpack_from('<i', b, o)[0]

class D:
    def __init__(s, code, names, imps, exps):
        s.c, s.p, s.names, s.imps, s.exps = code, 0, names, imps, exps
        s.adj = 0
    def u8(s): v = s.c[s.p]; s.p += 1; return v
    def u16(s): v = struct.unpack_from('<H', s.c, s.p)[0]; s.p += 2; return v
    def i32(s): v = struct.unpack_from('<i', s.c, s.p)[0]; s.p += 4; return v
    def u32(s): v = struct.unpack_from('<I', s.c, s.p)[0]; s.p += 4; return v
    def f32(s): v = struct.unpack_from('<f', s.c, s.p)[0]; s.p += 4; return round(v, 4)
    def name(s):
        i, n = struct.unpack_from('<ii', s.c, s.p); s.p += 8; s.adj += 4
        return s.names[i] + (f'_{n - 1}' if n else '')
    def obj(s):
        i = s.i32(); s.adj += 4
        if i == 0: return 'null'
        if i < 0: return s.imps[-i - 1][3]
        return s.exps[i - 1][3]
    def prop(s):
        p0, a0 = s.p, s.adj
        n = s.i32(); path = [s.name() for _ in range(n)]; s.i32()
        s.adj = a0 + 8 - (s.p - p0)
        return '.'.join(path) or '?'
    def astr(s):
        e = s.c.index(b'\0', s.p); v = s.c[s.p:e].decode('latin-1'); s.p = e + 1; return repr(v)
    def wstr(s):
        e = s.p
        while s.c[e:e + 2] != b'\0\0': e += 2
        v = s.c[s.p:e].decode('utf-16-le'); s.p = e + 2; return repr(v)
    def params(s):
        out = []
        while s.c[s.p] != 0x16: out.append(s.expr())
        s.p += 1
        return ', '.join(out)
    def until(s, end):
        out = []
        while s.c[s.p] != end: out.append(s.expr())
        s.p += 1
        return out
    def expr(s):
        t = s.u8()
        if t == 0x00: return s.prop()
        if t == 0x01: return 'self.' + s.prop()
        if t == 0x02: return 'default.' + s.prop()
        if t == 0x04: return 'return ' + s.expr()
        if t == 0x06: return f'jump {s.u32()}'
        if t == 0x07: o = s.u32(); return f'if not ({s.expr()}) jump {o}'
        if t == 0x09: s.u16(); s.u8(); return 'assert ' + s.expr()
        if t == 0x0B: return 'nothing'
        if t == 0x0F: s.prop(); a = s.expr(); return f'{a} = {s.expr()}'
        if t in (0x12, 0x19, 0x1A):
            a = s.expr(); s.u32(); s.prop(); return f'{a}{"?" if t == 0x1A else ""}.{s.expr()}'
        if t == 0x13: c = s.obj(); return f'MetaCast<{c}>({s.expr()})'
        if t in (0x14, 0x43, 0x44, 0x5F, 0x60): a = s.expr(); return f'{a} = {s.expr()}'
        if t == 0x15: return 'endparm'
        if t == 0x17: return 'self'
        if t == 0x18: s.u32(); return 'skip ' + s.expr()
        if t in (0x1B, 0x45): n = s.name(); return f'{n}({s.params()})'
        if t in (0x1C, 0x46, 0x68, 0x63): f = s.obj(); return f'{f}({s.params()})'
        if t == 0x1D: return str(s.i32())
        if t == 0x1E: return str(s.f32())
        if t == 0x1F: return s.astr()
        if t == 0x20: return 'obj:' + s.obj()
        if t == 0x21: return 'name:' + s.name()
        if t in (0x22, 0x23): return f'({s.f32()},{s.f32()},{s.f32()})'
        if t == 0x24: return str(s.u8())
        if t == 0x25: return '0'
        if t == 0x26: return '1'
        if t == 0x27: return 'true'
        if t == 0x28: return 'false'
        if t == 0x29:
            k = s.u8()
            if k == 0: return 'text:""'
            if k == 1: a = s.expr(); s.expr(); s.expr(); return 'text:' + a
            if k in (2, 3): return 'text:' + s.expr()
            if k == 4: s.obj(); s.expr(); return 'text:' + s.expr()
            return f'text?{k}'
        if t == 0x2A: return 'None'
        if t == 0x2B: return 'transform(' + ','.join(str(s.f32()) for _ in range(10)) + ')'
        if t == 0x2C: return str(s.u8())
        if t == 0x2D: return 'NoInterface'
        if t in (0x2E, 0x52, 0x54, 0x55): c = s.obj(); return f'Cast<{c}>({s.expr()})'
        if t == 0x2F: c = s.obj(); s.i32(); return f'{c}{{' + ', '.join(s.until(0x30)) + '}'
        if t == 0x31: a = s.expr(); return f'{a} = [' + ', '.join(s.until(0x32)) + ']'
        if t == 0x33: return 'prop:' + s.prop()
        if t == 0x34: return s.wstr()
        if t in (0x35, 0x36): v = struct.unpack_from('<q', s.c, s.p)[0]; s.p += 8; return str(v)
        if t == 0x38: s.u8(); return 'cast(' + s.expr() + ')'
        if t in (0x39, 0x3B): a = s.expr(); s.i32(); return f'{a} = {{' + ', '.join(s.until(t + 1)) + '}'
        if t == 0x3D: s.prop(); s.i32(); return '{' + ', '.join(s.until(0x3E)) + '}'
        if t == 0x3F: s.prop(); s.prop(); s.i32(); return '{' + ', '.join(s.until(0x40)) + '}'
        if t == 0x42: m = s.prop(); return f'{s.expr()}.{m}'
        if t == 0x48: return 'out.' + s.prop()
        if t == 0x4B: return 'delegate:' + s.name()
        if t == 0x4C: return f'push {s.u32()}'
        if t == 0x4D: return 'pop'
        if t == 0x4E: return 'computedjump ' + s.expr()
        if t == 0x4F: return f'popifnot ({s.expr()})'
        if t in (0x50, 0x5A, 0x5E): return 'trace'
        if t == 0x51: return 'iface(' + s.expr() + ')'
        if t == 0x53: return 'end'
        if t == 0x5B: return f'skipconst {s.u32()}'
        if t in (0x5C, 0x62): a = s.expr(); return f'{a} {"+=" if t == 0x5C else "-="} {s.expr()}'
        if t == 0x5D: return 'clear ' + s.expr()
        if t == 0x61: n = s.name(); a = s.expr(); return f'bind {n} {a} {s.expr()}'
        if t == 0x64: p = s.prop(); return f'persist.{p} = {s.expr()}'
        if t == 0x65: s.prop(); s.i32(); return '[' + ', '.join(s.until(0x66)) + ']'
        if t == 0x67: return 'soft:' + s.expr()
        if t == 0x69:
            n = s.u16(); s.u32(); idx = s.expr(); cases = []
            for _ in range(n):
                v = s.expr(); s.u32(); cases.append(f'{v}:{s.expr()}')
            return f'switch({idx}){{' + ', '.join(cases) + f', default:{s.expr()}}}'
        if t == 0x6B: a = s.expr(); return f'{a}[{s.expr()}]'
        if t == 0x6C: return 'sparse.' + s.prop()
        if t == 0x6D: return 'fieldpath:' + s.expr()
        raise ValueError(f'opcode 0x{t:02x} at {s.p - 1}')

def export_table_offset(b):
    o = 4
    legacy = struct.unpack_from('<i', b, o)[0]; o += 4
    if legacy != -4: o += 4
    o += 8
    n = struct.unpack_from('<i', b, o)[0]; o += 4 + n * 20 + 4
    fl = struct.unpack_from('<i', b, o)[0]; o += 4 + (fl if fl > 0 else -fl * 2)
    return struct.unpack_from('<i', b, o + 24)[0]

def code_of(b, ux, hs, eoff, k):
    size, off = struct.unpack_from('<qq', b, eoff + k * 104 + 28)
    blob = ux[off - hs: off - hs + size]
    # UFunction tail: ...ScriptBytecodeSize, ScriptStorageSize, bytecode (ends with EX_EndOfScript), 12 bytes of flags
    for q in range(len(blob) - 8, -1, -1):
        bc, st = struct.unpack_from('<ii', blob, q)
        end = q + 8 + st
        if 0 < st and 0 < bc < 4 * st and st < 4 * bc and len(blob) - end == 12 and blob[end - 1] == 0x53:
            return blob[q + 8: end]
    return b''

def listing(path, subs=()):
    """Yield text lines: '== Function (n bytes)' then '  <memory offset>: <expression>'."""
    names, imps, exps = parse(path)
    b = open(path, 'rb').read()
    hs, eoff = header_size(path), export_table_offset(b)
    ux = open(path[:-6] + 'uexp', 'rb').read()
    for k, (ci, si, oi, on, sz) in enumerate(exps):
        if ci >= 0 or imps[-ci - 1][3] != 'Function': continue
        if subs and not any(x.lower() in on.lower() for x in subs): continue
        code = code_of(b, ux, hs, eoff, k)
        yield f'== {on} ({len(code)} bytes)'
        d = D(code, names, imps, exps)
        while d.p < len(code):
            at = d.p + d.adj
            try:
                line = d.expr()
            except Exception as ex:
                yield f'  !! {ex}'; break
            if line not in ('trace', 'end'): yield f'  {at:5}: {line}'

if __name__ == '__main__':
    for line in listing(sys.argv[1], sys.argv[2:]): print(line)
