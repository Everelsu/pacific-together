"""Reads the parts of a Maya ASCII (.ma) scene a skinned character needs: bind-pose meshes, skin weights, joint bind
matrices, joint parents, lambert colours and which material each face has. Plain text parsing, no Maya or Blender.

  python -I tools/model/maya_ascii.py <scene.ma>      prints a summary (meshes, faces, joints, materials)
"""
import re
import sys

import numpy as np


def statements(text):
    """(command, rest) per MEL statement; a statement ends at a ';' that closes a line (values never contain one)."""
    buf = []
    for line in text.splitlines():
        buf.append(line.strip())
        if line.rstrip().endswith(";"):
            s = " ".join(buf)[:-1].strip()
            buf = []
            if s and not s.startswith("//"):
                cmd, _, rest = s.partition(" ")
                yield cmd, rest


def words(s):
    return re.findall(r'"[^"]*"|\S+', s)


def rng(spec):
    a, _, b = spec.partition(":")
    return int(a), int(b or a)


class Scene:
    def __init__(self, path):
        self.nodes = {}  # name -> {"type", "parent", "attrs": [(attr, values words)]}
        self.conns = []  # (src, dst)
        cur = None
        for cmd, rest in statements(open(path, encoding="latin1").read()):
            if cmd == "createNode":
                w = words(rest)
                name = w[w.index("-n") + 1].strip('"')
                parent = w[w.index("-p") + 1].strip('"') if "-p" in w else None
                cur = self.nodes[name] = {"type": w[0], "parent": parent, "attrs": []}
            elif cmd == "setAttr" and cur is not None:
                # flags can stand before or after the attribute name; negative numbers are values, not flags
                flags, rest_w, w, i = {}, [], words(rest), 0
                while i < len(w):
                    if re.fullmatch(r"-[a-zA-Z]+", w[i]):
                        if w[i] in ("-k", "-l", "-cb", "-ch", "-s", "-type"):
                            flags[w[i]] = w[i + 1].strip('"'); i += 2
                        else:
                            i += 1  # -av, -c: no argument
                    else:
                        rest_w.append(w[i]); i += 1
                if rest_w:
                    cur["attrs"].append((rest_w[0].strip('"'), flags, rest_w[1:]))
            elif cmd == "connectAttr":
                w = [x.strip('"') for x in words(rest) if not x.startswith("-")]
                if len(w) >= 2:
                    self.conns.append((w[0], w[1]))
            elif cmd in ("select", "requires", "fileInfo", "currentUnit", "file", "relationship", "lockNode"):
                cur = None if cmd == "select" else cur

    def of(self, typ):
        return [n for n, d in self.nodes.items() if d["type"] == typ]

    def attr(self, node, pattern):
        """every (match, flags, values) of an attribute name matching the regex"""
        out = []
        for a, f, v in self.nodes[node]["attrs"]:
            m = re.fullmatch(pattern, a)
            if m:
                out.append((m, f, v))
        return out

    # --- meshes -------------------------------------------------------------------------------------------------------
    def mesh(self, shape):
        """positions (n,3), polygons as vertex index lists, for a mesh shape (the Orig shape holds the bind pose)"""
        nv = 0
        for m, f, v in self.attr(shape, r"\.vt"):
            nv = int(f.get("-s", 0))
        P = np.zeros((nv, 3))
        for m, f, v in self.attr(shape, r"\.vt\[(\d+(?::\d+)?)\]"):
            a, b = rng(m.group(1))
            P[a:b + 1] = np.array([float(x) for x in v], dtype=float).reshape(-1, 3)
        E = {}
        for m, f, v in self.attr(shape, r"\.ed\[(\d+(?::\d+)?)\]"):
            a, b = rng(m.group(1))
            vals = [int(float(x)) for x in v]
            for k in range(b - a + 1):
                E[a + k] = (vals[3 * k], vals[3 * k + 1])
        polys = []
        for m, f, v in self.attr(shape, r"\.fc\[(\d+(?::\d+)?)\]"):
            i = 0
            while i < len(v):
                tag, n = v[i], int(v[i + 1])
                if tag in ("f", "h"):
                    es = [int(x) for x in v[i + 2:i + 2 + n]]
                    if tag == "h":
                        raise ValueError(shape + ": polygon holes are not supported")
                    polys.append([E[e][0] if e >= 0 else E[-e - 1][1] for e in es])
                    i += 2 + n
                elif tag == "mu":  # uv set index, count, uv ids
                    n = int(v[i + 2]); i += 3 + n
                elif tag in ("mc", "fc"):
                    n = int(v[i + 2]) if tag == "mc" else n; i += (3 + n) if tag == "mc" else (2 + n)
                elif tag in ("mf", "mh"):
                    i += 2 + n
                else:
                    raise ValueError("%s: unknown face tag %s" % (shape, tag))
        return P, polys

    def face_groups(self, shape):
        """og index -> face index list: shape.iog.og[k].gid <- groupId, groupParts.gi <- the same groupId, its .ic = faces"""
        gid_faces = {}
        for gp in self.of("groupParts"):
            gid = next((a.split(".")[0] for a, b in self.conns if b == gp + ".gi"), None)
            faces = []
            for m, f, v in self.attr(gp, r"\.ic"):
                for c in v[1:]:
                    mm = re.fullmatch(r'"f\[(\d+(?::\d+)?)\]"', c)
                    if mm:
                        a, b = rng(mm.group(1)); faces += range(a, b + 1)
            if gid:
                gid_faces[gid] = faces
        out = {}
        for a, b in self.conns:
            m = re.fullmatch(re.escape(shape) + r"\.iog\.og\[(\d+)\]\.gid", b)
            if m:
                out[int(m.group(1))] = gid_faces.get(a.split(".")[0], [])
        return out

    def materials(self, shape):
        """face index -> material name (lambert), or None -> one material for all faces"""
        sg_mat = {}
        for s, d in self.conns:
            if s.endswith(".oc") and d.endswith(".ss"):
                sg_mat[d[:-3]] = s[:-3]
        whole, per = None, {}
        groups = self.face_groups(shape)
        for s, d in self.conns:
            if not d.endswith(".dsm") or not s.startswith(shape + ".iog"):
                continue
            mat = sg_mat.get(d[:-4])
            m = re.fullmatch(re.escape(shape) + r"\.iog(?:\.og\[(\d+)\])?", s)
            if m and m.group(1) is None:
                whole = mat
            elif m:
                for fi in groups.get(int(m.group(1)), []):
                    per[fi] = mat
        return whole, per

    def color(self, mat):
        for m, f, v in self.attr(mat, r"\.c"):
            return [float(x) for x in v]
        return [0.5, 0.5, 0.5]  # Maya's lambert default

    # --- joints -------------------------------------------------------------------------------------------------------
    def joint_world(self, name, _cache={}):
        """bind world matrix (row vectors, translation in row 3) from .t/.r/.jo/.ra up the parents (rotate order xyz)"""
        key = (id(self), name)
        if key in _cache:
            return _cache[key]

        def v3(a):
            r = self.attr(name, a)
            return np.array([float(x) for x in r[0][2]]) if r and r[0][2] else np.zeros(3)

        def eul(d):
            x, y, z = np.radians(d)
            cx, sx, cy, sy, cz, sz = np.cos(x), np.sin(x), np.cos(y), np.sin(y), np.cos(z), np.sin(z)
            return (np.array([[1, 0, 0], [0, cx, sx], [0, -sx, cx]]) @ np.array([[cy, 0, -sy], [0, 1, 0], [sy, 0, cy]])
                    @ np.array([[cz, sz, 0], [-sz, cz, 0], [0, 0, 1]]))
        if self.attr(name, r"\.ro"):
            raise ValueError(name + ": only rotate order xyz is supported")
        M = np.eye(4)
        M[:3, :3] = eul(v3(r"\.ra")) @ eul(v3(r"\.r")) @ eul(v3(r"\.jo"))
        M[3, :3] = v3(r"\.t")
        p = self.nodes[name]["parent"]
        if p in self.nodes:
            M = M @ self.joint_world(p)
        _cache[key] = M
        return M

    # --- skin ---------------------------------------------------------------------------------------------------------
    def skin(self, cluster):
        """(orig shape, joints by influence index, weights {vertex: {influence: w}}, bind world matrix per influence)"""
        orig = joints = None
        joints = {}
        for s, d in self.conns:
            if d == cluster + ".ip[0].ig":
                orig = s.split(".")[0]
                # multi-material meshes come through groupParts nodes: follow their input geometry to the mesh
                while orig and self.nodes[orig]["type"] != "mesh":
                    orig = next((a.split(".")[0] for a, b in self.conns if b in (orig + ".ig", orig + ".ip[0].ig")), None)
            m = re.fullmatch(re.escape(cluster) + r"\.ma\[(\d+)\]", d)
            if m and s.endswith(".wm"):
                joints[int(m.group(1))] = s[:-3]
        W = {}
        for m, f, v in self.attr(cluster, r"\.wl\[(\d+(?::\d+)?)\]\.w"):
            a, b = rng(m.group(1))
            i = 0
            for vi in range(a, b + 1):
                n = int(v[i]); i += 1
                W[vi] = {int(v[i + 2 * k]): float(v[i + 2 * k + 1]) for k in range(n)}
                i += 2 * n
        for m, f, v in self.attr(cluster, r"\.wl\[(\d+)\]\.w\[(\d+)\]"):
            W.setdefault(int(m.group(1)), {})[int(m.group(2))] = float(v[0])
        bind = {}
        for m, f, v in self.attr(cluster, r"\.pm\[(\d+)\]"):
            pm = np.array([float(x) for x in v]).reshape(4, 4)  # row vectors: p_local = p_world @ pm
            bind[int(m.group(1))] = np.linalg.inv(pm)
        for m, f, v in self.attr(cluster, r"\.gm"):
            if not np.allclose(np.array([float(x) for x in v]).reshape(4, 4), np.eye(4)):
                raise ValueError(cluster + ": non-identity geometry matrix is not supported")
        return orig, joints, W, bind


if __name__ == "__main__":
    sc = Scene(sys.argv[1])
    for c in sc.of("skinCluster"):
        orig, joints, W, bind = sc.skin(c)
        P, polys = sc.mesh(orig)
        shape = orig[:-4] if orig.endswith("Orig") else orig
        whole, per = sc.materials(shape)
        print(c, orig, "verts", len(P), "polys", len(polys), "weighted", len(W), "influences", len(joints), "mat", whole, set(per.values()))
        # self-check: the hierarchy gives the same bind matrices the skin cluster stored
        for k, n in joints.items():
            assert np.allclose(sc.joint_world(n), bind[k], atol=1e-3), n
    print("joints", len(sc.of("joint")))
    for m in sc.of("lambert"):
        print("material", m, sc.color(m))
