"""Builds the co-op player placeholder: a low-poly survivor on a UE4 Mannequin-named skeleton.

Run inside Blender (Text Editor > Run, or the Blender MCP). Rebuilds everything in the
"PlayerModel" collection. Blender front is -Y, 1 unit = 1 m, character ~1.80 m tall.
Each mesh part is rigidly weighted (1.0) to a single bone, so no weight painting is needed.
"""
import bpy, bmesh
from mathutils import Vector, Matrix

scene = bpy.context.scene
scene.render.fps = 30

COL = "PlayerModel"
col = bpy.data.collections.get(COL)
if col:
    for o in list(col.objects):
        bpy.data.objects.remove(o, do_unlink=True)
else:
    col = bpy.data.collections.new(COL)
    scene.collection.children.link(col)
for coll, name in ((bpy.data.meshes, "SK_CoopSurvivor"), (bpy.data.armatures, "SK_CoopSurvivor_Skeleton")):
    d = coll.get(name)
    if d and d.users == 0:
        coll.remove(d)

# ---------- skeleton (UE4 Mannequin bone names and parenting) ----------
bones = [
    ("root", (0,0,0), (0,0,0.25), None),
    ("pelvis", (0,0,0.94), (0,0,1.04), "root"),
    ("spine_01", (0,0,1.04), (0,0,1.16), "pelvis"),
    ("spine_02", (0,0,1.16), (0,0,1.29), "spine_01"),
    ("spine_03", (0,0,1.29), (0,0,1.44), "spine_02"),
    ("neck_01", (0,0,1.44), (0,-0.01,1.54), "spine_03"),
    ("head", (0,-0.01,1.54), (0,-0.01,1.76), "neck_01"),
]
for s, sd in ((1, "l"), (-1, "r")):
    bones += [
        (f"clavicle_{sd}", (s*0.03,0,1.41), (s*0.18,0,1.42), "spine_03"),
        (f"upperarm_{sd}", (s*0.19,0,1.41), (s*0.22,0,1.13), f"clavicle_{sd}"),
        (f"lowerarm_{sd}", (s*0.22,0,1.13), (s*0.235,0,0.88), f"upperarm_{sd}"),
        (f"hand_{sd}", (s*0.235,0,0.88), (s*0.24,0,0.79), f"lowerarm_{sd}"),
        (f"thigh_{sd}", (s*0.10,0,0.93), (s*0.10,0,0.51), "pelvis"),
        (f"calf_{sd}", (s*0.10,0,0.51), (s*0.10,0,0.09), f"thigh_{sd}"),
        (f"foot_{sd}", (s*0.10,0,0.09), (s*0.10,-0.13,0.025), f"calf_{sd}"),
        (f"ball_{sd}", (s*0.10,-0.13,0.025), (s*0.10,-0.21,0.025), f"foot_{sd}"),
    ]

arm_data = bpy.data.armatures.new("SK_CoopSurvivor_Skeleton")
arm = bpy.data.objects.new("Armature", arm_data)  # named "Armature" so UE's FBX import adds no extra root bone
col.objects.link(arm)
arm_data.display_type = 'STICK'
arm.show_in_front = True

bpy.context.view_layer.objects.active = arm
for o in bpy.context.selected_objects:
    o.select_set(False)
arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
eb = arm_data.edit_bones
X = Vector((1,0,0))
for name, h, t, parent in bones:
    b = eb.new(name)
    b.head, b.tail = Vector(h), Vector(t)
    if parent:
        b.parent = eb[parent]
        b.use_connect = (Vector(h) - eb[parent].tail).length < 1e-4
    y = (b.tail - b.head).normalized()
    if abs(y.dot(X)) < 0.9:
        b.align_roll(X.cross(y))  # local X = world X: rotation about local X swings fore/aft
    else:
        b.align_roll(Vector((0,0,1)))
bpy.ops.object.mode_set(mode='OBJECT')

# ---------- mesh ----------
MATS = [("M_Survivor_Suit",(0.32,0.29,0.19)), ("M_Survivor_Boots",(0.11,0.07,0.045)),
        ("M_Survivor_Gloves",(0.07,0.07,0.07)), ("M_Survivor_Skin",(0.62,0.42,0.32)),
        ("M_Survivor_Hair",(0.06,0.04,0.03)), ("M_Survivor_Gear",(0.15,0.17,0.11))]
SUIT, BOOTS, GLOVES, SKIN, HAIR, GEAR = range(6)

bm = bmesh.new()
dl = bm.verts.layers.deform.verify()
bone_names = [b[0] for b in bones]
gidx = {n: i for i, n in enumerate(bone_names)}

def snap():
    return set(bm.verts), set(bm.faces)

def finish(before_v, before_f, bone, mat, smooth):
    for v in bm.verts:
        if v not in before_v:
            v[dl][gidx[bone]] = 1.0
    for f in bm.faces:
        if f not in before_f:
            f.material_index = mat
            f.smooth = smooth

def cone(bone, p0, p1, r0, r1, mat, seg=10):
    bv, bf = snap()
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    m = Matrix.Translation((p0+p1)/2) @ Vector((0,0,1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r0, radius2=r1,
                          depth=d.length, matrix=m)
    finish(bv, bf, bone, mat, True)

def sphere(bone, c, r, mat, u=10, v=7):
    bv, bf = snap()
    m = Matrix.Translation(c) @ Matrix.Diagonal((*r, 1))
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0, matrix=m)
    finish(bv, bf, bone, mat, True)

