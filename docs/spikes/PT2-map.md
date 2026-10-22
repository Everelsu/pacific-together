# PT2 map: the other player on the ARC map and the HUD (P8, D17 second half)

2026-10-22, lane `pt2-map`. Module `mod/PacificTogether/Scripts/mapmark.lua` (+ "mapmark" in FEATURES), scenario `mapmark` (fixture `zone`, mutation `nomapmark`).
Builds on `docs/research/arc-marker.md` (map icon registers) and `nametag.lua` (close range).

## Observations

- The only spatial map the game has is the ARC (Gobbler) screen in the car. The "run map" in the player menu (`UMG_PlayerMenu_RunMap`) is the route graph of junctions, no positions.
  So "map" = ARC screen; there is no handheld map.
- The game has its own HUD marker system: component `SC_GenericObjective` (`/Game/UI/NavigationSystems`, a SceneComponent) creates a `UMG_GenericObjective` widget
  (`ActivateObjective`), adds it to the screen (`BFL_Widget_Utils.AddWidgetToScreen`) and, with `UpdatePositionOnTick`, writes its own world location into the widget's `Position` every
  tick. The widget projects that to the screen and clamps it to the screen edge (`EdgePad`, `SnapScreenVector`), so an off-screen player shows as an edge arrow. `SetMarkerVisuals(Type, Text)`;
  type 3 = the blue quest marker with text. Its own text (`CheckForTextDisplay`) shows only within 8 m and when aimed at, so the distance text is forced visible by us.
- Run `20261022-085027-pt2-map-mapmark` (22/22): on both sides exactly one `MapIconComponent` and one `SC_GenericObjective_C` on the other's character, the icon is in the
  MapTracker's `GetMapIcons()`, the widget is in the viewport, both within 0-5 m of the other's own reported position (after a 50 m teleport the HUD/icon were 98 uu off the report, the
  report itself lags about a quarter second), HUD hidden at 1.7 m, shown with `<name> 49 m` after the move, gone when the guest left.
- A character teleported 50 m away in the zone fixture fell through the world on the guest (no collision there; guest "died", rejoined) until the test put the characters in flying
  movement mode (`CharacterMovement:SetMovementMode(5)`): test-only.
- Intermittent known issue seen once: the guest crashed on the rejoin after the scenario's own disconnect (run `20261022-084655`, EXCEPTION_ACCESS_VIOLATION); same family as the
  README known issue "guest crash on rejoin".

## Derived (what is built)

- Nothing replicates, no `g.map.*` messages: each side adds two runtime components to the other player's replicated character (same rule as the body, X13) and the game moves them with it
  every frame (far above 2 Hz). The scenario's position reports (`t.pos`) are test-only.
- Hand-over: the HUD marker is hidden within 30 m (`M.HANDOVER` = 3000 uu, the name tag runs from full at 15 m to gone at 50 m, so 30 to 50 m shows both) and shows
  `<name> <metres> m` (updated every 250 ms) beyond it. "Out of sight" alone is not a trigger: the game's widget does the edge clamping.
- Markers are removed when the other character is gone (they are components of it, plus explicit cleanup) and rebuilt after a map change (`RegisterLoadMapPreHook` forgets them).
- The map icon copies the car's icon (texture and materials) in cyan; it is only created once a car with a `MapIcon` exists in the world.
- Shared edit: `nametag.lua` exports `M.others()` (its 2 s scan of the other characters) so the scan is not duplicated.

## Guesses

- The icon is drawn on the ARC screen (registered with the tracker; same as the car icon, not seen in an image: headless).
- The HUD marker draws as the blue quest marker with the distance text under it and as an edge arrow when off-screen (widget code read, not seen in an image).

## Unknowns

- Screenshot proof of both (needs a rendered run; run `-Mutate shot`-style by hand: a playtester should look, see the report).
- Fog on the ARC map (`IconFogInteraction`) may hide the icon in unrevealed areas.
- Whether the car icon's rotation looks odd when used for a person; `Map-Pin` texture would be an alternative.
- When the other player is in the car the icon sits on their character (which rides the car): not tested separately.
