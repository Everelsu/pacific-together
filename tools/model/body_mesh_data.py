"""Writes mod/PacificTogether/Scripts/survivor_mesh.lua (the other player's body, see survivor.lua) from a skinned Maya ASCII
character on the UE5 mannequin skeleton, e.g. the Rogue in local/player_model/rogue/rogue_free.ma. No Maya, Blender or UE.

Each triangle goes to the one game bone that moves it most (UE5-only bones fold into their nearest game ancestor:
spine_04/05 -> spine_03, neck_02 -> neck_01, twist/corrective -> their limb bone, fingers -> hand), because survivor.lua hangs
one rigid part per bone. Output per bone: rest direction and length, and per (material, part) a section with positions relative
to the bone head in cm in Unreal component axes (Maya y-up/+z-forward -> x left, y forward, z up), smooth normals, 0-based tris.

  python -I tools/model/body_mesh_data.py <scene.ma> [preview.png]
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from maya_ascii import Scene  # noqa: E402

GAME = ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head"] + [
    b + s for s in ("_l", "_r") for b in ("clavicle", "upperarm", "lowerarm", "hand", "thigh", "calf", "foot", "ball")]
# the joint giving a bone's direction (as CHILD in survivor.lua; head points from the neck, ball like the foot)
# the game bone a part's anchor is placed by (survivor.lua PARENT): each part starts where its parent puts the model's joint
PARENT = {"spine_03": "pelvis", "head": "spine_03", "upperarm": "spine_03", "lowerarm": "upperarm", "hand": "lowerarm",
          "thigh": "pelvis", "calf": "thigh", "foot": "calf", "ball": "foot"}
CHILD = {"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "head",
         "clavicle": "upperarm", "upperarm": "lowerarm", "lowerarm": "hand", "hand": "middle_01", "thigh": "calf",
         "calf": "foot", "foot": "ball"}

# Simplified for rigid parts (hand play 2026-10-31): straps, pads and the cloak tore apart between bones and their copies crossed
# each other, so they are left out; the torso is two blocks (hips, chest) instead of five bones, the neck is part of the head
DROP = {"shoulderPad", "elbowPads", "kneePad", "mantle"}
# kept whole on the one bone that moves them most (the belts and straps cover jacket that is not modelled under them)
RIGID = {"beltA", "beltB", "topB"}
MERGE = {"spine_01": "pelvis", "spine_02": "spine_03", "clavicle_l": "spine_03", "clavicle_r": "spine_03", "neck_01": "head"}
HANG = {"topA"}  # kept off the legs: the jacket's skirt split onto the thighs hung in jagged strips (hand play 2026-10-31)
# the model's joint a game bone's part hangs from, where the two skeletons differ: the game's (UE4) spine_03 is the chest
# (140 cm), the model's (UE5) spine_03 the waist (113 cm), its chest bone spine_05 (141 cm). From spine_03 the chest sat 26 cm
# off and opened a gap at the waist (hand play 2026-10-31)
ANCHOR = {"spine_03": "spine_05"}


def ue(p):  # Maya (x left, y up, z forward) -> Unreal component (x left, y forward, z up); flips handedness like the old y = -by
    return np.stack([p[..., 0], p[..., 2], p[..., 1]], -1)


def game_bone(sc, joint):
    if joint == "root":  # stray skin weights on the root move with the body
        return "pelvis"
    j = joint
    while j and j not in GAME:
        j = sc.nodes[j]["parent"]
    if not j:
        raise ValueError("joint %s has no game bone above it" % joint)
    return MERGE.get(j, j)


# Glowing faces on the mask (head_geo), one per variant, in Maya front view coordinates: x = the character's left (the viewer's
# right), y = height, cm. ("stroke", width, points) is a ribbon along the points, ("disc", radius, centre) a filled circle.
def _smile(x): return 163.0 + 0.17 * x * x


GLOW = {
    "glow1": [  # host: slanted eyes and a wide grin
        ("stroke", 0.75, [(-3.3, 171.0), (-2.2, 170.2), (-1.0, 169.4)]),
        ("stroke", 0.75, [(3.3, 171.0), (2.2, 170.2), (1.0, 169.4)]),
        ("stroke", 0.7, [(x / 10, _smile(x / 10)) for x in range(-34, 35, 4)]),
    ],
    "glow2": [  # guest: round eyes and a zigzag mouth
        ("disc", 1.0, (-2.0, 169.6)),
        ("disc", 1.0, (2.0, 169.6)),
        ("stroke", 0.4, [(x / 10, 163.0 + 0.08 * (x / 10) ** 2 + (0.35 if (x // 6) % 2 else -0.35)) for x in range(-30, 31, 6)]),
    ],
}
GLOW_LIFT = 0.25  # cm above the mask, so it never sinks into it
GLOW_PREVIEW = {"glow1": (1.0, 0.8, 0.3), "glow2": (0.5, 1.0, 0.6)}  # preview only; the game's colours are in survivor.lua


def glow_faces(sc):
    """per design: positions (Maya), triangles, normals, projected along -z onto the mask's front"""
    MP, polys = sc.mesh("head_geoShapeOrig")
    tri = np.array([(p[0], p[k], p[k + 1]) for p in polys for k in range(1, len(p) - 1)])
    A, B, C = MP[tri[:, 0]], MP[tri[:, 1]], MP[tri[:, 2]]

    def hit(x, y):  # the frontmost mask point at (x, y), lifted along its normal
        best = None
        for a, b, c in zip(A, B, C):
            d = (b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])
            if abs(d) < 1e-9:
                continue
            u = ((x - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (y - a[1])) / d
            v = ((b[0] - a[0]) * (y - a[1]) - (x - a[0]) * (b[1] - a[1])) / d
            if u < 0 or v < 0 or u + v > 1:
                continue
            p = a + u * (b - a) + v * (c - a)
            n = np.cross(b - a, c - a)
            n = n / np.linalg.norm(n)
            if n[2] < 0:
                n = -n
            if best is None or p[2] > best[0][2]:
                best = (p, n)
        if best is None:
            raise ValueError("glow point %.1f,%.1f misses the mask" % (x, y))
        return best[0] + best[1] * GLOW_LIFT, best[1]

    out = {}
    for name, shapes in GLOW.items():
        P, N, T = [], [], []

        def vert(x, y):
            p, n = hit(x, y)
            P.append(p)
            N.append(n)
            return len(P) - 1

        def tri_(i, j, k):  # Maya faces count counter-clockwise seen from the front (+z)
            a, b, c = P[i], P[j], P[k]
            T.extend((i, j, k) if np.cross(b - a, c - a)[2] > 0 else (i, k, j))
        for kind, size, pts in shapes:
            if kind == "disc":
                cx, cy = pts
                c = vert(cx, cy)
                ring = [vert(cx + size * np.cos(a), cy + size * np.sin(a)) for a in np.linspace(0, 2 * np.pi, 17)[:-1]]
                for k in range(16):
                    tri_(c, ring[k], ring[(k + 1) % 16])
            else:
                pts = np.array(pts, float)
                prev = None
                for k, p in enumerate(pts):
                    d = pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]
                    side = np.array([-d[1], d[0]]) / np.linalg.norm(d) * size / 2
                    cur = (vert(*(p + side)), vert(*(p - side)))
                    if prev:
                        tri_(prev[0], prev[1], cur[1])
                        tri_(prev[0], cur[1], cur[0])
                    prev = cur
        out[name] = (np.array(P), T, np.array(N))
    return out


