# ARC device: route planning, gateway summon, energy (D13, W11)

2026-10-19, lane E. Classes and calls behind the ARC, and how a guest's use could become host actions. Sources: UE4SS
dumps, Blueprints extracted from `pakchunk0` and listed with `tools/kdis/` (`local/research-extract/laneE/dis/`, git-ignored),
scenario `arc` (`test/PacificTogetherTest/Scripts/scenarios/arc.lua`).

## Observations

### What the ARC is in the game's code

- Internal name **Gobbler**. Two car parts:
  - `BP_Carpart_Internal_Gobbler_C` (`/Game/Gameplay/Inventory/Items/Car/Internal/Gobbler/`): the anchor slot.
    `AnchorAdded(ItemSlot, ItemInstance)` -> `AddingAnchorCompleteLogic` -> `SetItemProperty(IP_Gobbler, Instance,
    CurrentCharge, CurrentCharge + TotalGobblerCurrency)`; `CheckIfCharged` compares with `MaxCharge`. The energy is an
    item property (`IP_Gobbler.CurrentCharge`) on the Gobbler item instance in the car's equipment; it is reset in
    `BP_CarManager_C."Reset Car Attachments"`.
  - `BP_Carpart_Internal_GobblerScreen_C`: the map screen. A `BP_InteractCameraComponent` (focus/unfocus events) and a
    world-space widget `UMG_GobblerScreen_C` with a `Minimap_C` (map details: `arc-marker.md`). Input is read by the
    widget itself: `InpActEvt_NavigateUI_Select`, `Interact`, `UI_PlaceWaypoint`, `UI_ClearWaypoint`, zoom, back.
    `GetAnchorCharge(out CurrentCharge, out MaxCharge)` reads the Gobbler item via
    `BP_CarManager_C.GetGobblerItem(out HasItem, out Item, out Manifestation)`.
- Instability, storm walls and the exit list come from `BP_StormManager_C` (a manager on the game instance) and
  `BP_SpawningManager_C.CanPresentExitPortals`. Exit portals are `BP_LevelTransition_ExitPortal_C`, spawned by the
  host's run spawn pass only (X3).

### Gateway summon (bytecode)

1. Screen `TryPresentExits`: `Charged and SpawningManager.CanPresentExitPortals()` -> `Minimap.PresentExits()`.
2. Select on a hovered exit: `UseSelectedWidget` -> `portal.CanPress()` and not `IsExitWithinRadius()` ->
   `portal.StartPress()`, binds `PressComplete` -> `ExitUseComplete` -> `OnExitUseComplete(portal)`.
3. Screen part `OnExitUseComplete(portal)`: `popifnot(AbleToChooseExit)`, then
   `BP_StormManager_C."Select Exit Portal Actor"(portal)`: broadcasts `OnExitPortalSelected(portal)` and sets
   `EvolvedGatewayExit = portal`.
4. Screen part `OnExitPortalSelected_Event_0` -> `SetSelectedExitPortal` -> (unless `WB.LevelType.Fig`)
   `Screen.Charged = false`, `AbleToChooseExit = false`, `ExitSelected = true`,
   route whiteboard `WB.ActiveRun.GatewaySelected = 1`, `Screen.ActivateExit(portal)`, `portal.Activate()`,
   `StormManager.SpawnExitTriggeredStorm(location, portal)` (royale storm toward the gateway).
5. Driving into the portal: `BP_LevelTransition_ExitPortal_C` checks the car (`IsCarWithinDistance`, alert
   `hud_alert_level_transition_failed_no_player_in_car`), then `WorldState.TravelTo(dest, 0)` or
   `BP_ProgressionManager_C.TravelToGarage(...)`.

### Route planning (bytecode, not exercised in game)

- Garage map table `BP_RunPlanner_MapTable_2_C` with `UMG_RouteDisplay_*` / `UMG_RunPlanner_*` widgets; global tag
  `WB.WorldState.Garage.RoutePlannerInUse`. Clicking a leg calls the leg state: `BP_LegStateBase_C.RevealLeg(2, true)`
  (native `UBaseLegState::RevealLeg(ELegRevealState, bSuppressImplicitReveals)`, guarded by `CanReveal`);
  rerolls via `"Re Roll Leg from Station"` and `BP_ProgressionManager_C."Reroll Route Selection"(CritPathOnly, SimulateRun)`
  (the Destabilizer station uses the latter); expeditions via `ProgressionManager.ExpeiditonOfferSelected(ChartInstance)`.
