# Game atlas: map of Pacific Drive's systems for co-op work

Built 2026-10-20 from the game paks (build 21896301), the UE4SS dumps and a Blueprint bytecode lister. The atlas itself
is game-derived and lives only in git-ignored `local/atlas/`; this page is our own map into it. Names are the in-game
class names without the UE prefix (`DrivingGameInstance`, not `UDrivingGameInstance`; Blueprint classes without `_C`).
Read-only research: nothing here was verified in a running game.

## How to use the atlas

- `local/atlas/bp/<Asset>.txt`: linear bytecode listing of one Blueprint (every function, with flags and byte size).
  Offsets are in-memory offsets. The event graph is `ExecuteUbergraph_<Class>`; event stubs only jump into it.
  Custom events and replicated events are separate functions.
- `local/atlas/index/*.tsv` (tab separated, header on line 1): `classes` (class, parent, asset, module), `functions`
  (BP class, function, flags, bytes, overridden parent function, asset), `native_functions` (C++ game-module functions
  with UFUNCTION flags and params), `calls` (caller -> callee, native calls included), `properties` (class, property,
  type; all classes including engine).
- `python -I local/atlas/xref.py callers SaveGame` (any class) | `callers BaseSaveGameManager.SaveGame` |
  `callees BP_ProgressionManager.TravelToGarage` (or just a class) | `class BP_CarManager` (chain, children, props,
  functions) | `find Storm`.
- Gotchas: `?.Name` in `calls` is a virtual call by name whose class could not be resolved (usually an engine function
  or a call on another object); `callers` matches those by name. The class of a native callee is the declaring class.
  Rebuild (needs the paks and the dumps): `local/atlas/tools/` `pk.py headers`, `scan.py`, `pk.py uexp want.txt`,
  `build.py`, `mkindex.py`; `_ex/` is the extraction cache.
- Listing failures: none. Not listed: 1020 class-only assets, non-Blueprint assets, `.umap` level scripts
  (see `local/atlas/failures.txt`).

## Architecture in one paragraph

`DrivingGameInstance` (C++, module PenDriverPro) owns `InventorySystem`, `MessageSystem`, `DebugManager` and two lists:
`ActiveManagers` (looked up by class in `ManagerLookup`) and `ActiveDirectors`. Managers derive `BaseManager` with the
hooks `K2_Initialize/PostInitialize/PostBeginPlay/PreLevelChange/PostLevelChange/Tick/Shutdown`; each is a C++
`Base*Manager` with a Blueprint subclass in `/Game/Systems/Managers/`. Directors (`BaseDirector`, same hooks) are small
rule objects in `/Game/Systems/Directors/` (autosave, hazards, quests, tutorials, time of day). Gameplay code talks
through manager multicast delegates (`OnPlayerStartEnterCar`, `OnPartBroken`, ...), which are the natural co-op hooks.
The game instance also holds `MasterSeed` (`RollMasterSeed`, `SetMasterSeed`), `CurrentGameplayState`, `bIsInGarage`.

## Systems (key classes, what to hook or call)

