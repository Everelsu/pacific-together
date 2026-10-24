# PT3-hazard: radiation on the guest (#8), wheel damage look (#9), repeating story lines (#4)

> Historical research; see the [index](README.md) for current implementation and later evidence.

## #8 radiation (fixed, scenario `radiation`)
Observations
- Zone Rural_Forest_Radio_Scylla_02, live probe: host 8 `BP_VolCascade_Radiation_C` (5 with Max Local Radiation > 0), guest 3 (all Max 0, level-placed). `BP_HazardManager_C["Is Radiation Greater at Point"]` at a host volume: host true, guest false.
- The game hurts the player in its own process (BP_ResourceDirector asks the hazard manager for the radiation at the player's location); the radiated-zone BPs spawn the volumes at runtime on the host only.
- Spawning a volume on the guest with `world:SpawnActor`, setting Radius / "Falloff Size" / "Max Local Radiation" / Shape / BoxShapeSize / BoxShapeFalloff and calling `UpdateInfluenceZone(Influence_LocalRadiation)` makes the guest's hazard manager see it.
Derived
- Fix: `radiation.lua`: the host sends its radiating volumes every 4 s (`g.rad.vols`), the guest spawns the missing ones (matched by position, 100 uu). Scenario `radiation` (zone): host places the guest in the strongest volume, the guest's game sees radiation there and its health falls. Mutation `norad` fails it (guest_game_sees_radiation, guest_health_fell).
- Results: norad 16/20 (folder 20261023-233134-pt3-hazard-radiation-norad), fixed 20/20 (20261023-235751-pt3-hazard-radiation).
Unknowns
- The spawned guest volumes have no decal / point light / VFX (construction visuals not run); only the damage is shared. Volumes the host destroys are not removed on the guest.
- Radiation damage to the car on the guest side was not looked at.

## #9 flat tyres (partly fixed, scenario `wheelflat`)
Observations
- Live probe (zone, host + guest): the flat state is `BP_CarManager:GetPartFlat(slot)`; `SE_FlatTire` / `SE_BlownoutTire` (on the wheel item instance) call `SetPartFlat`. Applying `SE_FlatTire` on the host's WheelFR via `BP_StatusEffectManager:AddItemStatusEffect(instance, class)` gave flat=true on the host and flat=false on the guest: nothing mirrors it. Handling (`AC_CarHandling.UpdateFlatTireCalcs`), audio (`AC_CarAudio`) and the field-guide scan read `GetPartFlat`, so the guest's car never knew.
- Our Lua never touched wheels. The visible tyre squash is the wheel mesh material (`flatTire_TraceDistance` from the wheel trace, `BP_CarPart_Wheel_Base`); nothing sets a separate "flat" look, so it follows the suspension sag the handling tuning produces.
Derived
- Fix: `wheelflat.lua`: host sends the four slots' flat flags (`g.wheel.flat`, every 5 s and on change), the guest calls `SetPartFlat`. Scenario `wheelflat` (zone): flat on the host's WheelFR, the guest's GetPartFlat shows it (FL stays whole). `noflat` mutation: 16/17 (guest_wheel_flat fails), fixed 17/17 (folders 20261024-002523-pt3-hazard-wheelflat-noflat, 20261024-002639-pt3-hazard-wheelflat).
Unknowns
- Whether the tyre then LOOKS flat on the guest (a rendered check by eye is needed). The owner said the host did not show it either; the host side was not reproduced (headless, no screenshot of a driven car). The status effect itself is not added on the guest (only the map), so a scan of the guest's own item may still say whole.

## #4 repeating story lines (changed, NOT proven by a scenario)
- Guest log: the same dialogue sequence `g.story.say` played every ~6.1 s (= the guest's 6 s dedupe window) and `PT|prog guest whiteboard N tags set` 69 times in 3 minutes; the tags were `WB.Statistics.PlayerWalkMileage` and `WB.Statistics.PlayerDamage.Rad`, rewritten every 2 s (the guest counts its own statistics).
- Changes: story.lua dedupe window for a replayed line 6 s -> 90 s; progression.lua skips `WB.Statistics.*` tags. Unknown whether the host really replays the sequence (host's `CurrentlyPlayingSequence` flapping) or the story-state apply retriggers lines on the guest; the "mission updated" link was not investigated.
