"""Keys the survivor's in-place locomotion loops on the "Armature" made by survivor_model.py.

Procedural: legs use a sagittal two-bone IK with heel and ball rockers so stance feet move
backward at exactly the gait speed (no foot skate when the game moves the capsule at that speed).
Bone rolls are set so local X = world X, which makes rotation about X the fore/aft swing:
negative X swings a downward bone (leg, arm) forward, positive X tips an upward bone (spine) forward.
"""
import bpy
from math import sin, cos, pi, radians as rad, atan2, acos, sqrt

arm = bpy.data.objects["Armature"]
pb = arm.pose.bones
for b in pb:
    b.rotation_mode = 'XYZ'

L1, L2 = 0.42, 0.42           # thigh, calf length
HIP_Z = 0.93                  # hip joint rest height
ANK_Z = 0.09                  # ankle height with the foot flat
BALL = (0.13, 0.025)          # ball joint: forward of ankle, height
HEEL = (0.055, 0.0)           # heel contact: behind ankle, height

def leg_ik(hip_z, fa, za):
    """returns (thigh forward angle, knee bend) for an ankle at (fa forward of hip, za height)"""
    dz = hip_z - za
    d = min(sqrt(fa*fa + dz*dz), L1 + L2 - 1e-4)
    phi = atan2(fa, dz)
    a = acos(max(-1, min(1, (L1*L1 + d*d - L2*L2) / (2*L1*d))))
    knee = acos(max(-1, min(1, (L1*L1 + L2*L2 - d*d) / (2*L1*L2))))
    return phi + a, pi - knee

def pivot_on_ball(fb, q):
    """ankle when the foot pitches toe-down by q (>0) around the ball resting at fb"""
    return fb - BALL[0]*cos(q) + (ANK_Z-BALL[1])*sin(q), BALL[1] + BALL[0]*sin(q) + (ANK_Z-BALL[1])*cos(q)

def pivot_on_heel(fh, q):
    """ankle when the foot pitches toe-up by -q (q<0) around the heel resting at fh"""
    u = -q
    return fh + HEEL[0]*cos(u) - ANK_Z*sin(u), HEEL[0]*sin(u) + ANK_Z*cos(u)

def ease(s):
    return 0.5 - 0.5*cos(pi*s)

def foot_state(p, g):
    """p: leg phase 0..1, 0 = heel strike. returns ankle (forward, z), foot pitch, toe bend"""
    S, d = g["stride"], g["duty"]
    half = S*d/2
    fc = g.get("fcenter", 0.0)
    to, hs, roll_at = g["toe_off"], g["heel"], g.get("roll_at", 0.6)
    if p < d:
        s = p/d
        fa = fc + half - S*d*s            # flat-foot ankle position, moves back with the ground
        if s > roll_at:
            q = to * ((s-roll_at)/(1-roll_at))**2
            fa, za = pivot_on_ball(fa + BALL[0], q)
        elif s < 0.15:
            q = -hs * (1 - s/0.15)**2
            fa, za = pivot_on_heel(fa - HEEL[0], q)
        else:
            q, za = 0.0, ANK_Z
        return fa, za, q, -max(q, 0)
    s = (p-d)/(1-d)
    f0, z0 = pivot_on_ball(fc - half + BALL[0], to)
    f1, z1 = pivot_on_heel(fc + half - HEEL[0], -hs)
    fa = f0 + (f1 - f0) * ease(s)
    za = z0 + (z1 - z0) * s + g["lift"]*sin(pi*s)**1.2
    q = to + (-hs - to) * ease(s)
    return fa, za, q, -to*(1-s)**2

def set_rot(name, x=0.0, y=0.0, z=0.0):
    pb[name].rotation_euler = (x, y, z)

