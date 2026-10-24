# UE4SS crash dump (ue4ss/crash_*.dmp) -> exception address and the UE4SS/game frames found on the crashing stack, symbolized with dbghelp.
# python -I tools/dmpstack.py <dump> <folder with UE4SS.dll and UE4SS.pdb>  (heuristic: stack scan, not a real unwind; read it top-down)
import ctypes as C, ctypes.wintypes as W, struct, sys, mmap
dmp, pdbdir = sys.argv[1], sys.argv[2]
data = open(dmp, 'rb').read()
sig, ver, nstreams, rva_dir = struct.unpack_from('<IIII', data, 0)
streams = {}
for i in range(nstreams):
    t, size, rva = struct.unpack_from('<III', data, rva_dir + 12 * i)
    streams[t] = (size, rva)
def u16s(rva):
    n = struct.unpack_from('<I', data, rva)[0]; return data[rva+4:rva+4+n].decode('utf-16-le')
# modules
size, rva = streams[4]; n = struct.unpack_from('<I', data, rva)[0]; mods = []
for i in range(n):
    o = rva + 4 + 108 * i
    base, sz = struct.unpack_from('<QI', data, o); name_rva = struct.unpack_from('<I', data, o + 20)[0]
    mods.append((base, sz, u16s(name_rva)))
# exception
size, rva = streams[6]; tid = struct.unpack_from('<I', data, rva)[0]
code, flags, rec, addr = struct.unpack_from('<IIQQ', data, rva + 8)
ctx_size, ctx_rva = struct.unpack_from('<II', data, rva + 8 + 152)
rsp, = struct.unpack_from('<Q', data, ctx_rva + 0x98); rip, = struct.unpack_from('<Q', data, ctx_rva + 0xF8)
# memory64
regions = []
if 9 in streams:
    size, rva = streams[9]; nr, base_rva = struct.unpack_from('<QQ', data, rva); off = base_rva
    for i in range(nr):
        start, sz = struct.unpack_from('<QQ', data, rva + 16 + 16 * i); regions.append((start, sz, off)); off += sz
if 5 in streams:
    size, rva = streams[5]; nr = struct.unpack_from('<I', data, rva)[0]
    for i in range(nr):
        start, sz, o = struct.unpack_from('<QII', data, rva + 4 + 16 * i); regions.append((start, sz, o))
def read(a, n):
    for s, sz, o in regions:
        if s <= a and a + n <= s + sz: return data[o + a - s:o + a - s + n]
dbg = C.WinDLL('dbghelp'); k32 = C.WinDLL('kernel32'); h = W.HANDLE(0x1234)
dbg.SymLoadModuleExW.restype = C.c_ulonglong
dbg.SymLoadModuleExW.argtypes = [W.HANDLE, W.HANDLE, C.c_wchar_p, C.c_wchar_p, C.c_ulonglong, W.DWORD, C.c_void_p, W.DWORD]
dbg.SymSetOptions(0x2 | 0x10 | 0x40); dbg.SymInitializeW(h, C.c_wchar_p(pdbdir), False)
for b, sz, name in mods:
    r = dbg.SymLoadModuleExW(h, None, name, None, b, sz, None, 0)

class SYM(C.Structure):
    _fields_ = [('SizeOfStruct', W.ULONG), ('TypeIndex', W.ULONG), ('Reserved', C.c_ulonglong * 2), ('Index', W.ULONG), ('Size', W.ULONG),
                ('ModBase', C.c_ulonglong), ('Flags', W.ULONG), ('Value', C.c_ulonglong), ('Address', C.c_ulonglong), ('Register', W.ULONG),
                ('Scope', W.ULONG), ('Tag', W.ULONG), ('NameLen', W.ULONG), ('MaxNameLen', W.ULONG), ('Name', C.c_char * 512)]
dbg.SymFromAddr.argtypes = [W.HANDLE, C.c_ulonglong, C.POINTER(C.c_ulonglong), C.c_void_p]
def sym(a):
    m = next((n.replace(chr(92),'/').split('/')[-1] for b, sz, n in mods if b <= a < b + sz), None)
    if not m: return None
    s = SYM(); s.SizeOfStruct = 88; s.MaxNameLen = 511; d = C.c_ulonglong()
    if dbg.SymFromAddr(h, a, C.byref(d), C.byref(s)): return '%s!%s+0x%x' % (m, s.Name.decode(), d.value)
    return '%s+0x%x' % (m, a - next(b for b, sz, n in mods if b <= a < b + sz))
print('exception 0x%x at %s' % (code, sym(addr)))
print('RIP', sym(rip))
mem = read(rsp, 0x3000) or read(rsp, 0x800) or b''
seen = 0
for i in range(0, len(mem) - 8, 8):
    a, = struct.unpack_from('<Q', mem, i); s = sym(a)
    if s and ('UE4SS' in s or 'PenDriverPro' in s or 'main.dll' in s or 'lua' in s.lower()):
        print('  ', s); seen += 1
        if seen > 45: break
