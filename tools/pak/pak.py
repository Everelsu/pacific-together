"""List and extract files from the game's own .pak archives (UE 4.27 pak v11, unencrypted, Zlib or stored).

  python -I tools/pak/pak.py list <pak> [glob]              one line per file: size, compressed size, path
  python -I tools/pak/pak.py extract <pak> <out> <glob>...  files matching any glob into <out>/<path>
  python -I tools/pak/pak.py selftest                       builds a small pak in memory and reads it back

Paths are mount point + file path with the leading "../../../" dropped, e.g. PenDriverPro/Content/Gameplay/X.uasset.
Research only: extracted files stay in local/ (git-ignored), never in git.
"""
import fnmatch
import io
import os
import struct
import sys
import zlib

MAGIC = 0x5A6F12E1
FOOTER = 16 + 1 + 4 + 4 + 8 + 8 + 20 + 5 * 32  # key guid, encrypted index, magic, version, index offset/size, hash, methods


class R:
    def __init__(self, b): self.b, self.p = b, 0
    def take(self, n): v = self.b[self.p:self.p + n]; self.p += n; return v
    def u8(self): return self.take(1)[0]
    def u32(self): return struct.unpack("<I", self.take(4))[0]
    def i32(self): return struct.unpack("<i", self.take(4))[0]
    def i64(self): return struct.unpack("<q", self.take(8))[0]
    def fstr(self):
        n = self.i32()
        if n == 0: return ""
        if n > 0: return self.take(n)[:-1].decode("latin-1")
        return self.take(-n * 2)[:-2].decode("utf-16-le")


class Entry:
    __slots__ = ("path", "offset", "size", "usize", "method", "encrypted")


def _entry(r):  # FPakEntry as the index stores it (v11: no timestamp)
    e = Entry()
    e.offset, e.size, e.usize, e.method = r.i64(), r.i64(), r.i64(), r.u32()
    r.take(20)
    if e.method: r.take(16 * r.i32())
    e.encrypted = bool(r.u8() & 1)
    r.u32()
    return e


def _encoded(r):  # FPakFile::DecodePakEntry: one bitfield word, then 32 or 64 bit fields
    v = r.u32()
    if v & 0x3F == 0x3F: r.u32()
    e = Entry()
    e.method = (v >> 23) & 0x3F
    e.encrypted = bool(v & (1 << 22))
    e.offset = r.u32() if v & (1 << 31) else r.i64()
    e.usize = r.u32() if v & (1 << 30) else r.i64()
    e.size = (r.u32() if v & (1 << 29) else r.i64()) if e.method else e.usize
    blocks = (v >> 6) & 0xFFFF
    if blocks > 1 or (blocks == 1 and e.encrypted): r.take(4 * blocks)
    return e


class Pak:
    def __init__(self, path):
        self.f = open(path, "rb")
        self.f.seek(-FOOTER, 2)
        r = R(self.f.read(FOOTER))
        r.take(16)
        enc_index = r.u8()
        magic, self.version = r.u32(), r.i32()
        if magic != MAGIC: raise ValueError("not a pak (magic %08x)" % magic)
        if self.version != 11: raise ValueError("pak version %d, this reads 11" % self.version)
        if enc_index: raise ValueError("encrypted index")
        off, size = r.i64(), r.i64()
        r.take(20)
        self.methods = [""] + [r.take(32).split(b"\0")[0].decode() for _ in range(5)]
        self.f.seek(off)
        ix = R(self.f.read(size))
        mount = ix.fstr()
        self.mount = mount[9:] if mount.startswith("../../../") else mount
        ix.i32()
        ix.take(8)  # path hash seed
        if ix.i32(): ix.take(8 + 8 + 20)  # path hash index: not needed, the full directory index has the names
        if not ix.i32(): raise ValueError("pak has no full directory index")
        doff, dsize = ix.i64(), ix.i64()
        ix.take(20)
        encoded = R(ix.take(ix.i32()))
        plain = [_entry(ix) for _ in range(ix.i32())]
        self.f.seek(doff)
        d = R(self.f.read(dsize))
        self.entries = []
        for _ in range(d.i32()):
            dname = d.fstr()
            for _ in range(d.i32()):
                fname, at = d.fstr(), d.i32()
                if at >= 0:
                    encoded.p = at
                    e = _encoded(encoded)
                else:
                    e = plain[-at - 1]
                e.path = (self.mount + dname + fname).lstrip("/")
                self.entries.append(e)

    def read(self, e):
        if e.encrypted: raise ValueError("encrypted: " + e.path)
        # the copy of the entry in front of the data has the block list, offsets relative to the entry (pak v5+)
        self.f.seek(e.offset)
        h = R(self.f.read(53 + 4 + 16 * 4096))
        h.take(24)
        method = h.u32()
        h.take(20)
        blocks = [(h.i64(), h.i64()) for _ in range(h.i32())] if method else []
        if not method:
            self.f.seek(e.offset + h.p + 5)
            return self.f.read(e.usize)
        name = self.methods[method]
        if name.lower() != "zlib": raise ValueError("compression %s: %s" % (name, e.path))
        out = io.BytesIO()
        for a, b in blocks:
            self.f.seek(e.offset + a)
            out.write(zlib.decompress(self.f.read(b - a)))
        data = out.getvalue()
        if len(data) != e.usize: raise ValueError("size %d, index says %d: %s" % (len(data), e.usize, e.path))
        return data


