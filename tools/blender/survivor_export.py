"""Exports the survivor (mesh + skeleton + every A_Survivor_* action) to FBX for UE 4.27.

Writes <repo>/local/player_model/SK_CoopSurvivor.fbx and a copy of the .blend next to it
(the open Blender session keeps its own file path). Set OUT_DIR before running to change it.
"""
import bpy, os

OUT_DIR = globals().get("OUT_DIR") or os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "local", "player_model")
os.makedirs(OUT_DIR, exist_ok=True)

arm = bpy.data.objects["Armature"]
mesh = bpy.data.objects["SK_CoopSurvivor"]
for b in arm.pose.bones:
    b.rotation_euler = (0, 0, 0)
    b.location = (0, 0, 0)
arm.animation_data.action = None

if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
for o in bpy.context.view_layer.objects:
    o.select_set(False)
arm.select_set(True)
mesh.select_set(True)
bpy.context.view_layer.objects.active = arm

fbx = os.path.join(OUT_DIR, "SK_CoopSurvivor.fbx")
bpy.ops.export_scene.fbx(
    filepath=fbx,
    use_selection=True,
    object_types={'ARMATURE', 'MESH'},
    apply_unit_scale=True,
    apply_scale_options='FBX_SCALE_ALL',   # 1 m in Blender -> 100 uu in UE, armature keeps scale 1
    axis_forward='-Z', axis_up='Y',
    mesh_smooth_type='FACE',
    use_mesh_modifiers=False,
    add_leaf_bones=False,
    primary_bone_axis='Y', secondary_bone_axis='X',
    use_armature_deform_only=False,
    bake_anim=True,
    bake_anim_use_all_bones=True,
    bake_anim_use_nla_strips=False,
    bake_anim_use_all_actions=True,
    bake_anim_force_startend_keying=True,
    bake_anim_step=1.0,
    bake_anim_simplify_factor=0.0,
)
blend = os.path.join(OUT_DIR, "SK_CoopSurvivor.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend, copy=True)
exported = {"fbx": fbx, "blend": blend, "fbx_bytes": os.path.getsize(fbx)}
