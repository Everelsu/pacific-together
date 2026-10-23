# PT3 anom: Spark Tower and Grabber on the guest (Steam playtest 2026-10-23)

Lane `pt3-anom`. Code: `anomalies3.lua` (wake, range, Tesla effects), `world.lua` (hazard smoothing). Scenario `anomtesla` (fixture `zone`), mutations `noanomtesla` (wake, range hook, effects off) and `nosmooth` (smoothing off).

## Observations

- Playtest: the Spark Tower did nothing for the guest; the Grabber worked but moved per frame.
- Zone fixture hazards (scenario log `zone hazard`): Bollard x6, Landmine x10, PhysicsGrabber x1, Tesla x1.
- Tesla in the game's code (atlas `BP_Hazard_Tesla`): `FindTarget` takes the first actor with the best tag priority in its AoE (tags `ActorTags.Character.MainPlayer`, car chassis ...); the guest pawn
  is found by it (target moved to 400 uu east of the Tesla = the guest, then the guest lost health). So targeting was never the problem.
- The real cause: the Tesla is a `ManagedTickComponent` owner. `SpatialTickController:Tick` switches the owner's tick off by distance (`MaxTickDistance` 5000) from the HOST's player. A Tesla
  next to a guest who is far from the host has no tick at all (`IsActorTickEnabled` false, no buildup, no search, no shot). Calling `SetOwnerTickEnabled(true)` is undone by the controller
  on its next tick (7000+ wakes in 20 s with no effect); `SpatialTickController:RemoveManagedTick(comp)` first makes it stick.
- The same distance rule exists in `BP_HazardProperty_PlayerRange:DistanceToPlayer` (distance from `GetPlayerCameraManager(0)`, flattened): Landmines, Bollards and Grabbers arm only for the host.
- Level-placed hazards the host replicates are spawned anew on the guest (name `BP_Hazard_PhysicsGrabber_C_2147477277`, Role 1), not matched by name to the host's actor. So `g.world.pos` (by name)
  does not move them; their motion is the engine's replicated movement (snaps at the update rate). The Tesla copy on the guest has a different name too.
- Measuring smoothness: the host moves the grabber 700 uu every 500 ms; the guest counts the share of frames (from first to last movement) in which the copy moved: 78% smoothed, 18% with 
osmooth.
- Real Steam playtest guest log: `SerializeNewActor failed` for Tesla/Grabber/ExitPortal: the engine channel to those actors failed on the guest there (streaming sublevel not yet loaded when the
  channel opened). It does not happen in the zone fixture. If it happens, the guest has no copy and the effects below find nothing (logged `found=false`); the damage still arrives (anomalies.lua).
  Not reproducible here, unknown: whether the channel retries.

## Derived (what is built)

- Wake (host, 500 ms): a `ManagedTickComponent` whose owner is dormant and within its own `MaxTickDistance` of a guest pawn is taken out of the controller (`RemoveManagedTick`), owner tick on;
  put back (`AddManagedTick`) when no guest is near. Covers every managed hazard (Tesla, Leech trees, malfunction volumes ...).
- Range: post-hook on `BP_HazardProperty_PlayerRange:DistanceToPlayer` (host) uses the nearest guest's flat distance when shorter. Landmines (and Bollards, Grabbers) arm for a lone guest.
- Tesla effects: the guest's copy does not tick, so the host watches each running Tesla every 100 ms and sends the winding beam (`CreateTargetingBeam`) and the discharge (cooldown edge after a
  real target) as `g.anom3.fx`; the guest runs `FireFakeShot` + `CreateDischargeFX` / `CreateTargetingBeam` on the copy nearest to the Tesla's position. Hooks on `Discharge`/`CreateTargetingBeam`
  never fired (Blueprint-internal calls), hence the polling. Damage was already forwarded by anomalies.lua (`DispatchMessageInSphere` on the guest pawn).
- Smoothing (guest, `world.lua`): every frame, a replicated hazard (Role 1) moved by the engine is shown gliding from its shown spot to the new one over the time between the last two updates
  (80..500 ms); jumps over 1500 uu snap.

## Per hazard in the zone fixture (guest alone near it, host far)

- Tesla: reacts to the guest now (wake + targeting + damage forwarded); before: only when the host was within 5000 uu.
- Landmine: armed by `PlayerRange` for the guest now (check `landmine_arms_for_guest`); its creep target is `GetPlayerPawn(0)` (host), so it does not creep toward the guest (not fixed). Tourist creep freeze: anomalies.lua.
- Bollard: arming via `PlayerRange` now; the bollards' own `SERVER_Start` from the guest copy has no owning connection (playtest log), not looked at.
- PhysicsGrabber: pull and hit reach the guest (anomalies2.lua); arming via `PlayerRange` now; movement smooth on the guest.

## Checks (scenario `anomtesla`)

`guest_hurt_by_tesla` (the guest stands next to the Tesla, the host 44000 uu away: guest health drops), `guest_sees_tesla_fx` (the guest's copy runs the beam/discharge functions; NOT discriminating: the
guest's own near copy also runs them when the fix is off), `landmine_arms_for_guest`, `grabber_smooth_on_guest` (share of guest frames in which it moved >= 60%).

## Unknowns

- Host health read 97 once after a Tesla shot at the guest (put-back sampling in anomalies.lua, not the Tesla); not investigated.
- Guest's own Tesla copy ticking near the guest (its own sim) may double the visuals with the mirrored effects. Not observed visually (headless).


## Runs (local/test-results)

- normal: 20/20, `20261024-014734-pt3-anom-anomtesla`
- `nosmooth`: 19/20, fails `grabber_smooth_on_guest` (18% of frames moved vs 78%), `20261024-014941-pt3-anom-anomtesla-nosmooth`
- `noanomtesla`: 18/20, fails `guest_hurt_by_tesla` and `landmine_arms_for_guest`, `20261024-015413-pt3-anom-anomtesla-noanomtesla`
- before the fix (first runs, `20261023-233106`): `guest_hurt_by_tesla` failed (Tesla dormant, `tick=false`), 16/19.
