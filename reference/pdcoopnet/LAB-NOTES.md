# Pacific Drive — working notes

## Session 2026-10-19 — Phase 0 triage + Phase 1 research

### Observations (checked this session)
- Store: Steam, appid 1458140, buildid 21896301 (from appmanifest).
- Main exe: `<game dir>/PenDriverPro/Binaries/Win64/PenDriverPro-Win64-Shipping.exe`,
  SHA-256 `568bb63476c6de5fc2b1878572a655dd631dd25bb44fe304e3d96a51f6b98f7e`,
  timestamp in Manifest_NonUFSFiles_Win64.txt: 2026-02-12. No version resource in the exe.
- Internal project name: `PenDriverPro`. Paks: `pakchunk0..4-WindowsNoEditor.pak`, pak format version 11.
- `Engine/Binaries/ThirdParty/PhysX3` present. `steam_api64.dll` shipped.
- OS: Windows 11 x64.
- Repo: no Pacific Drive entry in DIRECTORY.md or games/; no issues/PRs matching "pacific".
- GitHub repo search "pacific drive": no co-op project. Related single-player mods:
  keton/pacific-drive-uevr (UEVR profile), itsloopyo/pacific-drive-headtracking (native hooks,
  has offsets for Steam and GDK builds), MrPerruche/PDCmdMod (UE4SS Lua). Several
  "Pacific-Drive-Cheats/Trainer" repos with "File Size: 156 MB" blurbs look like malware bait — not opened.
- NorthernForce/PacificDrive is unrelated (FRC robot Java code).
- Nexus: many UE4SS mods (UE4SS 3.0.1 stable / experimental used); none multiplayer.

### Derived
- Engine: Unreal Engine 4, most likely 4.26 or 4.27 (pak v11 + WindowsNoEditor + PhysX3). Exact version: unknown.
- UE4 has built-in replication / NetDriver, but a single-player game may have stripped or
  never set up replication on its Blueprints. Whether the shipping exe contains IpNetDriver /
  OnlineSubsystemSteam: unknown (check pending).

### Guesses
- Route: UE4SS (Lua + C++ mod) for hooking, SDK dump via UE4SS, then either (a) try UE4's own
  netcode (open listen server, replicate the car/player), or (b) own sync layer over Steam
  networking with puppet players.

### Unknowns
- Whether earlier co-op attempt exists: web search result text mentions a 2024 Steam forum
  modder whose work was "frozen indefinitely" (loot sync, stable player movement). The thread
  https://steamcommunity.com/app/1458140/discussions/0/4291439538013940878/ redirected to the
  forum index on fetch (deleted/hidden?). Author, code, builds: unknown.

### Sources
- https://steamcommunity.com/app/1458140/discussions/0/4291439538013940878/
- https://steamcommunity.com/app/1458140/discussions/0/682986927120449638/
- https://www.nexusmods.com/pacificdrive/mods/206
- https://github.com/keton/pacific-drive-uevr
- https://github.com/itsloopyo/pacific-drive-headtracking

## Session 2026-10-19 — Phase 2 workspace

### Observations
- Test copy: `<test dir>/client1` made with robocopy, 86/86 files, 25.03 GB, 0 failed.
  Copied exe SHA-256 matches the original. The original install is not modified.
- No existing Pacific Drive save folder was found under %LOCALAPPDATA%, %APPDATA%, Documents,
  Saved Games or Steam userdata before the first test launch.
- UE4SS used: `experimental-latest` dev build `zDEV-UE4SS_v3.0.1-1181-g83330635.zip`,
  SHA-256 `82378cd7f679d055026286f11347355ac67c712f21eb892060c902bb0184b907` (matches GitHub release digest,
  asset dated 2026-10-17). Also downloaded stable `v3.0.1` (no published digest; local SHA-256:
  UE4SS_v3.0.1.zip `4b47d4bceddd2f561a4e395bfa00924ccfc945af576a2d0c613e6537846c57ec`,
  zDEV-UE4SS_v3.0.1.zip `af777d2af33fce4d520de35a8665e417376bcc530fec647778012ce6cdf51b2b`).
- Installed as `dwmapi.dll` proxy + `ue4ss/` folder in `PenDriverPro/Binaries/Win64` of the test copy.
  `steam_appid.txt` (1458140) added so the copy does not restart through Steam into the original install.