def build(path):
    sc = Scene(path)
    jpos = lambda n: ue(sc.joint_world(n)[3, :3])
    mats = sorted(sc.of("lambert"))
    parts = {}  # bone -> {(mat, part): [P list, N list, T list, index map]}
    for c in sorted(sc.of("skinCluster"), key=lambda x: int(x[len("skinCluster"):] or 0)):
        orig, joints, W, _ = sc.skin(c)
        P, polys = sc.mesh(orig)
        shape = orig[:-4] if orig.endswith("Orig") else orig
        part = shape.replace("_geoShape", "")
        if part in DROP:
            continue
        whole, per = sc.materials(shape)
        P = ue(P)
        # Maya's corner order kept as is: the axis swap flips handedness, which is what makes them front faces in UE (as the old
        # Blender export did with y = -y); reversing them drew the body inside out (hand play 2026-10-31)
        tris, tmat = [], []
        for fi, poly in enumerate(polys):
            for k in range(1, len(poly) - 1):
                tris.append((poly[0], poly[k], poly[k + 1]))
                tmat.append(per.get(fi, whole))
        # smooth, area weighted, outward (the axis swap turns the plain cross product inward); the model's hard edges made the
        # low-poly panels look faceted (hand play 2026-10-31): round is the look wanted
        N = np.zeros_like(P)
        for poly in polys:
            q = P[poly]
            n = -sum(np.cross(q[k] - q[0], q[k + 1] - q[0]) for k in range(1, len(poly) - 1))
            N[poly] += n
        N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
        vb = [{} for _ in range(len(P))]  # vertex -> game bone -> weight
        for vi, ws in W.items():
            for inf, w in ws.items():
                b = game_bone(sc, joints[inf])
                vb[vi][b] = vb[vi].get(b, 0) + w
        total = {}
        for ws in vb:
            for b, w in ws.items():
                total[b] = total.get(b, 0) + w
        rigid = max(total, key=total.get)
        for t, m in zip(tris, tmat):
            if m is None:
                raise ValueError("%s: a face without material" % shape)
            score = {}
            for vi in t:
                for b, w in vb[vi].items():
                    score[b] = score.get(b, 0) + w
            # the one bone that moves it most (copies on a second bone did not line up: each part turns onto the game's pose
            # by its own angle, so they stuck out as spikes at the shoulders and neck, hand play 2026-10-31)
            bones = {max(score, key=score.get)}
            if part in RIGID:
                bones = {rigid}
            if part in HANG:
                bones = {"pelvis" if b[:-2] in ("thigh", "calf", "foot", "ball") else b for b in bones}
            for bone in bones:
                sec = parts.setdefault(bone, {}).setdefault((mats.index(m) + 1, part), [[], [], [], {}])
                head = jpos(ANCHOR.get(bone, bone))
                for vi in t:
                    if vi not in sec[3]:
                        sec[3][vi] = len(sec[0])
                        sec[0].append(P[vi] - head)
                        sec[1].append(N[vi])
                    sec[2].append(sec[3][vi])
    for name, (P, T, N) in glow_faces(sc).items():
        parts["head"][(0, name)] = [list(ue(P) - jpos("head")), list(ue(N)), T, None]
    bones = {}
    for bone, secs in parts.items():
        sfx = bone[-2:] if bone[-2:] in ("_l", "_r") else ""
        base = bone[:len(bone) - len(sfx)]
        if base == "head":
            d = jpos("head") - jpos("neck_01")
        elif base == "ball":
            d = jpos(bone) - jpos("foot" + sfx)
        else:
            d = jpos(CHILD[base] + sfx) - jpos(ANCHOR.get(bone, bone))
        bones[bone] = (d / np.linalg.norm(d), np.linalg.norm(d), secs, jpos(ANCHOR.get(bone, bone)))
    return [(m, sc.color(m)) for m in mats], bones


