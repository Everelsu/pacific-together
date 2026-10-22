# PT2-ping: look, press, both players see a marker

Module `mod/PacificTogether/Scripts/ping.lua`, scenario `scenarios/ping.lua`, mutation `noping`.

## Behaviour
- Key: middle mouse button (`Key.MIDDLE_MOUSE_BUTTON`), falls back to G if UE4SS has no such key. The log line
  `PT|ping key MIDDLE_MOUSE_BUTTON bound=true` says which. Inert without a session (listening host with a guest, or a guest).
- Press: line trace (`KismetSystemLibrary:LineTraceSingle`, Visibility channel, own pawn ignored, 300 m) along the camera
  from `PlayerCameraManager`. The item or container nearest the view ray (within 90 uu, in front of the hit) names the marker:
  `BP_WorldItem_C` -> `Instance.Archetype.Title`, `BP_Lootable_Base_C` -> class name made readable.
- Marker: a local `TextRenderActor` ("Name / item / N m / v"), faced to our camera each frame, text size grows with distance,
  gone after 8 s (`PT_PING_LIFE` overrides, tests only). One marker per player name; a new ping replaces it.
- Sound: `AkGameplayStatics:PostEventAtLocation` with the game's `hud_log_entry_new_appear` (the log-book "new entry" blip,
  `/Game/WwiseAudio/Events/UI/ui_hud/`), played on every marker that appears (own and the other player's).
- Net: guest -> host `g.ping.send` "x<TAB>y<TAB>z<TAB>label"; host shows it and sends `g.ping.show` "name<TAB>x<TAB>y<TAB>z<TAB>label" to all guests;
  the host's own ping goes straight to `g.ping.show`. The guest's own marker appears when the host echoes it.
- Test hook: console command `ptping` runs the key's handler (the test mod is another Lua state and cannot call the module).

## Observations
- LineTraceSingle works from Lua with an out table: `hit.ImpactPoint`. Camera-ray check in the scenario: cos 1.0000.
- A TextRenderActor spawned with `BeginDeferredActorSpawnFromClass` + transform stayed at the origin; `K2_SetActorLocation` after spawn fixes it.
- Dropped Scrap Metal was named "Scrap Metal" on both sides.
- The marker sits in the world and is depth tested: it hides behind walls (not tried visually; headless).

## Derived
- Game has no ping/waypoint marker for players; `BP_Abilities_ResourceScanner_3DPing` is the scanner effect, not usable.

## Guesses
- Middle mouse works for a real player: UE4SS polls the key state and `RegisterKeyBind` returned true; a real click was never sent (headless).
- The sound is audible: the call runs without error, never heard.

## Unknowns
- How the marker reads on screen (colour, size at 5 m versus 100 m); a playtester should judge.
- A lootable's class name can be an internal name ("Lootable Glovebox"); no list was checked.

## Runs
See the report; result folders in `local/test-results/*pt2-ping-ping*`.