- No `CustomGameConfigs/Pacific Drive` entry ships with UE4SS.
- UE4SS ships `SplitScreenMod` (sets GameMapsSettings.bUseSplitscreen and calls
  GameplayStatics.CreatePlayer). Idea to test: local split screen + Steam Remote Play Together
  as a quick "online" path before real netcode (see playbook/split-screen.md).
- Probe mod `PDCoopProbe` (Lua): after 45 s logs net driver classes, GameInstance, World,
  player/vehicle actors, then runs DumpAllObjects, GenerateSDK, GenerateUHTCompatibleHeaders,
  GenerateLuaTypes, DumpUSMAP.

## Session 2026-10-19 — Phase 3 first look (UE4SS dumps)

### Observations
- UE4SS log: `Found EngineVersion: 4.27`, shipping build; usmap named `PenDriverPro-4.27.2-0+++UE4+Release-4.27`.
  So the engine is **UE 4.27.2**.
- UE4SS experimental build 83330635 loads with no custom game config; Lua mods run.
- Main menu map: `/Game/Maps/RunProto/RB_MainMenu`. GameEngine `DrivingGameEngine`, GameInstance
  `DrivingGameInstance`, menu PC `BP_MainMenu_PlayerController_C`, menu GM `BP_MainMenuGamemode_C`.
- Class presence (StaticFindObject): `IpNetDriver` FOUND, `NetDriver` FOUND, `DemoNetDriver` FOUND,
  `OnlineEngineInterfaceImpl` FOUND; `SteamNetDriver` and `SteamSocketsNetDriver` missing.
  `/Script/Engine.GameMapsSettings` reported missing (it lives in `/Script/EngineSettings`, probe path was wrong).
- Native game modules in the UHT dump: PenDriverPro (593 headers), PenDriverInventory (165),
  PenDriverUtils (55), IWCarPhysics (29), PenDriverDataBlocks, PenDriverUI, EntityFramework,
  DuctTape, IWHaptics, IWPhotoMode, IWAnalytics. Plugins: SMSystem (Logic Driver state machines),
  AkAudio/Wwise, Houdini, MinimapPlugin, PrefabAsset, Sentry, GameAnalytics.