def box(bone, c, size, mat, bevel=0.015):
    bv, bf = snap()
    vs = bmesh.ops.create_cube(bm, size=1.0)["verts"]
    bmesh.ops.scale(bm, vec=Vector(size), verts=vs)
    if bevel > 0:
        edges = list({e for v in vs for e in v.link_edges})
        bmesh.ops.bevel(bm, geom=edges + vs, offset=bevel, segments=1, profile=0.5, affect='EDGES')
    bmesh.ops.translate(bm, vec=Vector(c), verts=[v for v in bm.verts if v not in bv])
    finish(bv, bf, bone, mat, False)

# head
sphere("head", (0,-0.01,1.645), (0.095,0.105,0.115), SKIN, 12, 8)
sphere("head", (0,0.02,1.685), (0.1,0.1,0.095), HAIR, 12, 8)
for s in (1,-1):
    sphere("head", (s*0.035,-0.109,1.655), (0.013,0.008,0.011), HAIR, 8, 5)
box("head", (0,-0.118,1.635), (0.025,0.03,0.04), SKIN, 0.006)
for s in (1,-1):
    sphere("head", (s*0.095,-0.005,1.64), (0.015,0.025,0.03), SKIN, 8, 5)
cone("neck_01", (0,-0.005,1.43), (0,-0.01,1.57), 0.05, 0.048, SKIN)
# torso
cone("spine_03", (0,0,1.42), (0,0,1.48), 0.085, 0.068, SUIT, 12)
box("spine_03", (0,0,1.355), (0.36,0.21,0.19), SUIT, 0.04)
box("spine_02", (0,0,1.225), (0.31,0.19,0.15), SUIT, 0.035)
box("spine_01", (0,0,1.10), (0.30,0.19,0.14), SUIT, 0.035)
box("pelvis", (0,0,0.97), (0.33,0.20,0.14), SUIT, 0.035)
box("pelvis", (0,0,1.035), (0.335,0.21,0.04), GEAR, 0.01)
box("pelvis", (0,-0.107,1.035), (0.05,0.012,0.035), BOOTS, 0.004)
# backpack
box("spine_03", (0,0.165,1.30), (0.28,0.13,0.32), GEAR, 0.03)
cone("spine_03", (-0.14,0.15,1.49), (0.14,0.15,1.49), 0.055, 0.055, BOOTS, 10)
for s in (1,-1):
    box("spine_03", (s*0.09,-0.107,1.33), (0.04,0.012,0.20), GEAR, 0.004)
# limbs
for s, sd in ((1,"l"),(-1,"r")):
    sphere(f"upperarm_{sd}", (s*0.19,0,1.41), (0.066,)*3, SUIT)
    cone(f"upperarm_{sd}", (s*0.19,0,1.41), (s*0.22,0,1.13), 0.058, 0.048, SUIT)
    sphere(f"lowerarm_{sd}", (s*0.22,0,1.13), (0.05,)*3, SUIT)
    cone(f"lowerarm_{sd}", (s*0.22,0,1.13), (s*0.235,0,0.90), 0.047, 0.04, SUIT)
    cone(f"lowerarm_{sd}", (s*0.233,0,0.935), (s*0.236,0,0.87), 0.046, 0.045, GLOVES)
    box(f"hand_{sd}", (s*0.238,-0.005,0.82), (0.045,0.085,0.11), GLOVES, 0.015)
    box(f"hand_{sd}", (s*0.232,-0.05,0.85), (0.03,0.03,0.055), GLOVES, 0.008)
    cone(f"thigh_{sd}", (s*0.10,0,0.97), (s*0.10,0,0.51), 0.085, 0.06, SUIT, 12)
    box(f"thigh_{sd}", (s*0.168,0,0.70), (0.03,0.10,0.12), GEAR, 0.008)
    sphere(f"calf_{sd}", (s*0.10,-0.005,0.51), (0.058,)*3, SUIT)
    cone(f"calf_{sd}", (s*0.10,0,0.51), (s*0.10,0,0.25), 0.056, 0.05, SUIT)
    cone(f"calf_{sd}", (s*0.10,0,0.28), (s*0.10,0,0.06), 0.058, 0.055, BOOTS)
    box(f"foot_{sd}", (s*0.10,-0.045,0.05), (0.10,0.20,0.08), BOOTS, 0.02)
    box(f"foot_{sd}", (s*0.10,-0.045,0.012), (0.104,0.205,0.024), HAIR, 0.006)
    box(f"ball_{sd}", (s*0.10,-0.185,0.04), (0.095,0.08,0.06), BOOTS, 0.02)
    box(f"ball_{sd}", (s*0.10,-0.185,0.012), (0.099,0.08,0.024), HAIR, 0.006)

me = bpy.data.meshes.new("SK_CoopSurvivor")
bm.to_mesh(me)
bm.free()
obj = bpy.data.objects.new("SK_CoopSurvivor", me)
col.objects.link(obj)
for n in bone_names:
    obj.vertex_groups.new(name=n)
for name, rgb in MATS:
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if bpy.app.version < (5, 0, 0):
        m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*rgb, 1)
        bsdf.inputs["Roughness"].default_value = 0.85
    m.diffuse_color = (*rgb, 1)
    me.materials.append(m)
obj.parent = arm
obj.modifiers.new("Armature", 'ARMATURE').object = arm