- The route itself is native: `UBaseProgressionManager.GetWorldState()` -> `UBaseRouteState` (`TravelTo(leg, reason)`,
  `SetCurrentLegState`, `BeginPlanningPhase/GenerationPhase/ExplorePhase/IdlePhase`, `NotifyPlayerMapSelection`,
  `GetRevealedLegs`, `GetActiveAdjacentLegs`), legs `UBaseLegState` (`CanNavigateTo`, `DiscoverLeg`, modifiers).

### Other energy uses seen

- Tinker hints spend `CA_AnchorJuice_Stable` currency (`InventoryManager.CurrencyAdjust`, see `garage-stations.md`).
  Anchor currencies (`CA_AnchorJuice_Stable/Unstable/Corrupted`) are garage currencies, separate from the Gobbler charge.

### In game (scenario `arc`, one game, `open Wilderness_Forest_01`, headless)

- `20261019-202305-laneE-arc` (9/9): after 30 s the zone has the screen part, the storm manager, 2 exit portals and a
  Gobbler item (`GetAnchorCharge` -> 0.0/0.0, `AbleToChooseExit=true`, `ExitSelected=false`). One host call
  `StormManager."Select Exit Portal Actor"(portal)`: 3 s later `ExitSelected=true`, route whiteboard has
  `WB.ActiveRun.GatewaySelected`, `EvolvedGatewayExit` = that portal (`gateway_selected_by_host_call`).
- `20261019-202638-laneE-arc-noselect` (8/9): without the call the check FAILs.

## Derived

- **Gateway summon** is one host call: `BP_StormManager_C."Select Exit Portal Actor"(portal)` runs the game's whole
  chain through its delegate (tested; the storm and portal visuals were not checked). The UI's charge gate is in the
  screen (`Charged`, `AbleToChooseExit`), so the host must check them itself before acting on a guest intent:
  `AbleToChooseExit` and `GetAnchorCharge` current >= max.
- **Guest side of the summon:** the guest's own screen part can stay the UI. On the guest, keep its
  `AbleToChooseExit` false (the screen part pops before calling the storm manager, so nothing local happens) and
  post-hook its `OnExitUseComplete(portal)` to send `summon <portal id>`. Needs the portals on the guest (today host-only:
  replicate them or spawn proxies with the same stable id), the charge mirrored into the guest's Gobbler item property,
  and the storm state mirrored for the screen's warning visuals.
- **Energy:** anchors reach the Gobbler as an item-slot move into its container (`AnchorAdded`); the generic item-slot
  intent covers a guest depositing an anchor, the host's `AddingAnchorCompleteLogic` adds the charge. The guest's
  display reads `IP_Gobbler.CurrentCharge` locally, so the host broadcasts charge changes.
- **Route planning:** intents `reveal <leg id>`, `reroll`, `expedition <offer>` mapped to `RevealLeg`,
  `"Reroll Route Selection"` and `ExpeiditonOfferSelected` on the host; leg ids from the route shape (legs are
  `URouteShapeLeg` in the host's `UBaseRouteState`). The guest's planner UI would need the host's route state, which
  is native data; mirroring it is the costly part. Cheapest v1.0: the guest watches the host plan (planner only on
  the host), and only the in-run ARC actions (summon, waypoint, anchors) go through intents.
- Waypoint pins (`PlaceWaypoint` spawns `BP_WaypointActor_C` locally) are per side; sharing them is one more intent
  if wanted.
- D12/C7 (passenger reach): the screen part uses `BP_InteractCameraComponent` focus, so the guest needs to reach the
  screen part's highlight from the passenger seat (spike X8).

## Guesses

- `MaxCharge` 0.0 in a zone opened by console (no run state) means the charge needs a real run to be meaningful.
- `SpawnExitTriggeredStorm` and `portal.Activate()` ran, given `ExitSelected` and the tag were set in the same chain.

## Unknowns

- Route planning was not run in game; which call commits "the planned route" before leaving the garage
  (`NotifyPlayerMapSelection`? leaving through `BP_Garage_GatewayExit_01_C`?) is unconfirmed.
- How the interact camera and the screen's input stack behave for a second player in the passenger seat.
- What the guest's screen part shows without the host's portals and storm (it reads local managers).

Verdict: D13 is feasible for the in-run ARC: gateway summon is a single host call (tested), energy and anchors ride on
item-slot intents and a mirrored charge; route planning by the guest is costlier (native route state) and is better
left host-only for v1.0.
