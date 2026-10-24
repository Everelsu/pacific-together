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

## 2026-10-19: spike X1 listen server through the game's own travel

Scenario `travel` (`-Mutate norehost`). Runs: `local/test-results/20261019-164906-travel` (22/23, the one FAIL is the
question below; no native `main.dll` yet), `20261019-170156-travel-norehost` (19/23, `main.dll` present).

### Observations
- `RegisterLoadMapPreHook`/`PostHook` fire for every `UEngine::LoadMap`: boot (`/Temp/Untitled` -> menu), console
  `open`, the client's join (pre-hook `pending=PendingNetGame_...` with its `IpNetDriver`), the game's native
  `UserNewGame(5, STORY)` and `QuitToMenu` (pending=none), `servertravel`, and the client's drop back to the menu.
  Pre-hook world param = the old world, post-hook = the new one. Error string always empty.
- The FURL reaches Lua as an opaque `FURLUserdata`: `url.Map/Host/Port/Op/Portal/Protocol` all nil, no `get()`
  (`PT|info furl ...`). The UE4SS source (`LuaFURL.cpp`: "todo: setup member functions"; `LuaMod.cpp` callbacks take
  `Unreal::FURL URL` by value) shows it has no members and is a copy. **Lua cannot read the FURL or add `listen`.**
- Host: `UserNewGame(5, STORY)` -> `Browse: /Game/Maps/Narrative/Narrative_Forest_OlympicOpening_Sentry_01/...` (no
  `?listen`) -> `World NetDriver shutdown`. Post-hook: `standalone=true driver=none`. Check
  `host_listen_after_native_travel` FAIL. It also wrote `Saved/SaveGames/odsave5.sav` in the host copy.
- Client: `Host closed the connection.` -> `Browse: RB_MainMenu?closed`, back in the menu ~1 s after the host left.
- Re-host `servertravel <map>?listen` (second load): `Took 10.3 s` (intro map; the native load was 13.0 s). Client
  rejoin with `open` every 30 s: the first try timed out (`Threshold: 20.00`, host still loading), the second joined;
  41 s from leaving to back in. Host `QuitToMenu` with the client connected (spectator only, no second character):
  no crash, client dropped again, host in the menu after 4 s.
- norehost mutation: `host_listen_after_rehost`, `host_two_pcs_after_rehost`, `client_rejoined_new_map` FAIL.
- Loads (engine log, warm test copy): garage 15.8 s first run, ~8 s later; intro map 13.0 s; menu 1-2 s.

### Derived
- The hook is the right place (it fires for native travel and tells native travel from a client join by
  `pending`), but adding `listen` needs C++: detour `UEngine::LoadMap` in the native DLL and append `listen` to the
  FURL's `Op` in place (MSVC x64 passes the by-value FURL as a pointer to the caller's copy) when the old world was
  listening and `PendingGame` is null. The UE4SS C++ callback also gets a copy, so it has to be our own detour.
- Until then the Lua fallback is the reference's double load (`servertravel <map>?listen` after the native load)
  plus a client rejoin loop: works, costs ~10 s per map change plus a 20-40 s rejoin.

### Unknowns
- Whether an in-place FURL edit in a LoadMap detour makes `LoadMap` listen without side effects (untested, no build).
- Whether a pre-hook returning a bool skips the original LoadMap (not tried).
- `client_menu_after_host_quit` passes trivially when the client is already in the menu (weak check).

Verdict: change the plan. S6 "without a second load" is not reachable from Lua; M2 needs a native `LoadMap` detour
that adds `listen` (keep the `servertravel` re-host + rejoin as fallback until the detour passes `travel`). A
non-seamless map change always drops the client, so S5/S6 also need an automatic client rejoin.

## 2026-10-19: spike X11 connect timeout on long loads

Scenario `zonejoin`: the client sends one `open` as soon as its menu is up; the host waits 45 s, then opens
`Wilderness_Forest_01?listen`; no retry. Runs: `20261019-170601-zonejoin-noconfig` (host waited 25 s),
`20261019-170906-zonejoin` (ini, 14/14), `20261019-171355-zonejoin-noconfig` (12/14, `client_connected_zone`
FAIL), `20261019-171617-zonejoin-cdo` (14/14). `main.dll` present in all.

### Observations
- IpNetDriver CDO and the live pending driver: `InitialConnectTimeout=60 ConnectionTimeout=60`, `bNoTimeouts=false`,
  yet the pending connect dies at `Elapsed: 20.01 ... Threshold: 20.00`. `ResolutionConnectionTimeout` is 20 on the
  CDO (`PT|info timeouts cdo{init=60 conn=60 res=20}`).
- `[/Script/OnlineSubsystemUtils.IpNetDriver] ResolutionConnectionTimeout=120`, appended by the runner to
  `client2\PenDriverPro\Saved\Config\WindowsNoEditor\Engine.ini` (the `-NotInstalled` user config) and restored
  afterwards: the game reads it (client CDO `res=120`, host still 20); client pending 42 s, then
  `Welcomed by server`, no timeout.
- Same result with no ini and the CDO set from Lua before `open`
  (`Default__IpNetDriver.ResolutionConnectionTimeout = 120`): joined 41 s after open.
- Zone load with a warm cache: 3.5-3.8 s; the reference's 14-19 s were cold loads.

### Derived
- The 20 s threshold is the IpNetDriver's address-resolution timeout (applies while the client has had no reply),
  not `InitialConnectTimeout`; this is why the reference's edits did nothing. One Lua line on the CDO fixes it, no
  config file needed (`-ini:` override not tried).

### Unknowns
- The right value for slow disks; what the resolution timeout does once Steam P2P replaces plain UDP (M6).

Verdict: keep the plan, X11 passes. M2: set `ResolutionConnectionTimeout` (~120) on the IpNetDriver CDO at mod start
on the guest, then one `open` per join attempt plus rejoin-on-drop instead of blind 30 s retries.

## 2026-10-19: spike X10 block the guest's saves

Scenario `guestsave` (`-Mutate noblock`): the client first plays its own slot (`UserNewGame(6, STORY)`, intro map,
`QuitToMenu`), joins the host's garage, follows a host `servertravel RB_Garage?listen`, then runs the game's
autosave path (`BP_AutoSaveDirector_C:FlagAutosave` + `CheckFlagAndTrigger`) and a direct
`SaveGame(GetCurrentSlot(), "", AUTOSAVE)`. The runner snapshots `Saved\SaveGames` + `Saved\Config` (name, size,
time, SHA-256) on each `PT|snap` and at the end. Runs: `20261019-172056-guestsave-noblock` (host crash, below),
`20261019-172646-guestsave-noblock`, `20261019-173138-guestsave`, `20261019-173646-guestsave` (23/23),
`20261019-174119-guestsave-noblock` (20/23). `main.dll` present in all.

### Observations
- Save functions (dumps, `BaseSaveGameManager`): `SaveGame(int32 Slot, FString LevelOverride, ESaveType)`
  (`RINSE/MANUAL/AUTOSAVE`), `SaveCheckpoint`, `MakeBookmark`, `WriteUserSettings`, `WriteGameplaySettingsToSlot`,
  `Rinse`, `DeleteGame`; Blueprint gates `BP_AutoSaveDirector_C:CanAutoSave(out bool)`, `TriggerAutosave`,
  `K2_PostLevelChange`, `BP_SaveGameManager_C:CanUserSaveGame(out bool)`. Engine `GameplayStatics:SaveGameToSlot` /
  `AsyncSaveGameToSlot` were hooked and never fired: the game writes through its own code.
- Without blocking: joining, ~60 s in the garage and a map change wrote **no save** by themselves (the client's
  `CanAutoSave` turned false 5 s after reaching the menu). After `QuitToMenu` the manager reports `slot=0`. The forced
  autosave path called `SaveGame(slot=0, '', 2)` and wrote `SaveGames\odsave_scratch.sav` (141 KB, log
  `SAVE V4: Garage!!`), i.e. the host's world into the guest's own scratch save; the direct call wrote it again.
- `RegisterHook` on the native `SaveGame` fires for the game's own Blueprint->native call as well as for Lua calls.
  The pre-hook sets `Slot` to -1: nothing written in either case, `SaveGame -> false`, no error. Blocking run 23/23;
  the noblock mutation fails the three checks after the autosave step.
- `Config\WindowsNoEditor\GameUserSettings.ini` is rewritten on every map load on the client (new time, same SHA-256,
  981 bytes), with or without blocking. The runner check compares name + size + hash and lists such rewrites.
