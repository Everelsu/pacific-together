# ARC map marker for the other player (D17, P8)

> Historical research; see the [index](README.md) for current implementation and later evidence.

2026-10-19, lane E. How the in-world ARC map draws markers and whether a second player marker can be added.
Sources: UE4SS dumps (`MinimapPlugin` UHT headers, `UMG_GobblerScreen`, `BP_GobblerMapview`, `BP_PlayerCarNew`),
extracted Blueprints, scenario `tourist` (marker steps on both sides,
`test/PacificTogetherTest/Scripts/scenarios/tourist.lua`).

## Observations

- The ARC map is the car's "Gobbler screen": car part `BP_Carpart_Internal_GobblerScreen_C` with a world-space widget
  `UMG_GobblerScreen_C`, which contains a `Minimap_C` widget (`/MinimapPlugin/Widgets/Minimap`). The view is
  `BP_GobblerMapview_C` (`UMapViewComponent MapView`, `TrackingCar`, `SetTrackCar`, zoom/pan).
- The map is the third-party **MinimapPlugin** (native module `MinimapPlugin`): actors carry a `UMapIconComponent`
  (texture, materials for UMG and canvas, size, colour, z-order, rotation, category, fog interaction, tooltip,
  objective arrow); icons register with a `UMapTrackerComponent` (`GetMapIcons()`, `OnMapIconRegistered`), and the
  widget draws every registered icon in view (`MinimapInternal_Icon_C` per icon).
- Classes with a `UMapIconComponent` in the dumps: `BP_PlayerCarNew_C.MapIcon`, `BP_WaypointActor_C.MapIcon` (the
  pin the player places, `UMG_GobblerScreen.PlaceWaypoint` spawns it), exit portals and level transitions,
  `BP_Spawn_Anchor_Base_01`, `BP_LocationalEvent`, `BP_ClumpedArea_Base`, `BP_ScriptKit_GobblerMap_GenericObjective`.
  `PDP_MainCharacter_C` has none: the map shows the car (texture `Map-PlayerCar`), not the player on foot.
- In game, garage, both sides (`20261019-200157-laneE-tourist`, 25/25): the tracker is a component on the game state
  (`GameStateBase_...MapTracker`). `AddComponentByClass(MapIconComponent, false, identity, false)` on the other
  player's character, then copying `IconTexture` / `IconMaterial_UMG` / `IconMaterial_Canvas` / size from the car's
  `MapIcon`, `SetIconDrawColor`, `SetIconVisible(true)`: the new icon is in `GetMapIcons()` right away
  (host: 6 icons incl. the car's; guest: 9 icons, the guest has its local duplicate car too, X3)
  (checks `host_marker_registered`, `client_marker_registered`).
  `20261019-201843-laneE-tourist-nomarker` (23/25, no component added): both marker checks FAIL.

## Derived

- A marker for the other player is one runtime component per side, no assets: each side adds a `UMapIconComponent`
  to the *other* player's replicated character (the same rule as the visible body, X13), styled from the car icon with
  its own colour. It moves with the character because it is a scene component on it.
- Nothing needs replication: each side draws its own map from the replicated character position.
- Do it after the guest's character spawns (and again after every map change, the character is new).
- The car icon on the guest must come from the replicated car, not its local duplicate (W2 dedupe), or the guest
  sees two cars.

## Guesses

- `Minimap_C` draws registered icons each tick, so a registered icon appears on the screen; not seen in an image
  (headless runs have no rendering).
- A distinct texture (`/Game/UI/Images/Minimap/Map-Pin`, `Diamond-Shadow`) reads better than a recoloured car.

## Unknowns

- Screenshot proof on the real ARC screen in a zone (needs a rendered run with the camera on the screen).
- Fog interaction: `IconFogInteraction` / `bHideOwnerInsideFog` defaults may hide the marker in unrevealed areas.
- Whether `IconCategory` must match a category the Gobbler legend shows (`SetIconCategoryVisible`).

Verdict: D17's map half is cheap: a runtime `UMapIconComponent` on the other player's character registers with the
game's map tracker on both sides (tested); drawing on the screen is not yet seen in an image.
