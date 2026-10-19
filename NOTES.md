# Pacific Together lab notes

Prior findings by others: `reference/pdcoopnet/LAB-NOTES.md`. Record here only what we checked ourselves.

## 2026-10-19 — Player placeholder model (remote players need a visible body)

Built in Blender 5.2.3 by `tools/blender/survivor_model.py` (mesh + skeleton), `survivor_anims.py`
(loops) and `survivor_export.py` (FBX + .blend copy to `local/player_model/`, git-ignored).
Run them in that order from Blender's Text Editor or through the Blender MCP.
Source scene: `assets/player_model/SK_CoopSurvivor.blend` (also holds a `PreviewRig` camera, not exported).

### Observations (checked)
- Mesh `SK_CoopSurvivor`: 1500 verts, low-poly survivor in a jumpsuit with backpack, 1.78 m, front = Blender -Y.
  Each part is rigidly weighted (1.0) to one bone; no blended weights.
- Skeleton: 23 bones with UE4 Mannequin names and parenting (`root > pelvis > spine_01..03 > neck_01 > head`,
  `clavicle/upperarm/lowerarm/hand_{l,r}`, `thigh/calf/foot/ball_{l,r}`). No fingers, twist or IK bones.
  Armature object is named `Armature` (UE's FBX importer then adds no extra root bone).
- 5 in-place loops at 30 fps, last frame = first:
  | Action | Frames | Authored speed |
  |---|---|---|
  | `A_Survivor_Idle` | 90 | 0 |
  | `A_Survivor_Walk` | 30 | 1.4 m/s |
  | `A_Survivor_Sprint` | 18 | 4.5 m/s |
  | `A_Survivor_CrouchIdle` | 90 | 0 |
  | `A_Survivor_CrouchWalk` | 40 | 1.2 m/s |
- Foot check over every frame: lowest toe/heel point stays between -2 mm and +3 mm of the ground; stance
  ankles move back at speed/fps (walk ~0.047 m/frame after heel rocker, crouch walk 0.040).
- FBX re-imported in a clean background Blender: armature scale 1, one root bone (`root`), 1.78 m rest height,
  6 materials, 5 takes. 20 vertex groups (`root` and both clavicles have no geometry).

### Derived
- In an AnimBP, play rate = actual ground speed / authored speed, so feet don't slide.
- Mesh faces Blender -Y like the UE4 Mannequin export, so in UE it should need the same -90° yaw on the
  mesh component as the stock Mannequin.

### Guesses
- PDCoopNet notes say player animation uses ALS, which is built on the UE4 Mannequin skeleton. Since our
  bone names match, the game's own ALS anims might be retargeted onto this mesh later. Our rest pose
  (arms down) differs from the Mannequin A-pose, so a retarget pose would be needed.

### Unknowns
- UE 4.27 import not tried yet (scale, take names, orientation as UE sees them).
- Whether `PDP_MainCharacter_C` has a third-person mesh slot to put this on, or we attach our own
  SkeletalMeshComponent for remote players only (the local player must not see their own body in FP).
- The game's real walk / sprint / crouch speeds (to match play rates).
- Cooking: needs a UE 4.27 project named `PenDriverPro` to cook a .pak the game will mount.

## 2026-10-19: planning research

### Observations
- Our exe SHA-256 matches the build in `CLAUDE.md` (Steam buildid 21896301).
- `<game dir>/PenDriverPro/Binaries/Win64/steam_api64.dll` (298,856 bytes, read with `grep -a`) exports the flat
  Steam API including `SteamNetworkingMessages_SteamAPI_v002`, `SteamMatchmaking_v009`, `SteamFriends_v017`,
  `ISteamNetworkingMessages_SendMessageToUser/ReceiveMessagesOnChannel/AcceptSessionWithUser`,
  `ISteamMatchmaking_CreateLobby`, `ISteamFriends_SetRichPresence/ActivateGameOverlayInviteDialog`. No `SteamAPI_InitFlat`.
- The shipping exe imports `SteamAPI_Init`, `RestartAppIfNecessary`, `RunCallbacks`, `RegisterCallback`.

### Derived
- The game initialises Steam under appid 1458140 itself; a mod DLL in the process can use its Steam session for P2P
  and lobbies. Whether Steam relay and lobbies work for this appid without developer setup: unknown (spike X6).