def _selftest():
    import tempfile
    files = {"PenDriverPro/Content/A.uasset": b"stored " * 10, "PenDriverPro/Content/Sub/B.uexp": os.urandom(3000) + b"z" * 70000}

    def fstr(s): b = s.encode() + b"\0"; return struct.pack("<i", len(b)) + b

    body, plain, dirs = io.BytesIO(), [], {}
    for i, (p, data) in enumerate(files.items()):
        at = body.tell()
        comp = i == 1
        if comp:
            chunks = [zlib.compress(data[k:k + 65536]) for k in range(0, len(data), 65536)]
            hsize = 53 + 4 + 16 * len(chunks)
            blocks, cur = [], hsize
            for c in chunks: blocks.append((cur, cur + len(c))); cur += len(c)
            head = struct.pack("<qqqI", 0, cur - hsize, len(data), 1) + b"\0" * 20 + struct.pack("<i", len(blocks))
            head += b"".join(struct.pack("<qq", a, b) for a, b in blocks) + b"\0" + struct.pack("<I", 65536)
            body.write(head + b"".join(chunks))
            plain.append(struct.pack("<qqqI", at, cur - hsize, len(data), 1) + b"\0" * 20 + struct.pack("<i", len(blocks))
                         + b"".join(struct.pack("<qq", a, b) for a, b in blocks) + b"\0" + struct.pack("<I", 65536))
        else:
            head = struct.pack("<qqqI", 0, len(data), len(data), 0) + b"\0" * 20 + b"\0" + struct.pack("<I", 0)
            body.write(head + data)
            plain.append(struct.pack("<qqqI", at, len(data), len(data), 0) + b"\0" * 20 + b"\0" + struct.pack("<I", 0))
        d, f = p.rsplit("/", 1)
        dirs.setdefault(d.replace("PenDriverPro/", "") + "/", []).append((f, -len(plain)))
    # one entry the encoded way: the stored file again under another name
    enc = struct.pack("<I", (1 << 31) | (1 << 30)) + struct.pack("<II", 0, len(files["PenDriverPro/Content/A.uasset"]))
    dirs.setdefault("Content/", []).append(("C.uasset", 0))
    dix = struct.pack("<i", len(dirs)) + b"".join(fstr(k) + struct.pack("<i", len(v)) + b"".join(fstr(n) + struct.pack("<i", a) for n, a in v) for k, v in dirs.items())
    doff = body.tell()
    body.write(dix)
    ix = fstr("../../../PenDriverPro/") + struct.pack("<i", 3) + b"\0" * 8 + struct.pack("<i", 0) + struct.pack("<i", 1)
    ix += struct.pack("<qq", doff, len(dix)) + b"\0" * 20 + struct.pack("<i", len(enc)) + enc + struct.pack("<i", len(plain)) + b"".join(plain)
    ioff = body.tell()
    body.write(ix)
    body.write(b"\0" * 17 + struct.pack("<Iiqq", MAGIC, 11, ioff, len(ix)) + b"\0" * 20 + b"Zlib".ljust(32, b"\0") + b"\0" * 128)
    with tempfile.TemporaryDirectory() as t:
        p = os.path.join(t, "t.pak")
        with open(p, "wb") as f: f.write(body.getvalue())
        pak = Pak(p)
        got = {e.path: pak.read(e) for e in pak.entries}
        pak.f.close()
    want = dict(files, **{"PenDriverPro/Content/C.uasset": files["PenDriverPro/Content/A.uasset"]})
    assert got == want, sorted(got)
    print("selftest ok: %d files" % len(got))


def main(a):
    if a[:1] == ["selftest"]: return _selftest()
    if len(a) < 2 or a[0] not in ("list", "extract"): sys.exit(__doc__)
    pak = Pak(a[1])
    if a[0] == "list":
        pat = a[2] if len(a) > 2 else "*"
        for e in pak.entries:
            if fnmatch.fnmatch(e.path, pat): print("%d\t%d\t%s" % (e.usize, e.size, e.path))
        return
    out, pats = a[2], a[3:] or ["*"]
    n = 0
    for e in pak.entries:
        if any(fnmatch.fnmatch(e.path, p) for p in pats):
            dst = os.path.join(out, *e.path.split("/"))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "wb") as f: f.write(pak.read(e))
            n += 1
    print("%d file(s) -> %s" % (n, out))


if __name__ == "__main__":
    main(sys.argv[1:])