def write(mats, bones, out, src):
    f = lambda xs: ",".join("%g" % round(x, 2) for x in xs)
    g = lambda xs: ",".join("%g" % round(x, 3) for x in xs)
    lines = ["-- generated by tools/model/body_mesh_data.py from %s: do not edit" % os.path.basename(src), "return {",
             "  materials = {" + ", ".join('"%s"' % m for m, _ in mats) + "},",
             "  colors = {" + ", ".join("{%g,%g,%g}" % tuple(round(x, 4) for x in c) for _, c in mats) + "},", "  bones = {"]
    for bone in GAME:
        if bone not in bones:
            continue
        d, l, secs, at = bones[bone]
        lines.append("    %s = { dir = {%.4f,%.4f,%.4f}, len = %.2f, at = {%.2f,%.2f,%.2f}, sections = {" % (bone, *d, l, *at))
        for (mat, part), (P, N, T, _) in sorted(secs.items()):
            lines.append('      { mat = %d, part = "%s", v = {%s}, n = {%s}, t = {%s} },' % (
                mat, part, f(np.ravel(P)), g(np.ravel(N)), ",".join(map(str, T))))
        lines.append("    } },")
    lines += ["  },", "}"]
    open(out, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


def preview(mats, bones, png):
    """the body as survivor.lua places it in the mannequin's reference pose: front and side view, flat-lit"""
    import re
    from PIL import Image, ImageDraw
    src = open(os.path.join(os.path.dirname(__file__), "..", "..", "mod", "PacificTogether", "Scripts", "survivor.lua"), encoding="utf-8").read()
    REF = {k: [float(x) for x in v.split(",")] for k, v in re.findall(r"(\w+)=\{([-\d.,]+)\}", src.split("local REF = {", 1)[1].split("\n}", 1)[0])}

    def between(a, b):
        k, c = np.cross(a, b), a @ b
        K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
        return np.eye(3) + K + K @ K / (1 + c)
    pos = lambda n: np.array(REF[n][:3])
    place = {}

    def get(bone):  # as survivor.lua build(): the part's map of model points (relative to its anchor) into the reference pose
        if bone in place:
            return place[bone]
        ds, ln, secs, at = bones[bone]
        sfx = bone[-2:] if bone[-2:] in ("_l", "_r") else ""
        base = bone[:len(bone) - len(sfx)]
        dmv = (pos("head") - pos("neck_01")) if base == "head" else (pos(bone) - pos("foot" + sfx)) if base == "ball" else (pos(CHILD[base] + sfx) - pos(bone))
        if base == "ball":
            ds, ln = bones["foot" + sfx][0], bones["foot" + sfx][1]
        R = between(ds, dmv / np.linalg.norm(dmv))
        par = PARENT.get(base)
        off = get(par if par in bones else par + sfx)(np.array(at) - bones[par if par in bones else par + sfx][3]) - pos(bone) if par else 0

        def T(v):
            return np.atleast_2d(v) @ R.T + pos(bone) + off
        place[bone] = T
        return T
    tris = []
    for bone, (ds, ln, secs, at) in bones.items():
        T = get(bone)
        sfx = bone[-2:] if bone[-2:] in ("_l", "_r") else ""
        base = bone[:len(bone) - len(sfx)]
        for (mat, part), (P, N, Tr, _) in secs.items():
            P = T(np.array(P))
            Nn = T(np.array(N)) - T(np.zeros(3))
            for i in range(0, len(Tr), 3):
                t = Tr[i:i + 3]
                tris.append((P[t], Nn[t].mean(0), mats[mat - 1][1] if mat else GLOW_PREVIEW[part]))
    img = Image.new("RGB", (800, 700), (40, 44, 52))
    d = ImageDraw.Draw(img)
    light = np.array([0.4, 0.7, 0.6]); light /= np.linalg.norm(light)
    for ox, view, eye in ((200, (0, 2), np.array([0, 1, 0])), (600, (1, 2), np.array([-1, 0, 0]))):  # front (from +Y), left side
        order = sorted(tris, key=lambda t: t[0].mean(0) @ eye)  # far first
        for P, n, c in order:
            if n @ eye < -0.05:
                continue
            s = 0.35 + 0.65 * max(0, n @ light)
            col = tuple(int(255 * min(1, (x ** (1 / 2.2)) * s)) for x in c)
            sgn = -1 if view[0] == 0 else 1
            d.polygon([(ox + sgn * p[view[0]] * 3.4, 660 - p[view[1]] * 3.4) for p in P], fill=col)
    img.save(png)


if __name__ == "__main__":
    src = sys.argv[1]
    mats, bones = build(src)
    out = os.path.join(os.path.dirname(__file__), "..", "..", "mod", "PacificTogether", "Scripts", "survivor_mesh.lua")
    write(mats, bones, out, src)
    nt = sum(len(s[2]) // 3 for _, _, secs, _ in bones.values() for s in secs.values())
    nv = sum(len(s[0]) for _, _, secs, _ in bones.values() for s in secs.values())
    print("bones", len(bones), "sections", sum(len(b[2]) for b in bones.values()), "verts", nv, "tris", nt, "bytes", os.path.getsize(out))
    for b in GAME:
        if b in bones:
            print("  %-11s %5d tris  %s" % (b, sum(len(s[2]) // 3 for s in bones[b][2].values()), " ".join(sorted({p for _, p in bones[b][2]}))))
    if len(sys.argv) > 2:
        preview(mats, bones, sys.argv[2])
