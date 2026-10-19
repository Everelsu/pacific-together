# Client-local actor survey (spike X3)

2026-10-19. Every actor of the current world on both sides, grouped by class, `Role`, `bReplicates`, loaded from the
map file (`RF_WasLoaded`) and owner class. Scenario `travel` (garage) and `zonejoin` (Wilderness_Forest_01) in
`test/PacificTogetherTest/Scripts/main.lua` (`survey()`), 20 s after the client joined; the runner writes
`actors-<tag>.csv` with host and client counts side by side.

Sources: `local/test-results/20261019-164906-travel/actors-garage.csv` (host 554 actors, client 472),
`local/test-results/20261019-170906-zonejoin/actors-zone.csv` (host 1480, client 508). The client is a spectator
(`bStartPlayersAsSpectators`), no character of its own.

## How to read Role on the client

- Role 1/2 (SimulatedProxy/AutonomousProxy) = arrived by replication from the host.
- Role 0 (None) + loaded = placed in the map file and not replicated (the client swaps roles of loaded actors). Same
  object exists on the host as Role 3. Static map content; not a duplicate problem by itself.
- Role 3 (Authority) + not loaded = **spawned at runtime by the client's own game code**. These are the ones to look at.

## Classification

a = replicated from host (fine). b = client-local copy of an actor the host replicates. c = spawned locally on the
client, and the host spawns its own copy (authority-gating candidates). d = client-only (UI, camera, per-player engine
actors). Counts are host / client.

### Garage (RB_Garage)