- `UserNewGame` itself writes `odsave6.sav` (730 bytes): `odsaveN` = slot N, slot 0 = `odsave_scratch`.
  The `odsave_scratch.sav` from the noblock runs stays in `client2` (later noblock runs overwrite it).
- Host crash in `20261019-172056-guestsave-noblock`: `EXCEPTION_ACCESS_VIOLATION reading address 0x178` in the game
  exe (`+3160a56`, `+318205a`, `+2fc4f80`, no symbols), ~2 min after `servertravel RB_Garage?listen` with the client
  connected and the host idle; last host line `Viewport MouseLockMode Changed, LockOnCapture -> LockInFullscreen`.
  The client's hooks were only logging (that run still logged `CanAutoSave` every frame). Not reproduced in the next
  four guestsave runs with the same timing.

### Derived
- A Lua pre-hook on `BaseSaveGameManager:SaveGame` redirecting `Slot` to -1 blocks the game's autosave and manual
  save on the guest; no C++ needed for that path. Overriding `CanAutoSave`/`CanUserSaveGame` alone is not enough
  (`CheckFlagAndTrigger` saved while `CanAutoSave` was false).
- Write paths not covered by that hook: `WriteUserSettings`, `WriteGameplaySettingsToSlot`, `Rinse`, `DeleteGame`,
  `SaveCheckpoint`, `MakeBookmark` (hooked, never fired here; pre-hooks cannot cancel them) and the engine's
  `GameUserSettings.ini` rewrite (same bytes today; would persist any setting the mod changes, e.g. G5).

### Unknowns
- Whether other code paths save through direct C++ calls that bypass the UFunction (none seen).
- Cause of the 0x178 host crash.

Verdict: change the plan slightly. M2 S7: a guest-side Lua pre-hook on `SaveGame` (slot -> -1) while in a session,
plus guards for the other writers; for a hard guarantee a native `IPlatformFile` wrapper that refuses writes under
`Saved/SaveGames` during a session. Never change guest settings in place (G5). Keep `guestsave` as the S7 test.

## 2026-10-19: spike X3 client-local actor survey

Scenarios `travel` (garage) and `zonejoin` (zone) log every actor grouped by class/Role/bReplicates/loaded/owner;
the runner writes `actors-<tag>.csv`. Runs: `20261019-164906-travel` (garage), `20261019-170906-zonejoin` (zone).
Table and classification: `docs/research/client-actor-survey.md`.

### Observations
- Garage: host 554 actors, client 472. The client has 2 `BP_PlayerCarNew_C` (role 1 + a local role 3) and every car
  part actor twice (e.g. `BP_CarPart_Interactive_C` 53 / 106), all role 3 (not replicated). Garage stations
  (`BP_Garage_*`), storage and quest actors `BP_Fig_Mission_Chapter*` (via `AEntitlementSpawner`, on both sides)
  exist as separate local actors on each side. Roadside spawners and template cars are on the host only.
- Zone: host 1480, client 508. Lootables (`BP_Lootable_Backpack_Civilian_C`, `BP_Lootable_CoolingBox_01_C`),
  `BP_SpawnPoint_C` and destructible props are local on both sides; `BP_ItemSpawner_C` on the client only; the run
  spawn pass (`LogSpawnExecutor`: 63 lines on the host, 0 on the client) and its products (cars, gas barrels,
  lockboxes, radiation hazards, exit portals) on the host only. The host's character and car were not on the client.

### Derived
- Duplicates to gate: the client's local car and its part actors (W2), garage stations and storage (G1/G2), quest
  actors (G3), lootables and item spawners in zones (W1/W2). The run spawn pass is already host-only.

### Unknowns
- The client spectator is elsewhere than the host, so streaming and relevancy differ; redo with the guest's
  character next to the host after M2 spawn.

Verdict: keep the plan (W2 is real and wider than the car). M2 has nothing to gate; M3/M4 must gate the local car
with its part actors, and stable ids (X2) must cover lootables and garage storage that exist on both sides.

## 2026-10-19: spike X1b keep the listen server through native travel (C++)

Scenario `travel` (`-Mutate nokeep|norehost|follow`). Runs: `20261019-175958-travel` (22/23, `PTNative_*` not yet
visible to the test mod), `20261019-180355-travel` (23/23), `20261019-180625-travel-nokeep` (22/23),
`20261019-181441-travel-follow` (21/23), `20261019-185029-travel` (23/23, `-Port 7791`). Native layer 0.0.2.

### Observations
- UE4SS has no mutable-FURL LoadMap hook: the C++ `RegisterLoadMapPreCallback` (`deps/first/Unreal/include/Unreal/Hooks/Hooks.hpp`)
  takes `FURL URL` by value, and the detour (`Hooks/Internal/DetourInstance.hpp`, `Invoke(InArgs... Args)`) copies the
  arguments again for the trampoline and for each callback.
- Our DLL swaps the live `DrivingGameEngine`'s vtable slot for `LoadMap` (offset from `UEngine::VTableLayoutMap`) on the
  first UE4SS LoadMap pre-callback: `PT|native loadmap patched slot=0x470 original=0x7ff6729c66c0 ue4ss=0x7ff6729c66c0`,
  i.e. the slot held the function UE4SS detours; the UE4SS Lua LoadMap hooks kept firing behind ours in every run.
  Our function takes the FURL as a pointer (MSVC x64 passes a by-value class as a pointer to the caller's copy, the
  callee destroys it) and appends `listen` to `Op` when keep-listen is on, `PendingGame` is null, the old world's
  NetDriver has no ServerConnection, `listen` is not already there and the map name has no `MainMenu`.
- `UserNewGame(5, STORY)` with the guest connected: `PT|native keeplisten map=/Game/Maps/Narrative/... listening=true
  had=false added=true`; engine log `Browse: /Game/Maps/Narrative/...` (no `?listen`), old `World NetDriver shutdown`,
  then `IpNetDriver listening on port 7777` 1.9 s into the 4.5 s load. `host_listen_after_native_travel` PASS with no
  `servertravel`. `QuitToMenu`: `map=/Game/Maps/RunProto/RB_MainMenu listening=true added=false`, host standalone in
  the menu (`host_menu_after_quit` now also checks standalone). With `-port=7791` the new driver listens on 7791 again.
- The guest still drops: `Host closed the connection.` -> `Browse: RB_MainMenu?closed`, menu ~1 s later. With
  `ResolutionConnectionTimeout=120` on its IpNetDriver CDO and one `open` from the menu it joined on the first try:
  host `Browse` 18:03:06.2 -> guest on the new map 18:03:14.3 (8 s; final run 8 s too).
- `nokeep`: only `host_listen_after_native_travel` FAILs; the `servertravel <map>?listen` fallback re-hosts and the
  guest is back 21 s after leaving.
- `follow`: the host called `ClientTravel("127.0.0.1:7777", TRAVEL_Absolute)` on the remote PC in the Lua LoadMap
  pre-hook (inside LoadMap, before the old driver shuts down) and the guest never ran `open`. The guest's log has only
  `Host closed the connection` -> `Browse: RB_MainMenu?closed`; it stayed in the menu (`client_rejoined_new_map` FAIL
  after 400 s). Native travel itself sends no travel RPC to clients.
- Another lane ran its own test games (`C:\PTLanes\probe`) at the same time on port 7777; in `20261019-182606-body`
  its client joined my host (two different `Login request` names). Runs after that use the runner's `-Port 7791`.

### Derived
- Keep-listen from C++ works and needs no second load: ~10 s saved per map change, and the guest is back in ~8 s
  instead of 21-41 s. Lua turns it on per session with `PTNative_SetKeepListen(true)`.
- The guest cannot be made to follow a native (non-seamless) map change: the connection closes inside the same
  LoadMap call as anything the host could send. Guest-side auto-rejoin is the way.

### Unknowns
- The run travel (gateway -> zone -> garage) and run failure were not exercised; only `UserNewGame` and `QuitToMenu`.
  The "no `MainMenu` in the map name" rule assumes no other non-gameplay map.
- Seamless travel (would keep the connection) not tried.

Verdict: keep the plan, X1b passes: M2 ships the C++ keep-listen (`PTNative_SetKeepListen`) instead of the
`servertravel` re-host, plus guest auto-rejoin on "Host closed the connection" (one `open`, ~8 s). Following via
`ClientTravel` does not work.

## 2026-10-19: spike X13 remote player body

