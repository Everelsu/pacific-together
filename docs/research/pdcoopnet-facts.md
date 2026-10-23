# Facts mined from PDCoopNet (reference/pdcoopnet)

Read-only review, 2026-10-19. LN = `LAB-NOTES.md`, ML = `mod/PDCoopNet/Scripts/main.lua`, RT = `tools/run_test.ps1` (ML and RT
were removed from this repo on 2026-10-23; the facts below stay).
All test results are as their notes report them; none re-run by us.

## Game facts

- UE 4.27.2 (`PenDriverPro-4.27.2-0+++UE4+Release-4.27`); net version `PenDriverPro 1.15.0, EngineNetVer 17, GameNetVer 0` (LN:70, 139).
- Paks `pakchunk0..4-WindowsNoEditor.pak`, v11, unencrypted, Zlib (LN:122).
- Native modules: PenDriverPro, PenDriverInventory, PenDriverUtils, IWCarPhysics, PenDriverDataBlocks, PenDriverUI,
  EntityFramework, DuctTape; plugins SMSystem (Logic Driver), Wwise, Houdini, Sentry (LN:78).
- **Zero replication specifiers in game native code** (LN:83).
- Engine/instance: `DrivingGameEngine`, `/Script/PenDriverPro.DrivingGameInstance`. Menu: `BP_MainMenu_PlayerController_C`, `BP_MainMenuGamemode_C`.
- Gameplay GM `BP_DrivingGameMode_C` (`ABaseDrivingGameMode : AGameModeBase`), `DefaultPawnClass=PDP_MainCharacter_C`,
  **`bStartPlayersAsSpectators=true`** (joiners stay spectators). PCs `ABasePlayerController`.
- Character `PDP_MainCharacter_C` (`ABaseCharacter : ACharacter`, ALS animation).
- Car `ABaseNewCar : ANewVehiclePawn` (IWCarPhysics, not PhysXVehicles); subclasses `BP_PlayerCarNew_C` (garage),
  `BP_PlayerCar_Intro_C` (new-game intro). Members: `Chassis`, `VehicleController` (`ThrottleInput`, `SetParkingBrakeActive`),
  `TempSocket_Seat`, `Highlight_EnterDoor`, `EngineOn`, `ManualSetIgnition_NoAnim`, `ManualActivate_Gearbox`
  (0 = drive, 1 = park), `AccelerateBrake`, `DriveControl` (ML:257-548).
- Managers (`UBaseManager`): `BP_SaveGameManager_C` (SaveGame/LoadGame/SaveCheckpoint/LoadFromCheckpoint/MakeBookmark/QuitToMenu,
  `UserNewGame(5, STORY)`), `BP_CarManager_C` (`NewCarActor`, `CarIgnitionState`, `MyCarGearBox`), `BP_MainCharacterManager_C`
  (single `CharacterActor` ref), `UBaseInventoryManager`.
- Travel: `UBaseLevelManager` delegates `OnPreTravel/OnPostTravel(UMapLocation)`; `UBaseRouteState::TravelTo(UBaseLegState*, ERouteEndReason)`
  BlueprintNativeEvent. The map load itself goes through native `Browse` without `?listen`; no UFunction hook fired
  (OpenLevel, PreLoadMap, PostLoadMapWithWorld, ClientTravel). `TravelTo` hook never fired in tests (LN:304-358).
- Maps: `/Game/Maps/RunProto/RB_MainMenu` (default), `/Game/Maps/RunProto/RB_Garage` (hub),
  `/Game/Maps/Wilderness/Forest/Wilderness_Forest_01`, `/Game/Maps/Narrative/Narrative_Forest_OlympicOpening_Sentry_01/...` (intro).
- DefaultEngine.ini: no NetDriverDefinitions override (IpNetDriver), `bUseSplitscreen=False`.
- Saves: `%LOCALAPPDATA%/PenDriverPro/Saved` (shared with the real install!). `-NotInstalled` moves Config/Logs/saves into
  `<instance>/PenDriverPro/Saved`. No Steam Cloud calls in the exe (LN:92, 117, 325).
- Net: IpNetDriver/NetDriver/DemoNetDriver present; SteamNetDriver, SteamSocketsNetDriver, OnlineSubsystemSteam absent. Port 7777.
  Two instances run side by side; `steam_appid.txt` stops the copy relaunching via Steam.