| Cat | Classes | Host / client | Note |
|---|---|---|---|
| a | `PDP_MainCharacter_C` (host's), `BP_PlayerController_MainCharacter_C` (own, role 2), `PlayerState` x2, `GameStateBase`, `WorldSettings`, `DrivingWorldSettings`, `RB_Garage_C` | 1/1 ... | Stock replication works |
| b | `BP_PlayerCarNew_C` | 1 / 2 (one role 1 replicated, one role 3 local) | The known duplicate car |
| b (follows from the car) | every car part actor: `BP_CarPart_*` (53 `BP_CarPart_Interactive_C`, doors, wheels, engine, battery, radio, ...), `BP_Attach_*`, `BP_Panel_Base_C`, `BP_Internal_Radbox_01_C`, `BP_Internal_Windshield_C`, `BP_Manifestation_*`, `BP_PlayerCar_Computer_C`, `BP_PlayerCar_Compass_Simple_C`, `BP_Dash_CarFriend_C`, `BP_Storage_Trunk_Base_C` | 1 / 2 each (e.g. 53/106) | Not replicated (role 3 on the client). The client builds one full part set for its local car and one for the replicated car. Car state (C3-C6) cannot come from these actors on the client |
| c | garage stations: `BP_Garage_*` (CraftingTable, InventingBench, PartShredder, GasPump, CarRepairer, BatteryCharger, StarterStorage x2, InventoryExpansion x4, InventoryParts x4, LuckyJunkHeap, IncidentBoard, EmergencyProtocol, GatewayExit, ZoneScanner, ...), `BP_Garage_Cosmetic_FramedMount_C` x30, `BP_RunPlanner_MapTable_2_C`, `BP_RunGenerationReroll_01_C`, `BP_Fig_Station_LuckyJunkHeapInformer_C` | 1 / 1 each | Not replicated; both sides run their own. Storage containers here hold the host's items on the host only (G1, G2) |
| c | quest actors `BP_Fig_Mission_Chapter01/03/05/06/09/11/13/15/17/20_C` | 1 / 1 each | Spawned by `AEntitlementSpawner` on both sides (both log `AEntitlementSpawner::SpawnActor failed to load class .../BP_Fig_Mission_Chapter08`). Story state on the guest is its own (G3) |
| c | `BP_WorldItem_Resource_GasPumpHandle_C`, `BP_Destruct_Road_Sign_Stop_01_C`, `BP_SplineCableController_C`, `BP_VolCascade_Radiation_C` (1 / 41), `PrefabSettingsActor`, `ManageChildrenActor` (39 / 1), road-frame and PFX intersection actors | | Mixed; pickup handle is gameplay, the rest visual |
| d | `SpectatorPawn`, `PlayerController` (no class), `PlayerCameraManager`, `CameraActor`, `PDP_Game_Hud_C`, `ParticleEventManager`, `DefaultPhysicsVolume`, `AbstractNavData` | | Per-player engine actors, fine |
| host only | roadside destructibles (`BP_Destruct_*` cones, signs, barricades), `BP_Spawner_Car_Civ_C`, `BP_Spawner_Car_Stripped_C`, `BP_Spawner_Site_Open_Container_*`, `BP_Template_CivCar_01_C`, `BP_Template_StrippedCar_01_C`, `BP_Template_GasTruck_C` + their `BP_TemplatePart_*`, `BP_WorldItem_C` x2, `BP_GameplayEventItem_World_C` x2, `BP_Hazard_Landmine_C`, `BP_DrivingGameMode_C`, `GameSession`, `GameNetworkManager` | n / 0 | The client has none of these at survey time (see unknowns) |

### Zone (Wilderness_Forest_01)

| Cat | Classes | Host / client | Note |
|---|---|---|---|
| a | own PC (role 2), `PlayerState` x2, `GameStateBase`, `WorldSettings`, `DrivingWorldSettings`, `Wilderness_Forest_01_C` | | The host's character and car are **not** on the client in this run (host 1 / client 0), see unknowns |
| c | lootables `BP_Lootable_Backpack_Civilian_C` 3/3, `BP_Lootable_CoolingBox_01_C` 3/3, `BP_Spawn_Resource_ElectronicDevice_Radio_C` 2/2, `BP_SpawnPoint_C` 23/23, `BP_LeafSpawner_C` 3/3 | | **W1/W2 candidates**: loot containers exist separately on each side |
| c | destructible props `BP_Destruct_ChainFence_Large_01_C` 36/36, benches, chairs, trash bags, grill, shopping cart (1/3), barrels (6/4); `BP_Prop_FacilityStreetLight_C` 8/8, trees/shrubs `BP_IF_*`, `BP_Tree_Multi_C`, vista tiles, `DecalActor`, `StaticMeshActor` 138/98 | | Counts differ for some (client spawned more or fewer): local randomisation or streaming |
| c | `BP_VolCascade_Radiation_C` 145 / 4 | | Radiation volumes, host-heavy |
| d | `BP_ItemSpawner_C` 0 / 3 | | Item spawners on the client only (host's have presumably run and gone); candidate for gating |
| d | `SpectatorPawn`, cameras, HUD, `ParticleEventManager` | | fine |
| host only | the whole run spawn pass: `BP_Spawner_Car_Civ/Gov/Stripped_C`, template cars and parts, `BP_Spawn_GasBarrel_C` x96, `BP_Spawn_Resource_ReactiveLockbox_*`, `BP_WorldItem_ReactiveLockbox_Base_C` x5, `BP_WorldItem_C` x3, `BP_Hazard_RadiatedZone_*` (~140), `BP_LevelTransition_ExitPortal_C` x2, `BP_CarSpawnpoint_C`, `SpawnModifierActor` x14, the host's car and its parts | n / 0 | Host log has 63 `LogSpawnExecutor` lines, client 0: the procedural run spawn ran on the host only |

### Zone redo with the guest's character next to the host (spike X2)

Scenario `x2zone` (`scenarios/x2.lua`): the host opens `Wilderness_Forest_01?listen`, spawns and possesses a
`PDP_MainCharacter_C` for the guest 150 uu from its own, survey 25 s later. Source:
`local/test-results/20261019-194408-laneB-x2zone/actors-zone.csv` (host 1618 actors, client 633); same picture in
`20261019-195159-laneB-x2zone`. Per-actor names and spots: `PT|id` / `PT|iddiff` lines in the run's `*-UE4SS.log`.

| Cat | Classes | Host / client | Note |
|---|---|---|---|
| a | host's `PDP_MainCharacter_C` (role 1), own character (role 2), `BP_PlayerCarNew_C` (role 1), `PlayerState` x2 | | With a character nearby the host's character and car now arrive (the X3 run had neither: relevancy) |
| b | the car's part actors, e.g. `BP_CarPart_Interactive_C` 53 / 53, `BP_Storage_Trunk_Base_C` 1 / 1 | | One set on the client (no local car in a zone, unlike the garage); not replicated, built locally for the replicated car |
| c, own roll | `BP_Lootable_Backpack_Civilian_C` 3/3, `BP_Lootable_CoolingBox_01_C` 4/3, `BP_Spawn_Resource_ElectronicDevice_Radio_C` 2/2, `BP_SpawnPoint_C` 23/23, `BP_LeafSpawner_C` 3/3, `PrefabSettingsActor` 23/7, `ManageChildrenActor` 112/24 | | **Not the same objects.** Spawn points are level content (same 23 on both), but each side picks its own variants and spots: of the lootables only 1 per class has the same name and spot (`BP_Lootable_CoolingBox_40`, `BP_Lootable_Backpack_Civilian_0`), the others are metres to tens of metres apart, and the contents differ even for the matching ones (e.g. host `CoolingBox_40` = Plastic, Food; client = Food, Battery x2, Food) |
| d | `BP_ItemSpawner_C` 0 / 3 | | Client only, sitting where the host has world items (`BP_ItemSpawner5` at -12639,-41152 = a host `BP_WorldItem_C`) |
| host only | run spawn pass products: lootable crates (`BP_Lootable_Crate_*` 4), `BP_Container_*`, `BP_Spawner_Site_Open_Container_*`, template cars 16 + 120 `BP_TemplatePart_*`, `BP_Spawn_GasBarrel_C` 97, reactive lockboxes, light-array resources, `BP_WorldItem_*` 8, `BP_Hazard_RadiatedZone_*` 138, `BP_Hazard_Landmine_C` 2, `BP_LevelTransition_ExitPortal_C` 2, `SpawnModifierActor` (spawned) 14 | n / 0 | Confirmed with the guest next to the host: these are not hidden by relevancy, they do not exist on the client (`LogSpawnExecutor` 62 lines host, 0 client) |
| loaded | 181 level-placed actors (foliage structures, road endings, site spawners `BP_Spawner_Site_Closed_*`, vista, landscape) | same path | Same full path and spot on both sides. 3 `BP_ClumpedArea_Residental_PrePlaced_C` are on the client only (the host's spawn pass consumes them) |

## Spawners seen in logs

- `AEntitlementSpawner` (`LogEntitlementSpawner`): runs on both sides in the garage (both fail on Chapter08).
- `WB.Modifiers.Spawning.Vehicles.Car.Stripped.MaxCount` tag errors: host in the zone (spawn pass), client in the
  garage for the map's `BP_Template_StrippedCar_BehindGarage`/`_UnderBridge` cars. No `BP_Template_*` actor was left
  on the client 20 s later.
- `LogSpawnExecutor` (SC2_* spawn passes): host only, zone only.

## Unknowns

- ~~Streaming and relevancy~~: answered by the zone redo above; the "host only" rows hold with the guest's
  character next to the host.
- ~~Whether the client's copies of loot containers roll their own contents~~: they do (zone redo).
- Whether client-only `BP_ItemSpawner_C` spawn items later.
- The zone was opened directly (`open ...?listen`), not reached through a run (route, junction state); a real run
  may spawn more (anchors were absent).
- Category "c" includes harmless visual actors; which of them matter needs X2/X4.