- No OnlineSubsystemSteam module in the dump.
- **Replication specifiers in game native code: zero** (`Replicated`, `ReplicatedUsing`, `NetMulticast`,
  `Server`, `Client` all 0 in PenDriverPro, PenDriverInventory, IWCarPhysics, EntityFramework,
  PenDriverUtils, DuctTape). Sanity check: the same dumper finds 255 `Replicated` + 47 `ReplicatedUsing`
  in Engine, so the dumper does emit them. Only SMSystem has some (plugin's generic support).
- Core classes: `ABaseCharacter : ACharacter`; `ABaseNewCar : ANewVehiclePawn` (IWCarPhysics, custom,
  not PhysXVehicles); `ABaseDrivingGameMode : AGameModeBase`; `ABasePlayerController : APlayerController`;
  managers `UBaseSaveGameManager`, `UBaseCarManager`, `UBaseCharacterManager`, `UBaseInventoryManager`
  derive from `UBaseManager`. Player animation uses ALS (Advanced Locomotion System) Blueprint assets.
- Save manager exposes SaveGame/LoadGame/SaveCheckpoint/LoadFromCheckpoint/MakeBookmark/QuitToMenu UFUNCTIONs.
- The first test launch created `%LOCALAPPDATA%/PenDriverPro/Saved` (Config, Logs; no SaveGames yet).
  This folder is shared with the original install.

### Derived
- UE's own netcode (IpNetDriver, listen server) is compiled in, so engine-level replication is
  available: ACharacter movement replicates via CharacterMovementComponent once the pawn replicates.
- The game logic itself (car physics, inventory, managers, saves) has no replication at all, so the
  car, loot, car parts, damage and run state need our own sync (host authority), either as replicated
  properties/RPCs added from a C++ UE4SS mod or as a separate transport. This matches the 2024 attempt
  stalling on "loot synchronization and stable player movement".

### Next experiments (planned, not run)
1. Second test instance (`client2`): hardlink paks from client1, real copy of Binaries; isolate
   `%LOCALAPPDATA%/PenDriverPro` per instance (test `-userdir=`; else hook SHGetKnownFolderPath).
2. Host: `open <map>?listen` from a Lua mod; client: `open 127.0.0.1`. Record whether the client
   loads, spawns a pawn, and whether players see each other move (Stage 2 "puppet" via engine replication).
3. Probe car: `NewVehiclePawn` properties, whether bReplicates / ReplicateMovement can be forced.
4. Quick alternative to evaluate: UE local split screen (`GameMapsSettings.bUseSplitscreen` +
   `GameplayStatics.CreatePlayer`, UE4SS SplitScreenMod) + Steam Remote Play Together.

## Session 2026-10-19 — Phase 3/Stage 2: engine listen server experiments

### Setup (observations)
- `client2`: 82 files hardlinked from `client1` (paks, Engine), `PenDriverPro/Binaries/Win64` copied
  (own UE4SS config, logs and mods). Disk cost of client2 is only the Binaries folder.
- Per-instance settings: `-NotInstalled` on the command line makes the shipping build write
  `Saved/` into `<instance>/PenDriverPro/Saved` instead of `%LOCALAPPDATA%/PenDriverPro/Saved`.
  Checked: the instance folder gets `Config/` and `Logs/`, and `%LOCALAPPDATA%/PenDriverPro` got no new
  writes during any `-NotInstalled` run. Where SaveGames go under `-NotInstalled`: unknown (no save made yet).
- Two instances of the Steam build run at the same time on one PC with Steam running (no mutex block seen).
- Pak index: pak v11, not encrypted, compression Zlib. `tools/paklist.py` / `tools/pakextract.py`
  (kept locally, small pure-Python) list and extract files. 70,547 files in pakchunk0.
- `DefaultEngine.ini`: no NetDriverDefinitions override (engine default IpNetDriver),
  `GameDefaultMap=/Game/Maps/RunProto/RB_MainMenu`, `GlobalDefaultGameMode=/Game/Systems/GameModes/BP_DrivingGameMode`,
  `GameInstanceClass=/Script/PenDriverPro.DrivingGameInstance`, `bUseSplitscreen=False`,
  `TwoPlayerSplitscreenLayout=Vertical`. Hub map: `/Game/Maps/RunProto/RB_Garage`.
- Test mod `PDCoopNet` (Lua, UE4SS): role file per instance; host runs `open <map>?listen` at +40 s,
  client runs `open 127.0.0.1:7777` at +90 s; both log a `PDNET|` status line every 5 s; host teleports
  its own pawn ±150 uu every 5 s so the client can check movement replication.

### Experiment 1: main menu map (`RB_MainMenu?listen`) — ran, PASS
- Host: `standalone=false`, IpNetDriver created, listening on 7777.
- Client log: `Welcomed by server (Level: /Game/Maps/RunProto/RB_MainMenu, Game: .../BP_MainMenuGamemode_C)`;
  host log: `Join succeeded`.
- Host: 2 PlayerControllers, a second `DefaultPawn` owned by the remote PC.
- Client: own DefaultPawn is AutonomousProxy (role 2); host DefaultPawn is SimulatedProxy (role 1) and its
  X position alternates 0 / -150 in step with the host nudges, so movement replication works.
- `LogNetVersion: PenDriverPro 1.15.0 ... EngineNetVer: 17, GameNetVer: 0` on both sides.

### Experiment 2: hub map (`RB_Garage?listen`) — ran, PARTIAL
- Host loads RB_Garage as listen server with no save loaded; spawns `PDP_MainCharacter_C` (player) and
  `BP_PlayerCarNew_C` (car). Client joins (`Join succeeded`) and loads RB_Garage.
- Host character replicates to the client: `PDP_MainCharacter_C` role 1 on the client, X alternates
  3046 / 3196 with the host nudges.
- The car replicates as an actor (client sees `BP_PlayerCarNew_C` role 1 at the host's position), **but the
  client also has its own local car** (`BP_PlayerCarNew_C` role 3, ~2 uu away): level/Blueprint spawn logic runs
  on the client too, so there are two cars on the client.
- **The joining player gets no character**: host has 2 PCs but only its own `PDP_MainCharacter_C`; the client
  only has a local `SpectatorPawn`. The game mode spawns the character for the first player only.
- Host log error on join: `LogPlayerController: Error: EnableInput can only be specified on a PlayerController for itself`.
- Client log: many content errors, e.g. missing DLC package `/PDFeature_Fig/.../BP_Fig_Mission_Chapter08`
  requested by `AEntitlementSpawner`, DataTable `Missing RowStruct` on RoadSplineActors (also on host).

### Derived
- Engine replication is a working base: connection, travel, Character movement and actor replication
  all work without native patches. Co-op can be built "the UE way" from a UE4SS mod.
- Work items, in order: (1) spawn and possess a `PDP_MainCharacter_C` for each joining PC on the host
  (hook game mode PostLogin / HandleStartingNewPlayer); (2) stop client-side duplicate spawns (car, world
  actors) — run spawner logic on authority only, or destroy non-replicated duplicates on clients;
  (3) car: physics is IWCarPhysics (custom, no replication) → host-authoritative car with replicated
  transform/velocity, client as passenger first; (4) inventory, loot, car parts, damage via RPCs/replicated
  state; (5) saves on host only; (6) Steam transport for internet play (no SteamNetDriver in the build;
  options: IpNetDriver + port forward/VPN first, a Steam sockets driver later).

### Unknowns
- Whether `PDP_MainCharacter_C` controls (interaction, inventory UI) work for a non-first player.
- Whether running a real save/run (not a raw `open`) keeps the listen server alive across level travel
  (runs load new maps; needs seamless/server travel with clients following).

## Session 2026-10-19 — Stage 2: second player character + client car duplicate (PDCoopNet v2)

### What the mod does now (host = listen server on RB_Garage, client = joins 127.0.0.1)
- Host: every 5 s, for each remote PlayerController without a `PDP_MainCharacter_C`, spawns one with
  `GameplayStatics.BeginDeferredActorSpawnFromClass` + `FinishSpawningActor` (class taken from the host's
  own character, 250 uu beside it) and calls `Controller.Possess`.
- Host: after the spawn, `BP_MainCharacterManager_C.CharacterActor` has switched to the new character
  (single-player manager keeps one reference); the mod sets it back to the host's character.
- Client: finds `BP_PlayerCarNew_C` actors with Role = Authority (the client's own local car) while a
  SimulatedProxy copy from the host exists, calls `K2_DestroyActor` on the local one and points
  `BP_CarManager_C.NewCarActor` at the replicated car.
- Client: walks forward with `AddMovementInput` in 3 s bursts (client -> host movement check).

### Observations
- `BP_DrivingGameMode_C`: `DefaultPawnClass=PDP_MainCharacter_C`, `bStartPlayersAsSpectators=true`
  (this is why joining players stayed spectators: the game spawns the character for player 1 itself).
- Spawn + Possess works: client gets `PDP_MainCharacter_C` as AutonomousProxy (role 2); host sees it as a
  remote character; client input moves it and the host's copy follows (server-authoritative
  CharacterMovement with client prediction, stock UE).
- Client `BP_MainCharacterManager_C.CharacterActor` points at the client's own character without the mod
  doing it (the mod's bind step found it already set).
- `K2_DestroyActor` on the client's local car works: the actor is PendingKill with 0 live components right
  after the call. It stays visible to `FindAllOf` (and `IsValid()` in UE4SS Lua stays true) until garbage
  collection, which did not happen within ~2 min; early runs misread this zombie (location 0,0,0) as
  "destroy failed". Lesson: in UE4SS Lua treat `HasAnyInternalFlags(EInternalObjectFlags.PendingKill)` as gone.
- Survey on the client after joining: the player car was the only actor class with
  `bReplicates && Role == Authority` (i.e. the only locally spawned duplicate of a replicated actor).
  Non-replicated local actors (loot, props spawned by client-side logic) are not covered by this survey.
- Remaining host log error on join: `LogPlayerController: Error: EnableInput can only be specified on a
  PlayerController for itself` (also on the client side once).
- Test UE4SS Lua binding note: `K2_GetComponentsByClass` result is neither a Lua table of objects usable with
  `ipairs` nor a TArray with `:ForEach` in this build (exp5 error `attempt to call a nil value (method 'ForEach')`,
  exp6 found 0 components on a destroyed actor) — container type still to be confirmed on a live actor.

### Automated test (tools/run_test.ps1) — ran 2026-10-19, run "exp7-final", 200 s
```
PASS  client connected to host (serverConn=yes)
PASS  host has 2 PlayerControllers
PASS  client possesses own PDP_MainCharacter (local, role=2)
PASS  client sees host character (role=1)
PASS  host sees remote PDP_MainCharacter
PASS  client has exactly one player car
PASS  client car is the replicated one (role=1)
PASS  client walking moves its character on the host (>=3 distinct positions)
PASS  host movement visible on client (>=2 distinct positions)
SUMMARY: 9/9 checks passed
```
Earlier runs: exp3 (spawn OK, dedupe misread), exp4/exp5/exp6 (dedupe diagnostics), each with the character
checks passing.

### Not tested yet
- Anything a human sees: camera, HUD, animation of the remote character, interaction/inventory for player 2.
- Entering/driving the car with two players, car physics on the client, leaving the garage for a run
  (level travel), saves, internet play.

## Session 2026-10-19 — Stage 3: host drives, client rides as passenger (PDCoopNet v3)

### How it works now
- Client -> host command channel without new RPCs: the client calls the stock reliable Server RPC
  `PlayerController.ServerChangeName("PDCOOP:SEAT")`; the host reads remote `PlayerState` names every 5 s,
  acts on the `PDCOOP:` prefix and then renames the player ("Passenger").
- Host on `SEAT`: `CharacterMovement:DisableMovement()`, collision off, teleport the remote character to
  `TempSocket_Seat` + 70 uu to the car's right, `K2_AttachToActor(car, None, KeepWorld x3)`. Attachment replicates.
- Host bot drive: `PDP_MainCharacter_C.CommandEnterCar(true, nil, false)` (called as a UFunction object: the
  managers only have a *delegate* of that name, `cm:CommandEnterCar()` hits the delegate and fails with
  `attempt to call a MulticastDelegateProperty value`), then fallbacks (driver door highlight event,
  `PlayerController:Possess(car)` + `BP_CarManager_C."Register Car Possessed"(true)`),
  `ManualSetIgnition_NoAnim(2)`, `ManualActivate_Gearbox(...)`, `VehicleController:SetParkingBrakeActive(false)`,
  then every frame `AccelerateBrake(dir)`, `DriveControl(dir)`, `VehicleController.ThrottleInput = dir`
  (forward 4 s / back 4 s). `car:SetReplicateMovement(true)` on the host.
- Client when attached: own CharacterMovement disabled and its tick off, collision off, re-seated at the same
  seat point and re-attached locally; the replicated car's `Chassis` made kinematic and its
  `VehicleController` tick off; every frame the client sets the car transform from `car.ReplicatedMovement`
  (Location/Rotation). The host is the only physics simulation of the car.
- All mod loops run on the game thread (`LoopInGameThreadWithDelay`, `ExecuteInGameThreadWithDelay`).

### Observations
- exp8: with the client still simulating the replicated car's physics, the car on the client jittered
  (Z 95..280 while the host car was flat) and the passenger-to-car distance on the client ranged 36..699 uu,
  while on the host it was a constant 36 uu.
- exp9: client crash `EXCEPTION_ACCESS_VIOLATION reading address 0x000000000000000d`, call stack entirely inside
  `UE4SS.dll`, a few seconds after the client got its character, before any car code ran on the client.
  The client code on that path was the same as in the passing exp8. Suspected cause: `LoopAsync(16)` loops
  (run on a UE4SS worker thread) touching the Lua state / UObjects while the game thread also ran mod code.
  After moving every loop to the game thread: no crash in exp10 and exp11. Not proven, one run each.
- exp10: making the client's replicated car kinematic stopped it moving on the client (physics replication
  only drives simulating bodies). Following `ReplicatedMovement` by hand fixed it (exp11).
- Gearbox: with `ManualActivate_Gearbox(1)` and throttle the car did not move in 10 s; after
  `ManualActivate_Gearbox(0)` it drove (moved 2335 uu within the next 5 s). The garage start state was 0.
  Derived: `CarGearBoxState` 0 = drive, 1 = park (enum names in the dump are only NewEnumerator0/1).
- `CommandEnterCar` on the character returned without error, but 2.5 s later the host did not possess the car;
  possession came from the `Possess` fallback at 5 s. Whether the real enter sequence (timeline,
  dip to black) just needs longer: unknown.

### Automated test — run "exp11-car4", 300 s, 2026-10-19
```
PASS  client connected to host (serverConn=yes)
PASS  host has 2 PlayerControllers
PASS  client possesses own PDP_MainCharacter (local, role=2)
PASS  client sees host character (role=1)
PASS  host sees remote PDP_MainCharacter
PASS  client has exactly one player car
PASS  client car is the replicated one (role=1)
PASS  client walking moves its character on the host (>=3 distinct positions)
PASS  host movement visible on client (>=2 distinct positions)
PASS  client SEAT command reached host and seated the passenger
PASS  host is driving the car (host possesses car)
PASS  car moved on host > 500 uu (max 3510, mode=throttle)
PASS  host sees remote character attached to the car
PASS  client character attached to the car on the client
PASS  client sees the car move while riding (>=3 distinct car positions, got 24)
PASS  passenger stays with the car on the client (max char-to-car 67 uu < 400)
SUMMARY: 16/16 checks passed
```
History: exp8 14/16 (no host entry, client jitter), exp9 7/16 (client crash in UE4SS.dll), exp10 15/16
(kinematic car frozen on client), exp11 16/16.

### Not verified
- Visuals: passenger pose (no sitting animation is triggered), cameras, how smooth the car looks on the client
  (transform is set per frame from replicated movement, no interpolation), car sounds on the client.
- Real player input for driving (the bot calls the input handlers directly), the proper enter-car sequence,
  getting out of the car (passenger detach is not implemented), more than one passenger.
- Level travel out of the garage, saves, internet play.

## Session 2026-10-19 — Stage 4: map changes (ServerTravel, the game's own travel, re-host, rejoin)

### Tooling
- universal-modder skills installed for the owner (12 skills) and its `um` CLI 0.2.0, pinned to commit
  `6a8865ae171b406f50892c7f46fc5f45655269eb` (`uv tool install git+...@<sha>`), code read before install.
  `um scan <test dir>/client1`: Unreal Engine `UE4+Release-4.27`, no anti-cheat found, loader UE4SS. Matches triage.
  `um kb search "pacific drive"`: no note yet.

### Observations
- How the game changes maps: native C++ in `UBaseLevelManager` (delegates `OnPreTravel`/`OnPostTravel` with a
  `UMapLocation`), route logic in `UBaseRouteState::TravelTo(UBaseLegState*, ERouteEndReason) -> FString`
  (BlueprintCallable + BlueprintNativeEvent, so UE4SS `RegisterHook` sees every call). The actual map load does
  not go through hookable UFunctions: during the game's `QuitToMenu` none of the hooks on `GameplayStatics:OpenLevel`,
  `DrivingGameInstance:PreLoadMap/PostLoadMapWithWorld` or `PlayerController:ClientTravel` fired on the host;
  the host log shows `Browse: /Game/Maps/RunProto/RB_MainMenu` with no `?listen`. Result: the game's own travel
  shuts the listen server down (`World NetDriver shutdown`) and clients get `Host closed the connection`.
- Host `servertravel /Game/Maps/Wilderness/Forest/Wilderness_Forest_01` from RB_Garage: the client receives
  `ClientTravelInternal("/Game/Maps/Wilderness/Forest/Wilderness_Forest_01?listen", TRAVEL_Relative, false)`.
  exp12: client `ConnectionTimeout` after 20 s while the host loaded the zone (19.2 s, started 4 s late).
  exp13: client followed, got its own character there, 14/14 checks (host load 14.5 s that time, so whether the
  timeout change mattered is unknown).
- Setting `InitialConnectTimeout`/`ConnectionTimeout` on the IpNetDriver/NetDriver CDOs and on the live pending
  driver right after `open` does not change the pending-connect threshold: still `Threshold: 20` (exp15, exp16).
  Cause unknown. Retrying the `open` every 30 s works instead.
- Host crash, exp14: game's `QuitToMenu` from RB_Garage with a second `PDP_MainCharacter_C` present →
  `EXCEPTION_ACCESS_VIOLATION reading address 0x20` in game code right after `World NetDriver shutdown` during
  `BeginTearingDown for /Game/Maps/RunProto/RB_Garage`. With a pre-hook on `BaseSaveGameManager:QuitToMenu`
  that unpossesses and destroys remote players' characters first: no crash (exp15, exp16).
- `BaseSaveGameManager.UserNewGame(5, STORY)` (on `BP_SaveGameManager_C`) travels natively to
  `/Game/Maps/Narrative/Narrative_Forest_OlympicOpening_Sentry_01/...`. Saves go to the instance's own `Saved/`
  under `-NotInstalled`; the exe has no Steam Remote Storage calls (no `SteamRemoteStorage` strings).

### What the mod does now
- Host "re-host": if the host lands standalone in a gameplay map after having had clients, it runs
  `servertravel <same map>?listen` (one extra load).
- Pre-hooks on `QuitToMenu` and `BaseRouteState:TravelTo` remove remote players' characters before native travel.
- Client "rejoin": after dropping from a gameplay map to the menu it retries `open <host>` every 30 s until it is
  in a gameplay map again.
- Spawn rule (owner's requirement): a joining or re-joining player is always spawned next to what the host
  controls now (250 uu beside the host character, 320 uu beside the car), never at a saved position, a
  player start or the garage. If the host is driving, the new player is seated as a passenger right away
  (not tested yet).
- Per-map state of the mod resets on every map change.

### Automated test — run "exp16-gametravel3", 480 s
```
PASS  client connected to host (serverConn=yes)
PASS  host has 2 PlayerControllers
PASS  client possesses own PDP_MainCharacter (local, role=2)
PASS  client sees host character (role=1)
PASS  host sees remote PDP_MainCharacter
PASS  client has exactly one player car
PASS  client car is the replicated one (role=1)
PASS  game's own UserNewGame travelled the host to a gameplay map (Narrative_Forest_OlympicOpening_Sentry_01)
PASS  host re-hosted that map with ?listen
PASS  client rejoined the host in the new map
PASS  client has its own character there (local, role=2)
PASS  re-joined player spawned next to the host (first distance 250 uu < 800)
```
The two walking checks failed in that run because this scenario leaves the garage after ~20 s; they are marked
SKIP for `gametravel` in tools/run_test.ps1 from now on. Client rejoined after 2 tries.

### Not tested
- A real run travel (garage gateway → zone → zone → garage) triggered by gameplay; `TravelTo` hook has not fired yet.
- Seating a re-joined player directly into the car when the host is driving.
- Cost of the re-host double load on long zone maps; whether reloading a run map breaks run state.
- Anything visual.

### Car regression after the travel changes
- exp17 (14/16): the passenger rode along on the client at a constant 16506 uu from the car. The client's local
  re-seat (detach, teleport to seat socket, re-attach KeepWorld) read the car at (-15233,-9001,9669) in the frame
  where its chassis was switched to kinematic, so the attach offset was wrong. Removed the local re-seat; the
  client keeps the server's replicated attachment and only disables its movement and the car's physics.
- exp18 "car", 300 s: **16/16 PASS**, passenger-to-car distance on the client 83 then a constant 67 uu,
  car driven by throttle (max 3241 uu from start).

### Rejoin while the host is driving (owner requirement: a re-joining player appears next to the host)
- Scenario `rejoincar`: the client rides as passenger, disconnects itself (`disconnect`) after 40 s of riding,
  rejoins via the retry loop; the host spawns the new character 320 uu beside the car it is driving and seats
  it straight away.
- exp19 (19/21): one client sample at the seat moment had the kinematic car at a bogus position (Z 2845);
  fixed by putting the car on `ReplicatedMovement` in the same frame as the kinematic switch. The car later
  stopped on the host; exp20 diagnostics (`chassisSim=true awake=false`, stuck at the garage's far wall)
  show this is the test bot pushing the car into a wall until its body sleeps, not a co-op issue.
  The dropped passenger's character leaves the car's attached actors on logout.
- exp20 "rejoincar", 420 s: **21/21 PASS**:
```
PASS  client dropped out on purpose while riding
PASS  client rejoined the host in RB_Garage
PASS  host seated the re-joined player straight into the driven car
PASS  after rejoin the client rides in the car (39 samples, 17 car positions)
PASS  after rejoin the passenger stays with the car (max 69 uu < 400)
(+ the 16 car checks, all PASS; max passenger-to-car distance before the drop 70 uu)
```
- Host log: `SPAWNED ... at -3367,-1580,207 next to BP_PlayerCarNew_C (-3210,-1858,147)` then
  `SPAWN host is driving: seating ... as passenger`.

## Session 2026-10-19 — Stage 5: playable build, own repo

- Mod repository (MIT, no game files): https://github.com/BroZYTnikkkk/pacific-drive-coop (v0.1, commit e645cbf).
  `um publish check` against the clean Steam install: `PASS: 9 files, 0 failures, 0 warnings`
  (against the test copy it flagged the mod itself as a "game file", because the test copy has the mod installed).
- New `play` scenario (default): no test bots. Keys: host F8 = host the current map; client F8 = connect,
  F6 = sit in the car, F7 = get out. **The key bindings were not pressed in any test**; the tests run the same
  actions from bots. exp23 smoke run in `play`: both instances load the mod, no bot actions, no Lua errors.
- Get out of the car: client sends `UNSEAT`; host detaches the character next to the car and sets walking.
- Command channel fix: `PlayerState:SetPlayerName` did not clear the command name (exp21: every command ran again
  every 5 s); the host now acts once per distinct `PDCOOP:<cmd>:<seq>` string per controller.
- Client applies the server's `AttachmentReplication` offset in the frame the ride starts (exp21 had one sample
  with the passenger at a bogus position at attach time).
- exp22 "rejoincar", 480 s: **24/24 PASS** (car 16 + rejoin 5 + get out 3: host detached the passenger on UNSEAT,
  client left the car and walks again, its character moves on the host in 5 positions).

### Correction (2026-10-19): exp13 also crashed the host
- Three `CrashReportClient` windows were still open on the owner's screen after the runs. Crash contexts:
  client2 08:52 `EXCEPTION_ACCESS_VIOLATION reading address 0x000000000000000d` (exp9, UE4SS worker-thread loops);
  client1 09:59 `... 0x0000000000000020` (exp14, QuitToMenu from RB_Garage); client1 09:56 `... 0x0000000000000020`,
  i.e. **exp13 crashed the host on QuitToMenu from Wilderness_Forest_01 as well**. Earlier text saying the zone
  QuitToMenu "worked" is wrong: the test harness did not look for crashes after the checks it had.
- Same address as exp14, so the cause is most likely the same (a second PDP_MainCharacter during world teardown);
  no crash reporter appeared in exp15/exp16 with the pre-travel cleanup.
- tools/run_test.ps1 now records crash folders created during the run, closes the test copies'
  CrashReportClient processes by PID (nothing is sent), keeps the dumps under results/<run>/ and fails a
  "no game crash" check.

### Owner report: "start of the game, two cars inside each other" (v0.2, mod repo commit d878523)
- The new-game intro uses another car class, `BP_PlayerCar_Intro_C` (both derive from `ABaseNewCar`); the
  client's duplicate filter only knew `BP_PlayerCarNew_C`. Survey in exp25: `CLIENT-LOCAL REPLICATED ACTORS: BP_PlayerCar_Intro_C=1`,
  client had role 3 at -59029,64602 and role 1 at -58942,64602. Fix: all car logic uses `FindAllOf("BaseNewCar")`
  (UE4SS FindAllOf includes subclasses) and `IsA(/Script/PenDriverPro.BaseNewCar)`; a local copy is removed only if
  the host replicates the same class. exp26: duplicate removed, 1 car on the client.
- Same map: the intro starts with the player seated; after possession the game put player 2 into the driver's
  seat on top of the host (host-side distance 0 uu, exp26), although the mod had seated it as passenger.
  The game takes the seat from `PDP_MainCharacter_C.GetCarAttachTransformForCharacter(out FTransform)` (used by
  `EnterCarTimeline`), and asks for it every frame while seated. A UE4SS post-hook on that Blueprint function that
  moves the out transform 70 uu to the car's right for player 2 works (`transformParam:set()` on the out param
  changes what the game uses). exp27: player 2 at 70 uu from the host, 15/15; a host-side keeper (re-seat when
  player 2 is within 40 uu of the host while the host is in a car) never fired there; in exp28 it fired once
  while the host was getting into the car.
- Also new: tools/run_test.ps1 fails a "no game crash" check (exp24 caught a client crash
  `Runnable thread RHIThread crashed`, `EXCEPTION_ACCESS_VIOLATION 0x000001daef0c67d0`, call stack in game code
  while loading the main menu after the host left; not seen in exp25-exp28; cause unknown).
- exp27 gametravel 15/15 (2 n/a); exp28 rejoincar 24/25 as printed; the one FAIL was the test's own pattern
  (log text changed to "SPAWN host is in <car>: seating"); the host log shows the event, so 25/25 with the fixed pattern.
