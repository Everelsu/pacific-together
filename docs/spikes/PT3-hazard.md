# PT3-hazard: radiation on the guest (#8), wheel damage look (#9), repeating story lines (#4)

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

## #9 wheel damage look (NOT done, no run)
- Our Lua never touches wheels (grep: no wheel/tire code in car.lua, guestparts.lua, carfeel.lua).
- Atlas: the flat look is the wheel mesh material (`flatTire_TraceDistance`, `flatTire_WheelOffset_Vector`) set every tick by `BP_CarPart_Wheel_Base` from the WheelComponent's trace; the flat state is `CarManager:GetPartFlat(slot)` (status effect `SE_FlatTire` on the item instance, read by AC_CarHandling.UpdateFlatTireCalcs). Guess: the car's wheel parts on the guest copy lack the status effect / trace, or the host's co-op car loses it; first step next time is a solo-vs-coop live comparison (`GetPartFlat` on host and guest after `AddItemStatusEffect(inst, SE_FlatTire_C)`).

## #4 repeating story lines (changed, NOT proven by a scenario)
- Guest log: the same dialogue sequence `g.story.say` played every ~6.1 s (= the guest's 6 s dedupe window) and `PT|prog guest whiteboard N tags set` 69 times in 3 minutes; the tags were `WB.Statistics.PlayerWalkMileage` and `WB.Statistics.PlayerDamage.Rad`, rewritten every 2 s (the guest counts its own statistics).
- Changes: story.lua dedupe window for a replayed line 6 s -> 90 s; progression.lua skips `WB.Statistics.*` tags. Unknown whether the host really replays the sequence (host's `CurrentlyPlayingSequence` flapping) or the story-state apply retriggers lines on the guest; the "mission updated" link was not investigated.