def pose_frame(t, g):
    """t: cycle phase 0..1"""
    w = 2*pi*t
    for b in pb:
        b.rotation_euler = (0,0,0)
        b.location = (0,0,0)
    # pelvis local axes: X = world X, Y = up, Z = forward
    if g["moving"]:
        bob = g["bob"] * cos(2*w - 2*pi*g["duty"]) * g["bob_sign"]
    else:
        bob = g["bob"] * sin(w)
    up = g["hip_drop"] + bob
    pb["pelvis"].location = (g.get("sway", 0)*sin(w), up, 0)
    P = g["lean_pelvis"]
    yaw = g["yaw"]*cos(w)
    roll = g["roll"]*sin(w)
    set_rot("pelvis", P, -yaw, roll)
    lean = g["lean"]
    breath = g.get("breath", 0)*sin(w)
    set_rot("spine_01", lean*0.3, yaw*0.4, -roll*0.6)
    set_rot("spine_02", lean*0.35 + breath*0.5, yaw*0.5, -roll*0.3)
    set_rot("spine_03", lean*0.35 + breath, yaw*0.9, 0)
    S = P + lean
    set_rot("neck_01", -S*0.45 - breath*0.5, -yaw*0.8, 0)
    set_rot("head", -S*0.4 + g.get("look", 0), -yaw*0.8, 0)
    hip_z = HIP_Z + up
    for sd, off in (("l", 0.0), ("r", 0.5)):
        ph = (t + off) % 1.0
        if g["moving"]:
            fa, za, q, toe = foot_state(ph, g)
        else:
            fa, za, q, toe = g["stand_f"][sd], ANK_Z, 0.0, 0.0
        A, bend = leg_ik(hip_z, fa, za)
        set_rot(f"thigh_{sd}", -A - P)
        set_rot(f"calf_{sd}", bend)
        set_rot(f"foot_{sd}", q + A - bend)
        set_rot(f"ball_{sd}", toe)
        # arm swings opposite to the same-side leg
        sgn = 1 if sd == "l" else -1
        ph_arm = cos(w + pi*(sd == "r") - g.get("arm_lag", 0.3))
        if g["moving"]:
            swing = g["arm_base"] - g["arm"]*ph_arm
            flex = g["elbow"] + g["elbow_amp"]*max(0, -ph_arm)
        else:
            swing = g["arm_base"] + g.get("arm_idle", 0)*sin(w + off*pi)
            flex = g["elbow"]
        set_rot(f"upperarm_{sd}", -swing, 0, sgn*rad(-3))
        set_rot(f"lowerarm_{sd}", -flex)
        set_rot(f"hand_{sd}", rad(5))

GAITS = {
    "A_Survivor_Idle": dict(frames=90, moving=False, speed=0.0, bob=0.004, bob_sign=1, hip_drop=-0.012,
        lean_pelvis=rad(2), lean=rad(1), yaw=rad(1.5), roll=rad(1.2), sway=0.006, breath=rad(1.5),
        stand_f={"l": 0.02, "r": -0.03}, arm_base=rad(2), arm=0, arm_idle=rad(1.5), elbow=rad(8), elbow_amp=0),
    "A_Survivor_Walk": dict(frames=30, moving=True, speed=1.4, duty=0.6, lift=0.10, toe_off=rad(35), heel=rad(18),
        roll_at=0.5, fcenter=-0.02, bob=0.015, bob_sign=1, hip_drop=-0.04, lean_pelvis=rad(3), lean=rad(3),
        yaw=rad(5), roll=rad(3), arm_base=rad(2), arm=rad(20), elbow=rad(12), elbow_amp=rad(18)),
    "A_Survivor_Sprint": dict(frames=18, moving=True, speed=4.5, duty=0.30, lift=0.26, toe_off=rad(35), heel=rad(5),
        fcenter=0.04, bob=0.03, bob_sign=-1, hip_drop=-0.07, lean_pelvis=rad(7), lean=rad(9), yaw=rad(8),
        roll=rad(3), arm_base=rad(8), arm=rad(48), elbow=rad(80), elbow_amp=rad(15), arm_lag=0.2),
    "A_Survivor_CrouchIdle": dict(frames=90, moving=False, speed=0.0, bob=0.004, bob_sign=1, hip_drop=-0.33,
        lean_pelvis=rad(18), lean=rad(16), yaw=rad(1), roll=rad(0.8), sway=0.004, breath=rad(1.5), look=rad(4),
        stand_f={"l": 0.06, "r": -0.06}, arm_base=rad(18), arm=0, arm_idle=rad(1.5), elbow=rad(45), elbow_amp=0),
    "A_Survivor_CrouchWalk": dict(frames=40, moving=True, speed=1.2, duty=0.66, lift=0.09, toe_off=rad(22),
        heel=rad(6), fcenter=0.02, bob=0.012, bob_sign=1, hip_drop=-0.31, lean_pelvis=rad(18), lean=rad(16),
        yaw=rad(4), roll=rad(2), look=rad(4), arm_base=rad(18), arm=rad(12), elbow=rad(45), elbow_amp=rad(10)),
}

fps = bpy.context.scene.render.fps
arm.animation_data_create()
summary = {}
for name, g in GAITS.items():
    N = g["frames"]
    if g["moving"]:
        g["stride"] = g["speed"] * N / fps
    old = bpy.data.actions.get(name)
    if old:
        bpy.data.actions.remove(old)
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    arm.animation_data.action = act
    for f in range(N + 1):            # last frame repeats the first so the loop closes
        pose_frame((f % N) / N, g)
        for b in pb:
            b.keyframe_insert("rotation_euler", frame=f, group=b.name)
            if b.name == "pelvis":
                b.keyframe_insert("location", frame=f, group=b.name)
    act.use_frame_range = True
    act.frame_range = (0, N)
    act.use_cyclic = True
    summary[name] = {"frames": N, "fps": fps, "speed_m_s": g["speed"], "stride_m": round(g.get("stride", 0), 3)}
for b in pb:
    b.rotation_euler = (0,0,0)
    b.location = (0,0,0)