| System | Classes | Hook or call |
|---|---|---|
| Save | `BaseSaveGameManager` < `BP_SaveGameManager`; `BP_AutoSaveDirector` | `SaveGame`, `LoadGame`, `SaveCheckpoint`, `LoadFromCheckpoint`, `UserNewGame/UserLoadGame`, `SetCurrentSlot`, `GatherMetadata`, `MakeBookmark`; BP `LoadOrCreateGame`, `ShouldLoadTransforms`; `TriggerAutosave`, `CanAutoSave`. Managers persist via `K2_DataBlockPostLoad/PostSave` and `OnPreGatherSaveState`. |
| Car | `BaseCarManager` < `BP_CarManager`; pawn `BaseNewCar` < `BP_PlayerCarNew` (also `BP_PlayerCar_Intro`); module IWCarPhysics | `GetCarActor`, `GetCarSoul`, `GetEquipmentSlots`, `GetItemInstanceEquippedInSlot`, `Damage Car Equipment by Health Type`, `Set/Get PlayerCarState`, `Set/GetDoorState`, `SetCarLightsOn`, `TeleportWithTransform`, `FlipCar`; pawn input handlers (`AccelerateBrake`, `SteerLeftRight`, `Handbrake`, `Interact`, `OpenInventory`). Delegates `OnCarIgnitionChanged`, `OnCarGearboxChanged`, `OnDoorChanged`, `OnPartBroken`, `OnTrunkUsed`. |
| Car parts | `BP_Manifestation_CarEquipment*` (`BP_CarPart_Door_Base`, `_Wheel_Base`, `_Headlight_Base`, `_Bumper_Base`, `_FuelTank_Base`, `_LimBattery_Base`, `_Panel_*`), `BaseCarPartInteractive`, `BP_ItemUpgrade_CarPart`, `CarEquipment_SlotData` | A part is an `ItemInstance` in a car equipment slot, shown by an actor manifestation; health sits in item properties and `HealthComponentBase`. Assets under `/Game/Gameplay/Inventory/Items/Car/*`. |
| Player | `BaseCharacterManager` < `BP_MainCharacterManager`; pawn `BaseCharacter` < `PDP_MainCharacter` (ALS locomotion); `BasePlayerController` < `BP_PlayerController_MainCharacter` | `GetCharacterActor`, `GetActiveItem/SetActiveItem`, `PlayerEyeTrace`, `IsPlayerAlive/SetPlayerAlive`, `CommandEnterCar/ExitCar`; pawn `SafeTeleport`, `BPI_TeleportPlayer`, `BPI_HandleDeath`, `Interact_WorldInteraction`; delegates `OnPlayerSpawned`, `OnPlayerDeath`, `OnPlayerStartEnterCar`. |
| Inventory | `InventorySystem`, `BaseInventoryManager` < `BP_InventoryManager`; `ItemContainer`, `ItemSlot`, `ItemInstance`, `ItemArchetype`, `ItemContainerComponent`, `HotbarContainer`; module PenDriverInventory | `GiveItemToPlayer/Car`, `AddToContainer(s)`, `GetPlayerInventory`, `GetCarInventories`, `FindOwnedItem`, `RemoveInstance`; `ItemContainer.AddItem/RemoveItem/StartTransaction`, `ItemSlot.Transfer*`, `InventorySystem.SpawnItemActor`, `FindActorForItemInstance`, `ItemInstance.Duplicate`; delegates `OnItemPickedUp`, `OnItemDragPlaced`, `OnContainerFull`. |
| Loot, containers | `BaseItemSpawner` < `BP_ItemSpawner`, `BP_Container_Large`, `BP_InventoryContainerComponent(_ExternalInventory)`, `BP_ExtraCarItemContainer`, `BaseSiteSpawnerActor` / `BP_Spawner_Site_*`, `BaseLeafSpawner*`, `ItemRetentionSystem` | World loot is placed by the spawning pass; `BaseInventoryManager.SaveWorldItemsToState/LoadWorldItemsFromState` serialise world items; `BindItemInstanceToSpawningActor`. |
| Spawning, seed | `BaseSpawningManager` < `BP_SpawningManager`, `BaseRandomManager`, `BaseChartManager`, `ISpawn*` interfaces | `Execute Spawn Leafs`, `PickEntrance/PickExit`, `FinishAndSpawnPlayer`, `GetCurrentSeed`; delegates `SpawningComplete`, `LoadingFinished`. Determinism rests on `DrivingGameInstance.MasterSeed` plus route `GetWorldShapeRandSeed`. |
| Progression, route | `BaseProgressionManager` < `BP_ProgressionManager`; `BaseRouteState` < `BP_RouteState(_Expedition)`; `BaseLegState` < `BP_LegState*`; `BP_Garage_RouteTuner` | `TravelToGarage`, `Open Map UI`, `Construct Routes`, `BeginPlanning/Generation/Explore/IdlePhase`, `TravelTo`, `GetRevealedLegs`, `DoFailedRunPenalties`, `SpawnTombstone`, `ScanObject`; delegates `OnRunStarted/OnRunEnded/OnRouteSelected`. |
| Travel, maps | `BP_LevelTransition_*` (`/Game/Gameplay/LevelTransitions`), `BP_ExitPortalSpawn`, `BaseLevelManager` < `BP_LevelManager`; `DrivingGameInstance.PreLoadMap/PostLoadMapWithWorld/RestartLevel` | `K2_PreLevelChange/PostLevelChange` on every manager is the level-change hook; transitions are actors in the level (enter/exit, exit portal); `GetGarageMap`, `GetOpeningDriveMap`. |
| Storm | `BP_StormManager`, `BP_ZoneStormRoyale` | `SpawnInstabilityStorm`, `SpawnRoyaleStorm`, `SpawnExitTriggeredStorm`, `IsPlayerInsideStorm/IsCarInsideStorm`, `GetInstabilityTollerance`, `ClearInstability`; delegates `OnGatewayOpened`, `OnInstabilityStormStateChange`, `OnExitPortalSelected`. |
| Status effects, quirks | `BaseStatusEffectManager` < `BP_StatusEffectManager`, `StatusEffect`, `ItemUpgrade`, `BaseQuirkPart/Element` | `AddItemStatusEffect`, `RemoveStatusEffect`, `GetStatusEffects(ByTag/ByClass)`, `CanAdd`, `K2_OnStatusEffectAdded/Removed`. |
| Anomalies, hazards | `BP_HazardManager`, `BP_HazardDirector`, `BP_Base_Hazard(_WorldItem)`, `BP_Hazard_Leech/PartStealer/PhysicsGrabber/...`, `BP_HazardProperty_*`, `AC_Hazard*` | `BP_Base_Hazard.HazardDealDamage`, `IsPlayerInLOS`, `IsCarInRange`, `GetHazardOnHitType`; manager delegates `OnHazardGrab/Release`, `OnLeechAttachedToCar`, `CauseHazardDisturbance`. Hazards derive from the item world manifestation, so they also show up in inventory code. |
| Quests | `BaseMissionManager` < `BP_QuestManager`, `BP_QuestDirector`, `BPMT_*` mission tasks | `StartMission`, `StartObjective`, `AdvanceObjective`, `ForceCompleteMission`, `K2_GetMissionState`. |
| UI | `BP_UIManager`, `PDP_Game_Hud`, `PDP_PauseMenu`, `UMG_PlayerMenu_{Main,Inventory,Missions,RunMap}`, `UMG_RouteDisplay_Main`, `UMG_SaveLoad_Menu`, `UMG_MainMenu` | `SetPauseMenuOpened_Impl`, `SetMapViewActor`; `BP_SaveGameManager.Open Save Load Game Menu`; inventory via `BP_InventoryManager.OpenPlayerInventory/OpenCarInventories`. |
| Game mode, input | `BaseDrivingGameMode` < `BP_DrivingGameMode`, `BaseInputManager`, `BP_InputDirector` | The game mode has no native functions; managers are created by the game instance, not the mode. |

## Surprises

- `PDP_MainCharacter` contains server and multicast event stubs (movement, rotation, ragdoll, networked montage) from
  the ALS template; several have no bytecode, so they look like leftover scaffolding rather than game netcode (unverified).
- Most managers carry `DbgActEvt_*` debug functions (force save, load bookmark, spawn hazards, add status effects),
  and `DebugManager` exists: ready-made calls worth trying before writing our own.
- Event graphs compile to one `ExecuteUbergraph_*` function per class, so most Blueprint logic in `calls` is
  attributed there rather than to the named event.
