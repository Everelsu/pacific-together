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
- Zone props mirror (visual.lua) still off: host scan walks all Actors each second, guest mesh loads up to 30 ms a batch.
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
