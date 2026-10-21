# M5 progression: the guest holds the host's progression (D2, D6)

Shipping code: `mod/PacificTogether/Scripts/progression.lua` (+ `M.flush()` in `backpack.lua`, `"progression"` in `main.lua` FEATURES).
Test: `test/PacificTogetherTest/Scripts/scenarios/progsync.lua`, mutation `noprog`. Pair `C:\PTLanes\prog`, port 7941, headless.

## Verdicts

| Question | Verdict |
|---|---|
| Guest managers show the host's garage upgrades, stations, story flags, route legs, unlocks, logbook | Works for the sets below: `-Fixture zone`, a fresh-menu guest joins; after the handshake its values equal the host's (`progsync`, see results). `-Mutate noprog` fails 8 checks. |
| Later changes on the host | Work: a whiteboard tag and a research node unlocked on the host reach the guest within about 2 s. |
| Run-failure penalty on the guest's backpack (D6) | Works for the call the game makes: the host's `RemoveItemsPenalty` is hooked, the guest rolls the same removal on its backpack and hand and tells the host's record at once (`g.bp.save`). |

## Why not a save in memory (candidate a)

The game's save is its own container, not a `USaveGame`: file header `SAVC` with chunks `OPTS`, `META`, `GAME`, `CHKP` and a
per-object "data block" serializer (`PenDriverDataBlocks`: `IDataBlockHandler.K2_HandleDataBlock(UNativeDataValue, UDataSerializeContext)`,
`K2_DataBlockPostLoad`). `UGameplayStatics.SaveGameToMemory` has nothing to serialize. `BaseSaveGameManager.LoadGame/Rinse` read the slot
file and load the map, so they cannot be used without touching disk and travelling. So candidate (b): send the state sets and write them
with the managers' own setters.

## What is synced (all in memory; the guest's saves stay blocked by safety.lua)

| Section | Host reads | Guest writes |
|---|---|---|
| `wb` | `BP_ProgressionManager_C.GlobalWhiteboard.Entries` (tag=float). It holds `WB.GarageUpgrades.*` (stations and garage installs), `WB.Quests.*`, `WB.Missions.*`, `WB.Scanning.*`, `WB.Statistics.*`, `WB.Accessibility.*`, `WB.WorldState.DLC/FIG/Garage.*`. | `SetTagFloat` for tags that differ. Skipped: `WB.WorldState.TimeOfDay` (world.lua), `WB.Statistics.Fuel.Spent` (changes every frame). |
| `un` | `BaseGenericGraphState` (`BP_InventionUnlockState_C`, the recipe/research/blueprint graph `RecipeResearchGraph`): `UnlockedNodes`, `PurchasedNodes` by asset path. | `UnlockNode(node, true)` (events suppressed), `MarkAsPurchased`. Never removes. |
| `rt` | `BaseProgressionManager.WorldState` (`UBaseRouteState`): `CurrentPhase`, `CurrentLeg`, per leg in `LegStates` (keyed by `RouteShapeLeg_N`): `RevealState`, `Visited`, `Discovered`, `Active`. Only legs that are revealed, visited or discovered are sent. | The fields set directly on the guest's own leg states (same leg names on both sides: the shape asset `/Game/Systems/Routes/V2/WorldShape` is the same). |
| `lb` | `ProgressionManager.LogBook.Entries[].DataObject` (item archetypes the player knows, 19-20 in the fixtures) | `LogBook:AddEntry(object)` for the ones missing. |

Sections go out as `g.prog.wb|un|rt|lb`, `;`-separated, chunked at 28 000 characters (cap is 32 KB; nothing raised in msg.cpp). The host
sends everything to a guest on its `g.prog.hi` (the guest asks every 3 s until an answer, and again after every map load) and pushes
a section to all guests when its content changed (check every 2 s).

## Run failure (D6)

`BP_ProgressionManager_C:RemoveItemsPenalty(InPenaltyMode, out LostItems)` is the one place all failure paths use: the failed-run branch of the
ProgressionManager ubergraph (right before `DoFailedRunPenalties` and `TravelToGarage(2|3)`), `BP_MainCharacterManager.KillPlayer`, the tombstone lootable and
the pause menu's abandon run. It resolves `-1` to `DrivingGameUserSettings.HardcoreMode` (an expedition forces 1), then for the player backpack, the
hand and the trunk calls `BFL_ItemPropertyUtilityFns.RemoveRandomItems(container, retention, keepCrafted, mode, ...)`: mode 0 retention from
`RetentionPlayerInv` (tuning `WB.Tuning.Tombstone.ContainerRetention.PlayerInv`, 0.0 in this build), 1 keep all, 2 lose all, 3 as 0 but keep crafted;
1 and 3 keep crafted items. The host's hook (pre) resolves the mode and sends it (`g.prog.pen`); the guest calls `RemoveRandomItems` on
`Inventory_Player` and `Inventory_PlayerHand` with its own retention value. The trunk and car containers are the host's, so they are not touched twice.
After the removal the guest calls `backpack.flush()` so the host's stored record (`odsave<slot>.pt-<guest>.txt`) matches before any travel.
Scenario proof: guest 10 -> 0 items, host file 0 items (`host_file_matches_guest_after_penalty`).

## Observations

- The fresh guest (main menu) and the garage fixture host have the same 47 unlocked research nodes (the default set), the same 67 route leg names,
  and 34 vs 0 whiteboard tags (the guest has no `WB.GarageUpgrades.*`, no quests). The route state's seed differs (`WorldShapeRandSeed`), the shape does not.
- `RegisterHook` on the Blueprint function at mod load did not take (path not found before the class is loaded); it is registered from the host loop
  once a ProgressionManager exists (`PT|prog penalty hook registered`).
- `WB.Statistics.Fuel.Spent` moves every 100 ms while the car idles: it flooded the first run with one set per push, now skipped.

## Derived

- `UBaseProgressionManager.GlobalWhiteboard` is the central flag store: garage station installs (`WB.GarageUpgrades.*`) are tags, not actors.
- Leg `MapLocation`/`LegInstance` are null in the fixtures' states (the legs are not resolved before the first selection), so they are not synced.

## Guesses

- Setting `UBaseLegState` fields directly does not fire `OnLegRevealed`/`OnLegStateChanged`; a map UI that is already open shows the old values until it is reopened.
- Garage stations that spawn from a whiteboard tag change might spawn on the guest when the tags arrive (the host's garage actors come from the host); no duplicate was looked for.

## Unknowns / known gaps

- Car paint, detailing and cosmetics: cosmetics are items (`DbgActEvt_GiveAllCosmetics`), installed paint lives on the host's car parts: they come with car.lua's part sync, not with progression.lua. Not checked.
- Quest/mission objects (`BP_QuestManager`, `MissionObjective` state beyond the `WB.Missions.*` / `WB.Quests.*` tags), the NUX manager, the collectible system, the chart manager, expedition state: not synced.
- Resource counts in garage UIs are container contents (loot.lua) and health/fuel (health.lua, car.lua), not progression.
- The unlock graph, the logbook and the route are never reduced on the guest, so a guest that rejoins a different host keeps what an earlier host gave it until the game restarts (in memory only, never saved).
- The penalty mode for an expedition (forced 1) is not resolved on the host side; hardcore mode and the explicit mode (abandon run) are.
- Run failure itself (the game's `TravelToGarage` failed path with a real wreck) was not driven; the scenario calls `RemoveItemsPenalty(-1)` on the host, the same entry point the failed-run branch uses.