Scenario `body` (`-Mutate nospawn`): the host spawns a `PDP_MainCharacter_C` for the guest's PC and possesses it
(reference method), teleports it 300 uu in front of its camera; both sides log every mesh component of both
characters and take `HighResShot 1` screenshots while the guest walks, crouches and sprints across the host's view,
then the host walks and crouches; then the other character's materials are swapped and the phases repeat. Runs, all
20/20: `20261019-181704-body`, `-182012-body`, `-182922-body`, `-183310-body`, `20261019-183958-body` (final
choreography); `20261019-182606-body` 17/20 (another lane's client took the guest slot, see X1b);
`20261019-184606-body-nospawn` 13/20 as intended. Screenshots: `<role>-HighresScreenshotNNNNN.png` in the run folder.

### Observations
- Spawn + Possess as in the reference: `possessed=true`, the guest's pawn is a `PDP_MainCharacter_C` with Role 2 on
  the guest within ~12 s; the host's character is Role 1 there. The manager's `CharacterActor` was put back on the host's.
- Each character has exactly one mesh component, `CharacterMesh0` (the ACharacter mesh): `SkeletalMesh
  /Game/AdvancedLocomotionV3/Characters/Mannequin/Mannequin`, AnimBP `Mannequin_AnimBP_C`, visible=true,
  bHiddenInGame/bOwnerNoSee/bOnlyOwnerSee=false, head bone not hidden, bRenderInMainPass=true, CastShadow=false,
  scale 1, both material slots `/Game/Characters/Player/Art/Materials/M_PlayerCharacter_Invist`. Same for own and
  remote characters, on both sides. No other mesh on or attached to the character (garage, empty hands).
- With the other character straight ahead at 298-306 uu (camera yaw vs direction to it within 1°, view target = own
  character): nothing visible and no shadow on either side (e.g. `20261019-183958-body/host-HighresScreenshot00041`,
  `client-...00035`; same in the four earlier runs).
- Visibility flags were already on, so flipping them changed nothing. Setting every material of the other character
  (locally, that side only) to `/Engine/EngineMaterials/WorldGridMaterial`: a grey ALS mannequin appears and animates.
  Host sees the guest idle, strafe-walk, crouch-walk and sprint (`host-...00046`-`00049`); guest sees the host idle,
  walk and crouch-walk (`client-...00041`-`00046`).
- Movement numbers match on both sides: walk 375, crouch 150 with `bIsCrouched=true`, guest sprint 625 (host sees
  `MaxWalkSpeed=625` for the guest although the guest's `ShouldSprint` stays false there). Crouch used
  `ACharacter:Crouch/UnCrouch`, sprint the game's `Command Sprint`.

### Derived
- The game's own character already gives remote players a full body with replicated movement and ALS animation
  (walk, crouch, sprint); it is only drawn with an invisible material, because the game is first person. Remote
  bodies need a visible material on the other player's `CharacterMesh0`, applied locally on each side, never on
  one's own character.
- Djecka's placeholder model is not needed for v1.0 to function; it is cosmetic (the visible mannequin already reads
  as a body). Its UE4 Mannequin bone names would let it follow `CharacterMesh0` as a slave mesh later (needs a cooked pak).

### Unknowns
- Which cooked game materials work on a skeletal mesh and look like a survivor; only WorldGridMaterial was tried.
- Whether the game changes the body material or adds an arms mesh in the car, when carrying items or in cutscenes.
- How the guest's sprint speed reaches the server; remote anim tick at distance (`VisibilityBasedAnimTickOption`).

Verdict: change the plan slightly: P1's body needs no new mesh, only a visible material on the other player's
character (M2: apply WorldGridMaterial or a better cooked material to remote `CharacterMesh0` on both sides). Djecka's
model becomes optional polish.

## 2026-10-19: parallel lanes

Seven lanes (worktrees `lane/*`, run `wf_27e42d54-d99`, continued 2026-10-20) ran M1 spikes and the M2 session core in
parallel and were merged into main on 2026-10-20. Results, with observations, derived facts, guesses and unknowns, are
in the lane docs; verdicts are in `docs/PLAN.md` (M1 results table, M2 progress).

- A transport: `docs/spikes/X5.md` (UDP tunnel), `docs/spikes/X6.md` (Steam lobby, rich presence, messages; one account).
- B world: `docs/spikes/X2.md` (stable ids, runtime replication, loot call paths).
- C interaction: `docs/spikes/X4.md` (guest interaction), `docs/spikes/X12.md` (backpack record).
- D car: `docs/spikes/X7.md` (car interpolation), `docs/spikes/X8.md` (passenger seat, ARC move).
- E research: `docs/spikes/E.md`, `docs/research/{tourists,garage-stations,arc-device,arc-marker,crash-reports}.md`.
- F1 session: `docs/spikes/M2-session.md`. F2 safety: `docs/spikes/M2-safety.md`.

Merge regression (main test pair, port 7777): after the merge the shipping session mod gives every guest that sends the
hello a character, so lane scenarios that spawned their own guest character (`nametag`, `interact`/`backpack` via
`guestchar.lua`, `carlib.lua`, `tourist`) now use the shipping one; `crashcfg` now expects the empty DSN that `safety.lua`
sets (Q9). Derived from the code, not run: the native `PTNative_NetStats` counters (game MCP) and the X5 tunnel both swap the exe's `sendto`/`recvfrom`
import slots by value, so whichever runs second in a process finds no slot (tunnel: `PT|error`, net_stats: 0 slots).

Regression after the merge and these fixes, native 0.0.3 built from main (`local/test-results/20261020-1533*` to
`-170232*`): boot, listen, travel, guestsave, zonejoin, body, fixtureload, listen through the tunnel, session,
sessionmismatch, sessionrejoin, sessionsolo, sessionlook, safety, safety_crash, safety_solo, nametag, x2garage, x2zone,
interact, backpack, interactzone, carseat, carride (with car-error), tourist, stations, arc, crashcfg: all checks PASS.
Not run: steamsolo (puts a lobby on the owner's real Steam account), steamhost/steamguest (two accounts), probes and
diagnostics (dump, repl, invprobe, safety_probe, sessionchurn, sessionmats, sessionprobe), and no mutations.

## 2026-10-20: M2 gaps (S5, S6, S7, Q9)

Lane pair `C:\PTLanes\m2gaps`, port 7811, results in the lane worktree's `local/test-results/20261020-17*` to `-19*`.

Observations
- Killed guest process (`sessionabrupt`, `sessionabruptzone`): the host stays up, its remote controller and the guest's character
  are gone within seconds (`chars` 2 -> 1 in the host log), a relaunched guest joins again. The same after a polite leave. Lane C's
  "a leaving guest's character stays in the host's world" does not reproduce with the shipping guest spawn.
- `BP_ProgressionManager:TravelToGarage(ReturnState, ..., SaveAndQuit, ...)`: return states 2 and 3 jump past the SaveAndQuit
  branch (bytecode, `local/atlas/bp/BP_ProgressionManager.txt`), so `TravelToGarage(3, .., true)` is a plain garage return.
  The pause menu's save and quit is `SaveGame(CurrentSaveSlot, "", 1)` then `QuitToMenu(self)` (`PDP_PauseMenu`).
- `BaseSaveGameManager:QuitToMenu` takes a world-context parameter; calling it with none is a Lua error.
- Gateway, death return, run failure and save-and-quit mid-run + resume all keep the session: the host listens on every new map
  and the guest is back by itself (`sessiontravel` 55/55). With keep-listen off (mutation `nokeep`) the host is standalone after the
  first change (29/52).

Unknowns
- Story and garage-station save writers (S7), the moving-car disconnect (S5).
- Q9: the firewalled crash run (`tools/q9-firewall.ps1`) needs an elevated shell; not run yet.

## 2026-10-20: first playtest fixes (car entry, rejoin without the menu)

The owner and Djecka played the dev preview: the guest joined and walked around, but the host getting into the car pulled the
guest's character into the car and dropped it through the map, and the host's next run start crashed (access violation reading
0x178 under a Blueprint call, right after `ServerMove: TimeStamp expired` warnings for the guest's character).

Observations
- Reproduced with the game MCP (`enter_car`): on the host the guest's character was attached to `BP_PlayerCarNew_C` (and stayed
  attached after the host left the car); on the guest its own character was attached and falling (movement mode 3).
- Cause: every `PDP_MainCharacter` binds its own `CommandEnterCar` / `Exit Car` to the process's `BP_MainCharacterManager`
  `CommandEnterCar` / `CommandExitCar` delegates in its event graph (also storm and feedback manager events), so a broadcast reaches
  every character in the process. The handler attaches `self` to the manager's car (`K2_AttachToActor` in the ubergraph).
- Fix: native `mute.cpp` (`PTNative_Mute(address, names)`) drops those UFunction calls in a ProcessEvent pre-callback
  (`PreventOriginalFunctionCall`) for the other player's character on each side; `session.lua` mutes when it marks the other body.
  `carenter` 21/21 (host enters the car through `StartEntry`, guest stays out, run start with the guest connected, guest back in
  the zone), mutation `nomute` fails. The run start no longer crashes; the crash was not reproduced separately (guess: it needed the
  fallen guest character).
- `/Engine/Maps/Entry` is not cooked (opening it lands in `RB_MainMenu`); `GameMapsSettings.TransitionMap` is None.
- Rejoin without the menu: native `Browse` vtable swap (slot 0x460). While `PTNative_SetRejoin(host)` is set, the engine's
  `?closed` browse (connection dropped) goes to the host instead of the default map; the guest waits on the old map until the host
  listens again. A failed reconnect browses without `closed` and ends in the menu. `sessiontravel` 54/54 with a check that the guest
  never loads the menu; `session` 40/40, `sessionrejoin` 36/36 updated the same way.

Unknowns
- The guest's view while it waits on the old map (a frozen last frame or a loading screen); not seen with a renderer.

## 2026-10-20: hot reload probe, engine source

Observations
- UE 4.27.2 engine source (runtime + OnlineSubsystemSteam/Utils) is in `local/ue` (shallow sparse clone of tag
  `4.27.2-release`, commit d94b38ae, 195 MB, git-ignored). Read it instead of probing engine behaviour in a game.
- Lua `RestartMod("PacificTogether")` (UE4SS `LuaMod.cpp:5591`) reinstalls both the Lua mod and our C++ mod `main.dll`,
  because both carry the folder's name (`UE4SSProgram.cpp:2031` queues `LuaMod` and `CppMod`). Log shows
  `Stopping C++ mod 'PacificTogether' for uninstall`, `PT|native loaded`, `guard imports patched=5/5` per call.
- Three calls in a row in a headless garage host: the first two reloads come back (`PT|boot` each), the game dies right after
  the third (`local/test-results/20261020-230953-repl`, runner: crash, no CrashContext).
- Lua uninstall unregisters the mod's hooks and callbacks (`LuaMod::uninstall`, `LuaMod.cpp:6129`).
- A Lua-only reinstall exists (`queue_reinstall_lua_mod_by_name`, used by the UE4SS GUI) but is not exported
  (no `RC_UE4SS_API`), so neither Lua nor our DLL can call it.

- Split: `main.dll` now lives in its own mod `Mods/PacificTogetherNative/dlls/`, so `RestartMod("PacificTogether")` only
  restarts the Lua mod (no `Stopping C++ mod` line). Plain Lua-only RestartMod with a guest connected still killed the host on
  the first reload (`20261020-232445-reload`, log ends after `Stopping mod 'PacificTogether' for uninstall`): UE4SS
  uninstalls on its event loop thread while the game thread keeps firing the mod's hooks.
- Fix (native 0.0.5, test runs only): `PTNative_ReloadLua()` before `RestartMod` queues an event ahead of the reinstall that
  waits until the game thread sits in an engine-tick pre-callback; that callback waits until `on_lua_start` sees the new
  `PacificTogether` Lua mod (timeouts 5 s / 10 s). Scenario `reload` 28/28 (`20261020-232939-reload`): 5 reloads per side
  with a guest in the garage, 5 `reload resumed started=true` per side, then native travel and the guest's rejoin.
  Repeats: with the wait 3/3 (`232939`, `233701`, `234025`); mutation `nowait` (plain RestartMod) 3/3 too (`232445`'s crash
  was 1 of 4 plain runs). Mutation `noreload` fails 26/28 as it should.

Guesses
- The wait fixes the crash: unproven (1 crash in 4 plain runs, 0 in 3 with the wait). The race is visible in UE4SS's code
  (`LuaMod::uninstall` runs off the game thread, hooks fire on it), so the wait stays; it is test-only.
- The first solo crash (3 reloads with `main.dll` reinstalled each time) was the same race, or the DLL reload, or both.

Unknowns
- Lua state that the old mod held (session flags, delayed callbacks already queued) starts fresh; a reload mid-travel is untested.

Observation (setup bug, fixed): `tools/setup-test.ps1` robocopied the real install's `Binaries/Win64` including `ue4ss/`.
Once the owner had a dev preview installed, the copy went through the test copies' `Mods/PacificTogether` junction and
overwrote the repo's `mod/PacificTogether` with the installed 0.0.2 build (Lua files with their 19:52/20:12 mtimes,
`dlls/main.dll`, `version.txt`), and replaced the test copies' UE4SS settings with the preview's (consoles off). The real
install was only read. Fix: both copies skip `ue4ss/` and `dwmapi.dll`; setup expands the pinned UE4SS zip itself.
Pairs set up while a preview was installed: re-expand the UE4SS zip into each copy's `Binaries/Win64` and check
`git status` in the repo the junctions point at.

## 2026-10-20: message channel (intents and state)

Observations
- UE 4.27.2 source (`local/ue`): `APlayerController::ServerExecRPC(FString)` is `Reliable, Server, WithValidation`, and in
  shipping its body is empty (`PlayerController.cpp:1739`, `#if !UE_BUILD_SHIPPING`). `ClientMessage(FString, FName, float)`
  is `Reliable, Client` and only reaches `ClientTeamMessage`, which prints to the viewport console
  (`PlayerController.cpp:1384`, `1399`). No Blueprint in the game references either (`local/atlas`).
- Native `msg.cpp`: guest to host on `ServerExecRPC`, host to guest on `ClientMessage`, chunks of 1000 bytes
  `PT1|<kind>|<m|e>|<bytes>` caught in a ProcessEvent pre-callback (original call dropped), reassembled per controller
  and kind, kept in an inbox that each Lua mod polls by kind prefix. Max message 32 KB (33 chunks, far below UE's 256
  outstanding reliable bunches).
- Scenario `channel` 21/21 (`20261020-234822-channel`): 50 ordered messages and a 20 KB message with every byte value
  but NUL, each way, sender = the guest's controller, 70 chunks each way, dropped 0; 40 KB refused. Mutation `nocapture`
  16/21.
- Upstream PDCoopNet v0.6 (BroZYTnikkkk/pacific-drive-coop @23d6957) carries its items, trunk and car sync in PlayerState
  names polled every 200 ms (one message in flight, 8 KB cap; 60 KB never arrived). Facts mined from it are in the
  session's review; the car part functions (`Set Fuel`, `GetFuelStatus`, `Set Battery`, `GetBatteryStatus`) match our atlas.

Unknowns
- Behaviour under packet loss and over the Steam tunnel (reliable RPCs should resend; not run).

## 2026-10-21: playable prototype lanes (car, items, world, player)

Four Sonnet worker lanes, each in its own worktree, pair and port, headless, merged into main in this order: player, world,
car, items. Details, gaps and result folders are in each lane's spike doc: `docs/spikes/M4-player.md`, `M5-world.md`,
`M3-car.md`, `M4-loot.md`.

| Lane | Module | Scenario (lane run) | Mutation |
|---|---|---|---|
| player (P4, D6) | `health.lua`, name tag shows the other's health | `playerhealth` 26/26 | `nohealth` 20/26 |
| world (W3, W4, W6, G3) | `world.lua` | `worldsync` 27/27 | `noworldsync` 20/27 |
| car (C1-C4, C7) | `car.lua` | `carsync` 36/36 | `nocarsync` 27/34 |
| items (W1, W2, C6, G1) | `ids.lua`, `loot.lua` | `lootsync` 34/34 | `nointent` 23/34 |

Observations
- Player health is `BP_ResourceManager_C.PlayerHealth`, one per process; damage goes to the process's own manager, so the
  guest's own sim already hurts and heals the guest. The game's `KillPlayer` would travel the guest's process to the garage:
  the guest is clamped at 1 and respawned at the host's car by the mod instead.
- The guest's zone has almost no loot of its own (host 40 lootables + 16 pickups, guest 1): lootables come from the host's
  save, so seed syncing has nothing to regenerate. The guest gets copies from the host's list (class, position, contents).
- Hazards, the zone storm and the exit portals need always-relevant as well as replicate on the host: the default
  15000 uu cull distance hid them from a far guest. The guest's own motion code moved level-placed grabbers back after
  replication, so the guest turns their tick off and follows the host's positions.
- Without a pre-hook, a mission started on the guest crashed it (0x80000003).
- On merged main: `worldsync` failed once (26/27) because its story check wanted the unrooted MissionData to survive GC (fixed
  in the test). `carsync` failed once (32/36): the guest's car settled about 200 uu from the host's reported stop, and the state
  check that followed rejected a message older than 4 s. The rerun passed 36/36.

Unknowns
- None of this has seen a human playtest yet: real door and loot-UI input, the guest's view of anomaly effects, garage
  container sync and the car across a map change.

## 2026-10-21 afternoon: second sync pass, story, progression, launcher

Lanes merged into main, each with its spike doc: backpack (`M4-backpack.md`, `backpacksync` 32/32, `nobackpack` 22/32),
guest actions (`M3-guestact.md`, `guestact` 31/31, `noguestact` 24/31), items 2 (`M4-loot2.md`, `lootsync2` 33/33 zone and
21/21 garage, `nolootsync2` 23/33), story (`M5-story.md`, `storysync` 24/24, `nostory` 21/24), anomalies (`M5-anomalies.md`,
`anomalies` 19/19, `noanom` 17/19), progression (`M5-progression.md`, `progsync` 30/30, `noprog` 20/30), and the launcher app
(`tools/package/app`, C# WinForms built with the in-box .NET Framework csc).

Observations
- Hazards hurt through MSG_Damage_* messages to pawns in range. The guest's pawn on the host runs the same receiver, which
  adjusts the host's one PlayerHealth: a hit on the guest hurt the host (100 -> 90) and not the guest. `anomalies.lua`
  forwards the message to the guest and gives the host back what it lost.
- The game's save is its own SAVC container with a native per-object serializer, and `LoadGame` loads the map. So a
  SaveGameToMemory/LoadGameFromMemory round trip cannot carry progression; it travels as state sets instead (whiteboard
  tags, research nodes, route legs, logbook).
- Garage storage lives in `Inventories_Garage`, keyed by station tag; `Inventory_Garage*` is nil in `RB_Garage`. The
  morning's loot sync never covered it.
- The `carsync` camera check read `PlayerCameraManager` (last frame's view) against the car's current transform, i.e.
  speed x frame time. Against the previous frame it is 6.7 uu (`20261021-134010-carsync`).
- UE4SS hooks on Blueprint functions run after the function returns (guest-actions lane).
- Worktrees made for lanes branch from the commit the session started from, not always from current main: three
  afternoon lanes had to merge main first.

Unknowns
- Untested with real input: the loot UI, scrapper, cutter and siphon, the ARC screen hover-and-press, cutscenes on the
  guest, story props, the Tourist freeze check (it timed out although the log shows the freeze), and a real wrecked run.

## Playtest-1 fixes, overnight 2026-10-22 (lead)

Observations
- Full suite on main after the playtest-1 lanes: 28/31 (`local/test-results/suite-20261022-010350.txt`).
- `lootsync` failed once (`20261022-011719-lootsync`): one `BP_Lootable_MultiMesh_Tacklebox_C` held 4 items on the guest
  against 6 on the host for the whole 90 s; the rerun on the same code passed 34/34 (`20261022-024022-pt1-loot-lootsync`).
- `sessiontravel` failed in the suite only because the suite gave it no `-Fixture garage` (fixed in run-suite.ps1).
- pt1-swap saw a trunk stack count drift by one on a full trunk (guest took 10, host dropped 11) in an earlier run.

Local hand playtest 2026-10-22 evening (two games on one PC, logs in `local/playtest-0.0.6-local/`)
Observations
- Works by hand: guest join (after the 90 s hello wait), loot a world container as guest, guest drops, host picks up,
  moves to the trunk; driving together; car exit (camera back on the character, 2 of 3 times).
- `PT|slow` (main.lua loop timer): in a rendered zone loot.lua still costs 300-400 ms (max ~1 s) every 2 s on both
  sides after the name->address change; garage.lua:214 ~35 ms every 500 ms, anomalies3.lua:150 ~35 ms/s,
  guestact.lua:344 ~45 ms/s, upgrades.lua:171 ~190 ms every 30 s. Headless runs show a fraction of this.
Guesses
- The common cost is UE4SS `FindAllOf` (walks every UObject, ~35 ms per call with a rendered zone loaded). Fix idea:
  `NotifyOnNewObject` for the loot classes instead of polling, one full scan at session start; same for the other loops.
Open (owner wants these fixed next)
- FPS stutter: above. Biggest: loot.lua discovery/purge, then the 35 ms loops.
- Guest sees no buildings/walls in a zone, only loot containers: the zone props mirror is off by default (it starved
  loot sync, 5b70a28); needs pacing near the players before it can be on.
- Guest stuck after a car exit (camera and walking locked) once of three; F8 dump from that case is missing (the one
  dump taken was during the join freeze). Controller flags, view target and movement mode were all normal.
- Host vanished from the driver's seat in the guest's view while driving (once, nothing in either log).
- Ping spam crash fixed (key flag); a hook wrapper in main.lua raised "attempt to index a function value" and the guest
  closed without a crash report: hooks are no longer wrapped. Which hook threw is unknown.

Known gaps (rare, not chased per the owner's priority rule)
- A lootable can stay one snapshot behind on the guest (race between the host's snapshot and a content change). Look at
  that container's `S|L` lines in both logs if a player reports it.
  Correction (`20261022-190420-lootsync`): not a race. The same `BP_Lootable_MultiMesh_Tacklebox_C` held 6 on the host and 5
  on the guest (Plastic missing) for 90 s, and the host's state never changed after the send, so the guest's `ids.apply`
  could not add the 6th item. Guess: the MultiMesh picks its mesh variant per process, and the guest's variant has fewer
  slots. Risk: when the guest takes from it, its 5-item state goes back to the host and the host loses the 6th item.
  Unknown: whether a container's slot count can be raised (no setter found in our dumps yet).
- Full-trunk stack counts can drift by one item (`ids.apply` on a full container, lootsync2 area).
- The guest crashes intermittently on its native rejoin after a run failure (`sessiontravel -Fixture garage`): 5 of 8
  runs overnight (pt1-travel, folders `20261022-03*-pt1-travel-sessiontravel`), AV at varying addresses, crash marker depth 0,
  right after `native rejoin browse` + `loadmap post` with pawn=none. Not tonight's modules: it still crashed with garage,
  guestparts, carfeel, guestswap removed and most modules reverted to 11e3841, and it already crashed on 2026-10-21
  (`20261021-173735-m2gaps-sessiontravel`). Next: measure the flake rate on main vs 11e3841 (about 5 runs each), then look
  at the native rejoin (browse into the same map while the old world tears down).
- `anomalies3` check `guest_pushed_by_bunny` is flaky (about 1 in 3 runs fails: the guest's speed reports come once per
  poll and miss the short shove). Peak speed over the whole step can't replace it: the test's own moves reach 639 uu/s
  without any push (`20261022-082408-anomalies3-noanom3`) against 549 with it. The bunny's damage on the guest
  (`guest_hurt_by_bunny`) is the reliable proof.

## 2026-10-22 night: frame-time pass (where the stutter came from)
Observations (two rendered games on one PC, zone fixture, `pacific-game` eval with os.clock, ~1 ms resolution)
- UE4SS uses the engine's own per-class hash tables here (`[HashTables] Self test passed` in UE4SS.log), so `FindAllOf`
  is cheap: 0.2 ms for PlayerController / BP_Lootable_Base_C (40) / LootableTemplatePart (206), 3 ms for Actor (2620).
  The "FindAllOf ~35 ms" guess from the evening playtest is wrong.
- `UEHelpers.GetWorld()` 0.26 ms and `GetPlayerController()` about the same: both run FindAllOf("PlayerController") and
  a loop per call. `FindObject(class, shortName)` 0.18 ms (walks objects). `ids.spec` called both per item:
  136 ms for the 206 wreck parts of a zone, contents encode 75 ms for 40 lootables. This was the 200-300 ms loot tick.
- `StaticFindObject(path)` and `RegisterHook(path)` of a path that is NOT loaded: 25-45 ms each. UE4SS falls back to a
  scan of every object by full name when the hash misses (`UObjectGlobals.cpp:248`). Hits cost ~0. Every
  "retry the hook until the class loads" loop (anomalies3, guestact, stations, upgrades, garage) paid this per try.
- Guest join: the host's full loot list (~300 lines) applied in one dispatch, 470-590 ms. `claim()` read the name and
  class of every local candidate for every line (O(n²)).
Derived (fixes, measured in the same session)
- Cache the local controller + world (common.lua), the BFL object (ids.lua): host loot tick 250 ms -> 50-70 ms.
- `PTNative_Find` (find.cpp, hash tables only) behind global StaticFindObject/RegisterHook wrappers (common.lua): the
  retry spikes are gone and the same hooks register (`guestact hooked 3-7`, `stations hooked 2-5`, guestswap, guestparts).
- Wreck parts re-read only within 30 m of a player; loot lines drained 4 ms per frame; claim candidates indexed by
  position once per 5 s; host first scan and full list 15 ms per 50 ms. Guest takes 300 host actors in ~3 s with no frame
  over 30 ms. `PT|perf` (main.lua) logs per-loop totals and worst times every 60 s.
Guesses / unknowns
- The guest crashed (AV 0xffffffffffffffff, depth 0, last finished call Controller:IsPlayerController) seconds after its
  4th Lua hot reload in one session (`20261022-223936-repl`). Hot reload is known to be fragile (above); unproven
  whether the new GetPlayerController cache is involved: fresh-launch scenarios decide.
- Zone props mirror (visual.lua): was off; now on by default (sweep cached by address and spread, guest 8 ms per tick).
Observations and derived facts, later the same night
- `stations` on the `C:\PTLanes\main2` pair fails the guest cure the same way with or without the frame-time changes
  (`20261022-174042-main2-stations` before them; `230348`, `231554` after): the guest's own CureCarQuirk returns
  Removed=false. On `C:\PacificTogetherTest` it passes (`183634`, `160312`). Mirror tries do not decide it (40 tries passed
  in `095944`). Guess: that pair's saves (garage storage, progression) differ. Unknown: what the cure lacks there.
- Loot join: before the guest asked for the full list (H), the host's lines overflowed a loading guest's reliable channel
  (`20261022-225808-lootsync`: `Reliable partial bunch overflows reliable buffer! NumOutRec: 254`, connection closed,
  rejoin). Fix: the host sends loot only after that guest's H (loot.lua readyFor); the full list carries the rest.
- playpath p2 (guest opens a crate) and p6 (guest picks up a far world item) fail on unmodified e47ef32 too: 5 runs on a
  baseline worktree, p2 failed 2, p6 3 (`pt-base/local/test-results/20261022-2331*`, `2334*`, `2349*`...). With the
  frame-time changes p2 failed about 5 of 11. Both are "the game never highlighted" the target: an interaction-path flake,
  not loot sync (the host's full list completes in every run, `PT|loot full list sent`).
- UE4SS Lua `IsValid` (UE4SS `LuaUObject.hpp:761`) does not read the object: the pointer must be in a set that a delete
  listener keeps (`is_object_in_global_unreal_object_map`), then `IsUnreachable`. A freed object reads as invalid; a NEW
  object at the same address reads as valid. So cached wrappers are safe from freed memory, not from address reuse:
  the controller/world/singleton caches (common.lua) are dropped on every map load, props verdicts (visual.lua) and the
  loot transient skip carry the class address.
- Open (code review 2026-10-23, not done): net.lua has no per-guest "ready" gate; loot waits for the guest's H and visual
  for its hello, the other modules still send to a loading guest (a burst could overflow its reliable channel the same way).
- Suite on the frame-time code (2026-10-23 night, one pair, 2 clients, mirror ON from shard 1's second half): shard 1/3
  11/14, 2/3 13/14, 3/3 12/14; after the wreck-claim fix: session 40/40, lootsync2 33/33, lootcar 24/24, visual 26/26,
  zonejoin 14/14, sessiontravel 54/54 (no rejoin crash this time), mapmark 22/22, stations 50/50. Remaining fails are
  known flakes or gaps, each seen before tonight: playpath p2/p6 (baseline too), dropfall guest_drop_on_host_ground
  (20261021, 20261022-2005), lootsync tacklebox 6th item, guestparts host_dropped_by_guest_cutter (3 of 15 before),
  carfeel playlist (headless reshuffle), lootcar when the cargo roll leaves one free slot (needs 2 taken).
- Wreck bodies and parts are no longer claimed on the guest: the full list now comes after the guest rolled its own
  wrecks, a claimed part sat on an own body, and purging that body took the part (lootsync2 / guestparts 2026-10-23).
- Code review round 5: keeping "not dressing" verdicts by address without reading the class (cheaper sweep) made
  `visual` fail guest_removed_mesh_gone in 2 of 3 runs (`20261023-022539`, `022831`); reverted, then 3 of 3 passed
  (`2033*`). Guess: an address freed by the removed mesh came back as debris and kept a stale verdict.

## 2026-10-23 morning: hand playtest with the frame-time build (owner, two clients on one PC, logs local/playtest-20261023-morning/)
Observations
- Lag gone by feel (owner). Whole session: host 25 frames over 30 ms, guest 11 (PT|slow).
- Guest stuck after a car exit, reproduced: the guest's BP_MainCharacterManager.CharacterActor pointed at the HOST's
  character (simulated proxy, no controller). Setting it back to the guest's pawn freed walking and camera at once. The same
  flip made session.refreshBodies treat the host's body as ours: it got the invisible first-person material
  (M_PlayerCharacter_Invist) back. A guard (session.lua) put it back once in play (`PT|session guest manager was on ...`).
- Scrappable props (BP_Spawn_ResourceBase_C: PCs, TVs, lights, plasma generators) existed on the host only (56 vs 6); now
  loot kind R. Owner: visible and scrappable as guest, drops right.
- Car doors are physics once unlatched; the guest's copy never swung, and the door-state sync closed the guest's own opening.
  A simulating mesh is detached: its RelativeLocation/Rotation are world values (host hatch loc 70142,-35850,8290).
- Wreck trunk lids on the guest were standalone copies (host: attached to BP_Template_StrippedCar_01_C); attaching them to
  the nearest body copy made the trunk open (owner, by hand).
Derived / not yet verified by hand or a scenario
- Door pose now sent in car space and rebuilt on the guest; shut doors go back on their mount (owner saw the first, world-space
  version misplaced; this version not seen yet). Guest hitting the host: guest's health put back, host takes the hit (not seen).

## 2026-10-23 afternoon: live bug-fix loop (owner, two rendered clients, zone fixture, logs local/playtest-20261023-afternoon/)
Observations
- Seen working by hand: car doors/hatch pose v2 and the guest hitting the host (from the morning), headlights (2nd run).
- Guest pressing X in the car crashed the guest (EXCEPTION_ACCESS_VIOLATION reading 0xffffffffffffffff, game thread in
  AC_CarAudio_C:ReceiveTick). No `PT|car exit intent` line: the game's own "Exit Car" ran locally before our X flag was read.
  Muting "Exit Car" on the guest's own pawn (next to CommandEnterCar): two exits after, no crash.
- Guest frozen on the host after an exit (turns, does not move, then snapped back), for about as long as the ride
  (2.2 s ride -> 2.1 s freeze, 52 s -> 46 s). Probe (Character:ServerMovePacked / ClientMoveResponsePacked hooks, 250 ms):
  ~10 moves per 250 ms reached the host after the exit, 0 responses came back (before the ride: 2-3). The seated guest
  sends no moves (its CharacterMovement tick is off). Turning the host's CharacterMovement tick off during the ride did NOT
  help (52 s ride, 46 s freeze). pc:UnPossess(); pc:Possess(char) on the host 150 ms after the exit: moves accepted at once
  (owner: "worked seamlessly"); now in the g.car.exit handler.
- C (scan) did nothing on host and guest: InpActEvt_ScanObject fires, ObjectToScan is the anomaly (BP_Hazard_PhysicsGrabber2),
  then ScanInvalid. BP_ProgressionManager.CanScanObject returns false unless QD_Q00_Mission_B (or QD_Q00_Demo_Mission_A)
  is complete; in the zone fixture both are incomplete (the fixture came from TravelToNextLeg on the garage save, the
  tutorial was never finished). Not our bug as far as seen; needs a fixture made by finishing Q00 to test scanning.
- Guest closing a door the host opened did nothing: we forwarded AttemptOpen only. AttemptShut now forwarded too; the host
  shut at once (0.3 s), the guest showed it 3.8 s later: its own 1.5 s door hold dropped the host's change and the next
  state came after 3 s. Now the held state is applied when the hold ends, and a shut of a door posed from the host sets no hold.
  Owner: closes, but "like 3 fps" (car state every 250 ms); host now also sends at 20 Hz while a door's physics turns.
- Grabbers: same 25 hazards on both sides, but the awake grabbers' CoreFloatingMesh sat ~650 uu under the actor on the guest
  (host: 0), owner saw "a wiggling wreck" instead. The core's world position now goes with g.world.pos; owner: synced.
- Door swing at 20 Hz while it turns: owner "faster, not smooth", accepted as is.
- Guest entering by a door left it open (swung while driving): the game's entry animation shuts it, our seat() does not.
  The host now shuts the door of the guest's last open intent (within 5 s) 0.8 s after seating. Owner: works.
- Guest's ARC map: icons on a blank sheet, no terrain or roads (host: both). No MapFog or MapRevealer on either side; the
  terrain is BP_GobblerMapBounds' own capture at level start. RecaptureMinimap on the guest drew it (seen live); mapmark.lua
  now recaptures 10 s and 40 s after the guest first sees the bounds (35 ms frame each). Owner: works.
Unknowns / open
- One dormant grabber has different names on host and guest (97A5... vs ..._C_2147477136), so it is never position-synced.
- Grabber position on the guest trails the host by ~200 uu (250 ms updates, no interpolation).
- Scenarios on 061d114 (two pairs in parallel): carenter 21/21, carexit 29/29, anomalies 19/19, session 40/40, playpath
  39/39, guestact 32/32, worldsync 27/27, anomalies2 27/27; carsync 35/36 in parallel (guest_car_follows t=1), 36/36 alone;
  mapmark 16/19: guest crash after its death rejoin, same last calls as 20261022-084655 and -162801 (known rejoin crash in
  mapmark's icon loop, before today's recapture; the recapture ran 30 s earlier). Zip dist/PacificTogether-0.0.6-dev-061d114.zip.

## 2026-10-23 evening: facts from upstream PDCoopNet v0.8/v0.9-dev and coop-anything 5b86e5b

Sources: github.com/BroZYTnikkkk/pacific-drive-coop (docs/WORLD_SYNC.md, README) and its lab notes on
BroZYTnikkkk/coop-anything branch game/pacific-drive (games/pacific-drive/NOTES.md, 2026-10-23). Their text, not checked by
us unless said. Their code is no longer in this repo (`reference/pdcoopnet` keeps the v0.2 notes); `tools/pak/pak.py` is our
own pak v11 reader (same file lists for all 5 paks as their tool, extracted files byte-identical to `local/research-extract`).

Observations (ours)
- Guest E on a zone door copy now reaches the host: hook on the Highlight interact event of BP_Door_Single_C and
  BP_Door_Sliding_Single_C (the declaring classes), g.vis.door with the host's actor name, the host presses its door's
  Highlight. Door copies keep the Visibility response (other copies still ignore it). visual 28/28 with the new
  host_door_used_by_guest (host door 0 -> 2 about 1 s after the guest's press). Final code, zone fixture: visual 28/28
  (`20261023-181155-main2-visual`), playpath 39/39 (`180938`), lootsync 34/34 (`180844`), lootsync2 33/33 (`181028`).
- loot.lua guest pickup detection read `.Instance` of an actor already failing the alive check (freed memory when the actor
  was gone). Guarding it with IsValid dropped the pickup report (playpath p6_world_item_gone_on_host failed once,
  `20261023-175526-main2-playpath`); the instance is now kept while the actor lives and checked instead.

Derived / theirs (not checked by us)
- Reading fields of a pooled item actor whose Instance is gone crashes natively; pcall does not catch it.
- `ReplicatedMovement.RotationQuantizationLevel` changed on one side only breaks the connection (level never sent).
- Handlers must not run inside an RPC hook (one that loaded an asset hung the client): queue, handle from a loop.
- Container events: hooks on `UItemContainer::HandleSlotItemAdded/Removed` see every item entering or leaving any
  container; `RegisterBeginPlayPostHook` as a "new actors appeared" counter to gate whole-world scans. Candidate fix for
  our FindAllOf polling cost (not tried).
- The zone is chosen at travel time: the same save and route gave two copies different maps.
- The remote body can play the shipped ALS clips from Lua (`SetAnimationMode(1)`, `PlayAnimation`, `SetPlayRate`).

Unknowns
- A real E press on a door copy (trace + highlight) is not seen yet: the scenario presses the copy's Highlight directly.

## 2026-10-23 evening: first real Steam play (owner's PC = guest, real install, 0.0.6-dev-e56651f; logs local/playtest-20261023-steam/)

Observations
- Four sessions 18:52-19:30 local, all joined over Steam between two real accounts: each engine log has `Welcomed by server`
  (garage once, zone Rural_Forest_Radio_Scylla_02 in all four; 15:57 and 16:29 UTC end with "Host closed the connection.").
- Last session's UE4SS.log (the only one kept; UE4SS overwrites it per launch): the invite / Join Game callback arrived while the
  game ran (`PT|steam event join_lobby`, callback 333 path), lobby entered, tunnel peer 10.77.0.1 -> host SteamID, warm-up echo
  reliable and unreliable after 2.0 s, then the ordinary join and hello. So the Steam tunnel carries UE traffic between two
  accounts: the main X6/PT2-steam unknown.
- Host engine log (friend's PC, saved as host-PenDriverPro.log): one launch 18:52-19:32, garage `?listen` 15:52, zone 15:57:20,
  garage again 16:30:01 (after both died), main menu 16:32. So the two "Host closed the connection" are the host's own travels,
  not drops. No mod lines in it (ours go to UE4SS.log). 12k+ each of `Divide by zero detected: 425/0`, `325/0`, `0/0` on the
  host only: source not looked up.
- Guest sessions vs owner's account: 18:58 quit after X in the zone launched the car (#3); 18:59-19:17 ended by the hard
  freeze after the arc anchor (#6/#16); 19:27 rejoin, long stall at the zone entry, car launched, both died (#17).

Owner + friend reports from play (guest = owner, host = friend; numbering is the owner's list)
1. Chained side doors in the garage (pried open): opened by the guest, the door swings, but an invisible wall blocks the guest.
   Opened by the host, it works for both.
2. Guest driving: scraping-metal sound sometimes, host never hears it (maybe while turning).
3. Zone load: guest spawns in the driver's seat (game default), stuck. X: guest falls through the ground, then is put back
   floating above the car with the camera stuck to it; once the X launched the car.
4. Story lines repeat for the guest until the "mission updated" log appears.
5. Transmuter (in place of an ARDA container, small building) shown to the host only.
6. Guest frozen and snapped back while the host is in pause, loot container, trunk or crafting grid ("pause game while in
   inventories" was on: likely the cause). Once a freeze never ended (restart): host in the car using the ARC anchor at the car's
   ARC machine (behind the guest's seat); guest still heard car sounds as if seated.
7. Host's crafted Impact Hammer, seen by the guest: huge, broken texture (screenshot from owner, green body lying on the road
   next to the car), from the moment it was crafted.
7b. Plasma generator broken by the host: its drops reach the guest, the generator stays whole on the guest.
8. Radiation never hurts the guest.
9. Wheel damage (broken, punctured) not shown on either client, but a scan reports it damaged. Owner: not vanilla behaviour.
10. Guest scrapping sometimes leaves its sound playing.
11. No "paused by host" label on the guest: pauses look like lag.
12. Guest's legs stick out under the car (body copy seated).
13. Cyrillic Steam name renders as squares on the floating nametag (fine in the UI hint): font lacks Cyrillic.
14. Guest car entry sometimes slow.
15. ARC anchor structures invisible to the guest; once the host picks one up it shows in their hands, dropped it shows on the floor.
16. After the host inserted the ARC anchor, the car froze for the guest (sounds kept playing): same event as #6's hard freeze.
17. After several rejoins, 40-60 s stuck at the zone entry crossing, unable to move; then the car was launched spinning into
   the air, its impact killed both, both sent to the garage, guest launched again there.
- Worked: car parts, driving, Grabber (per-frame jumpy on the guest), floor items, buildings, scrappables, crafting, inventories.
- Host felt lower FPS / more sluggish than solo; no other complaints.

- Host UE4SS.log (friend sent it, saved as host-UE4SS.log, 18:52-19:32): no PT|error, no Lua traceback. Hitches: 257
  `PT|slow` lines (>30 ms in one callback), nearly all car.lua:740 (host car tick, 250 ms loop) and car.lua:753 (door swing
  loop, 50 ms), plus visual.lua:552, loot.lua:721, progression.lua:118. Last perf window: car.lua:740 total 1098 ms
  (max 33, n=222), carfeel.lua:265 851 ms, visual.lua:552 516 ms, car.lua:753 474 ms; FindAllOf BP_CarManager_C 403 ms
  over n=1376 and PlayerController 347 ms. Fits the friend's "more sluggish than solo" (derived, not measured in FPS).
- Host log at the ARC freeze (19:14-19:18): only slow lines, nothing from car/session until the guest's rejoin at 19:18:15
  (seated 19:18:46). So the host saw nothing wrong; the freeze was on the guest's side.

- Guest-only engine warnings (lead, diff of guest vs host warning kinds):
  - `SerializeNewActor failed to find/spawn actor` for actors of `Rural_Forest_Radio_Scylla_02_Mission_Sub`:
    BP_Hazard_Tesla_C x8, BP_Hazard_PhysicsGrabber_C x6, BP_LevelTransition_ExitPortal_C x4,
    BP_Resource_Narrative_Q01_RadioBitsGrabbable_C x4 (each zone join). Fits "Spark Tower not working" on the guest; the
    exit portal (gateway) and the Q01 quest item may be missing or unsynced on the guest too (not checked).
  - `No owning connection for actor BP_Hazard_PhysicsGrabber_C / BP_Hazard_Bollard_C. Function SERVER_Start/Stop will not
    be processed`: the guest's own hazard copies call server RPCs.
  - `CreateSavedMove: Hit limit of N saved moves` 66+ times around 16:00-16:10 UTC: the guest's moves not acked while the
    host was paused in menus (#6).
  - `ClientAdjustPosition_Implementation could not resolve the new relative movement base actor` ~45x at the garage join
    (base SM_Metal_Sheet_2), once in the zone.
  - `Ability ARC Doc / Handbrake no longer "available" from provider`, `GetHotbarSlots index 2 of length 2` (guest hotbar),
    `GetGarageInventory` index warning, `GasPump GetUpgrades index -1`: guest-side UI/state mismatches, not looked into.
Unknowns
- The guest's UE4SS logs of the first three sessions are gone (the freeze after the ARC anchor was in the second).

## 2026-10-24 night: Steam playtest fixes (lead + 10 Sonnet lanes, owner asleep; spike docs docs/spikes/PT3-*.md, PT1-portal.md, PT1-pt3-spawn.md)

All proven headless two-client only (no rendered or hand check). Numbers refer to the Steam playtest list above.

Observations (scenario runs, folders in local/test-results)
- #3 guest put in the DRIVER seat on a zone join: the game attaches a character spawned while the host drives to the driver
  seat; the host now moves it to the passenger seat (car.lua). zonespawn 34/34, mutation nozonefix 32/34.
- #6 host menus froze the guest: everything goes through BP_UIManager_C:PauseGame; with a session only the Esc menu
  (instigator PauseMenu) keeps its pause (pause.lua). #11 "Paused by host" banner on the guest. pausehost 27/27, nopause 22/27.
- #1 chained garage doors: guest lock-open and E run on the host's map-placed door (g.vis.unlock, g.vis.door, full-path key).
  worlddoors 21/21. #15 ARC anchor structures and #7b broken plasma generators on the guest: worldzone 26/26.
- #8 radiation: the radiating volumes are spawned at runtime on the host only (host 8, guest 3); radiation.lua sends them and
  the guest spawns copies (damage only, no decal/VFX). radiation 20/20, norad 16/20.
- #9 flat tyres: SE_FlatTire on the host set GetPartFlat on the host only; wheelflat.lua mirrors the flat map. wheelflat
  17/17. On-screen look not checked.
- #4 story lines: the guest's 6 s dedupe window was just shorter than the replay interval in the real log; now 90 s, and the
  guest stops writing WB.Statistics.* tags. storysync 24/24, storyprog 26/26, progsync 30/30. Not proven against the real repeat.
- #7 Impact Hammer: the tool carries a visible /Engine/BasicShapes/Cylinder that hands.lua took as the base; engine meshes
  skipped. hands 64/64. #13 Cyrillic nametag: TextRender only draws offline fonts (256 Latin glyphs); names with letters above
  U+00FF use a UMG TextBlock at the head (nametag 23/23; lead fixed the byte test to the UTF-8 lead byte). #2 scrape sound:
  BP_CarScrapeFX_C destroyed on spawn on the guest (carfeel 42/42; cause read from bytecode, not heard).
- Spark Tower: SpatialTickController switches managed hazards off by distance (5000) from the HOST's player; hazards near a guest
  are kept ticking, player-range hazards (landmines, bollards, grabbers) arm for the guest, Tesla beam/discharge mirrored,
  replicated hazard copies glide (anomalies3.lua, world.lua). anomtesla 20/20.
- Exit portals and Q01 radio bits: the guest destroyed its own level-placed copy before the host's actor channel bound to it
  (SerializeNewActor failed); now the guest keeps copies the host has. portals 20/20 (portal half not reproduced in the fixture).
- Guest UI: Esc opens the pause menu (a client's SetGamePaused always fails), End/F8 + `ptunstick` with "Controls reset",
  "X  Exit car" hint, Joining/Loading/Waiting text, fade on seat changes (guestui.lua). guestui 40/40.
- Host frame time: car host tick 3.9 -> 1.0 ms/call, swing watcher gone from the top 8, carfeel ticks halved (carsync window,
  docs/spikes/PT3-perf.md). Hooks seen firing on the host: UpdatedCarEquip, Tintable SetPaint/SetDecal.
- Two code reviews of the merged code; 14 fixes by the lead (35a885d, d818b35, e080c60, 54d56ce).
- Full suite on main d818b35 (2 shards): 46/50. Reruns: lootcar 24/24 (flake). Fail twice: playpath p6 (guest ground pickup
  never reaches the host), guestparts (1-2 different checks per run), mapmark (guest crash after its death rejoin, same address
  0x1e31c0cc0 as 2026-10-23 16:36: pre-existing). Lanes pt3-regress (p6, guestparts) and pt3-crash (mapmark) started 03:00.
- pt3-regress: p6 and the cutter check were test flakes (two chemicals 73 uu apart, near() took the first; a panel's drop is a
  loot roll). pt3-crash: the guest's 1 ms ride loop (car.lua) read the old world's pawn after a rejoin while seated; now
  validity-checked and cancelled at map change (section below). Lead: guestparts "door stays repaired by blowtorch" broke after
  the perf merge (the host's part lines cached for 1 s sent the old health back); the cache is dropped after any guest
  g.parts/g.act/g.swap message (net.tap, 24b9568).
- Final on main 24b9568: playpath 39/39, carexit 29/29, mapmark 22/22 x2, zonespawn 34/34, sessionrejoin 36/36, guestparts
  73/73 x2, guestswap 33/33, carsync 36/36, session 40/40. Zip dist/PacificTogether-0.0.6-dev-24b9568.zip.

Unknowns / not fixed
- #16 freeze after the ARC anchor: the ARC machine code never pauses, dilates time or repossesses; host log clean; cause on the
  guest side, needs a live repro or the guest's UE4SS log.
- #5 transmuter vs ARDA container: not reproduced (the host's transmuter reaches the guest, ~1 min late).
- #10 scrapper sound left playing, #12 legs under the car, #14 slow car entry, #17 40-60 s stall (assumed same cause as #3).
- Landmines still creep toward the host only; the guest's radiation copies have no visuals; a host pause opened before the guest
  joined is not refused; host health read 97 once after a Tesla shot at the guest (anomtesla run, unverified).

## 2026-10-24 night: the guest's rejoin crash in mapmark (pt3-crash)

Observations: crash (EXCEPTION_ACCESS_VIOLATION, 0x1e31c0cc0 / 0xffffffffffffffff) in 3 of 3 mapmark runs on main, about 50% of runs with mutate and ~0 of 6 with the fix. CrashContext call stack symbolized with dbghelp + UE4SS.pdb: Lua `obj.Property` read -> UObjectBase::prepare_to_handle -> UStruct::FindProperty -> TFieldIterator (a freed object's class pointer). Tracing every loop for 6 s after the load map (run 20261024-032013-pt3-crash-mapmark-noridefree): the last loop entered was car.lua's seat-hold loop (`ride`, 1 ms).
Derived: that loop kept `char`/`car` of the old world through the guest's rejoin and called `char:GetAttachParentActor()` without a validity check (pcall cannot catch an access violation). Fix in car.lua: the loop checks valid(char) and valid(car) first and cancels itself; a LoadMapPre hook cancels it. Mutation PT_MUTATE=noridefree switches both off.
Results: mapmark 22/22 twice with the fix (20261024-032235, -032333), noridefree: 2 of 3 runs pass by luck, 1 crashes (-032625); sessionrejoin 36/36 (-032823), guestdeath (zone) 30/30 (-034615).