- Pending-connect threshold 20 s; editing `InitialConnectTimeout/ConnectionTimeout` on CDOs or the live driver did not change it.
  Zone loads 14-19 s (LN:313-318).

## What worked (their evidence)

- Engine listen server: `open <map>?listen` / `open ip:7777`; join + movement replication (exp1, exp2).
- Spawn + possess a `PDP_MainCharacter_C` per remote PC (deferred spawn, `Possess`), then restore the host's
  `CharacterActor` (manager flips to the newest character). Client gets AutonomousProxy with stock prediction (exp7 9/9).
- Client duplicate car: any `BaseNewCar` with role Authority on the client is a local duplicate; `K2_DestroyActor` + hide,
  point `NewCarActor` at the replicated one (exp7, exp26).
- Passenger: host disables movement/collision, attaches to `TempSocket_Seat` (+70 uu right); attachment replicates (exp11, exp18 16/16).
- Client car kinematic: chassis `SetSimulatePhysics(false)`, VehicleController tick off, snap to `ReplicatedMovement` in the same frame (exp11, exp22 24/24).
- Host driving: `Possess(car)` + ignition + gearbox + throttle (exp11).
- Client->host commands via stock reliable RPC `ServerChangeName("PDCOOP:<cmd>:<seq>")`, host reads PlayerState names (exp22).
- `PDP_MainCharacter_C:GetCarAttachTransformForCharacter` post-hook fires every frame while seated; rewriting the out param moves the seat (exp27).
- Pre-travel cleanup (destroy remote characters in QuitToMenu/TravelTo pre-hooks) prevents a host crash (exp15, exp16).
- Re-host after native travel via `servertravel <same map>?listen` (double load); client rejoin loop every 30 s.
- UE4SS Lua: BP delegates can shadow same-named functions, call via `StaticFindObject(class..":"..fn)`; `FindAllOf` includes
  subclasses; treat `PendingKill` objects as gone (they stay findable until GC).

## Failures and crashes

- Host AV at 0x20 during `BeginTearingDown` on QuitToMenu with a second character present (exp13, exp14). Avoided by cleanup.
- Client crash in UE4SS.dll (exp9), suspected `LoopAsync` on a worker thread; all mod code on the game thread since. Not proven.
- Client RHIThread crash loading the menu after the host left (exp24), cause unknown.
- `EnableInput can only be specified on a PlayerController for itself` on every join, unresolved.
- Car on client: physics on = jitter; kinematic without updates = frozen; bad transform at the kinematic switch frame.
- `CommandEnterCar` silently did nothing; only `Possess` worked. Intro car not deduped; player 2 put in the driver seat on top of the host.
- `K2_GetComponentsByClass` return type unusable from Lua.

## Hacks that would not survive real play

- One 5 s polling loop for spawn, commands, dedupe, rejoin, re-host (hooks they wanted did not fire or were not used).
- Commands through player names (Lua cannot add RPCs).
- Test bots inside the shipping mod (role.txt line 3).
- Hardcoded offsets and enum literals; "player 2" assumption.
- Double map loads on every map change (+15-30 s).
- Per-frame car transform set with no interpolation.
- Code-only bugs: `SetReplicateMovement(true)` only called in bot scenarios (play mode may not move the car on the client);
  `rehostedFor` never reset; rejoin loop never stops.

## Not tested / unknown

Visuals (camera, animation, car sounds), interaction and inventory UI for player 2, real driving input and enter/exit
sequence, a real run (gateway -> zones -> garage), loot/inventory/parts/damage/quests/saves sync, internet play,
the play-mode keys, non-replicated client-local actors (loot, props).

## Their harness (ideas worth reusing)

Hardlinked instances + `-NotInstalled`; role file per instance; one machine-parseable status line per tick from both
sides with checks against both views; crash detection via new `Saved\Crashes` folders and closing reporters by PID;
per-run log archive; bot-driven scenarios. Flaws: kills every game process (including a real session), no exit code,
some checks pass trivially, no mutation runs.

## Open questions for our design

1. Keep the listen server alive across native travel (LoadMap hook? redirect to ServerTravel?).
2. Sync model for game state with no replication: loot, inventory, parts, damage, run/route state, saves.
3. Which client-side spawners/Blueprints need authority gating beyond the car.
4. Internet transport (Steam vs VPN) and the 20 s connect timeout.
5. Can player 2 use the game's own interaction, inventory, car entry and camera given single-reference managers?
