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

## 2026-10-19: M0 harness

Runs of `tools/run-test.ps1` (results in `local/test-results/20261019-*`), UE4SS 3.0.1-1181-g83330635.

### Observations
- boot (2 clients): 11/11 PASS. listen: 14/14 PASS. listen `-Mutate skipconnect`: 12/14, `host_two_pcs` and
  `client_connected_garage` FAIL as intended. dump: 19/19 PASS (first dump run 18/19: the usmap file is not
  `Mappings.usmap`, see below; fixed in the runner). No crash folder, no `PT|error` in any run.
- Launching `PenDriverPro\Binaries\Win64\PenDriverPro-Win64-Shipping.exe -NotInstalled` directly works and gives the
  PID we started; every run finished without user input. Logs: `ue4ss\UE4SS.log` (UE4SS working dir = `Win64\ue4ss`),
  `<copy>\PenDriverPro\Saved\Logs\PenDriverPro.log`.
- First launch after setup: main menu (`LoadMap RB_MainMenu`) ~59 s after start, `FShaderPipelineCache completed
  8914 tasks ... 38.60s wall time`. Later launches ~30 s. Engine frame counter stays 0 until then, and UE4SS
  delayed actions (`LoopInGameThreadWithDelay`) only start firing once the main menu is up.
- `GetCurrentLevelName` returns `RB_MainMenu` / `RB_Garage`.
- listen: host `open /Game/Maps/RunProto/RB_Garage?listen` from the menu took 9.6 s (`Took 9.601368 seconds to
  LoadMap`); client `open 127.0.0.1:7777` sent before the host was listening, the pending connection waited
  ~6 s and then succeeded on the first try (`Welcomed by server ... Game: /Game/Systems/GameModes/BP_DrivingGameMode.BP_DrivingGameMode_C`),
  client garage load 3.9 s. The 30 s retry was not needed in this run.
- While the client's connect is pending, the main mod's status prints `net=client map=RB_MainMenu` (world no longer
  standalone before the map change).
- Engine log errors after join: both sides `LogPlayerController: Error: EnableInput can only be specified on a
  PlayerController for itself`; client `ActorTag1 tried to add tag 'WB.Modifiers.Spawning.Vehicles.Car.Stripped.MaxCount'
  ... multiple times` (client-side spawner running); host `AEntitlementSpawner::SpawnActor failed to load class
  /PDFeature_Fig/...BP_Fig_Mission_Chapter08`.
- Every UE4SS.log has `[PS] Failed to find ConsoleManagerSingleton: found 2 unique values` and `Failed to expose size of
  'class RC::Unreal::FObjectPtrProperty'`; nothing broke from it so far.
- Dumpers (Lua globals exist in this build): `GenerateUHTCompatibleHeaders` ~42 s -> `ue4ss\UHTHeaderDump` (30 MB),
  `GenerateLuaTypes` ~7 s -> `ue4ss\Mods\shared\types` (2444 files), `DumpUSMAP` <1 s ->
  `ue4ss\PenDriverPro-4.27.2-0+++UE4+Release-4.27-83330635.usmap` (2 MB), `GenerateSDK` ~5 s -> `ue4ss\CXXHeaderDump`
  (13 MB). Copies of the garage-time dumps are in `local/dumps/`.
- No save file was written in the test copies (`Saved\SaveGames` has only `steam_autocloud.vdf`).

### Derived
- Test checks must look at the current world only: previous-map PlayerControllers linger until GC, so the test mod
  counts controllers whose world is the current world.
- "Connected" must mean `net=client` and the server's map, not `net=client` alone (see the pending state above).

### Unknowns
- Whether the test copies start without the Steam client running (all runs had Steam up).
- Whether the 30 s client retry works when the host takes longer than the 20 s pending timeout (not exercised).
- Whether the `ConsoleManagerSingleton` scan warning matters for console commands we have not used yet.
