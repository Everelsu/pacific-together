# M5 world lane: run state, anomalies, story bystander (W3, W4, W6, G3)

> Historical research; see the [index](README.md) for current implementation and later evidence.

2026-10-21. Mod: `mod/PacificTogether/Scripts/world.lua`. Scenario: `worldsync` (fixture `gateway`, mutation `noworldsync`).
Results (`local/test-results/`): `20261021-112743-world-worldsync` 27/27; mutation `20261021-114320-world-worldsync-noworldsync` 20/27
(7 sync checks fail); regressions `20261021-113417-world-session` 40/40, `20261021-114000-world-sessiontravel` 54/54.

## Observations

- Zone fixture, host vs guest before the mod: time of day 0.358 vs 0.504; weather override array 2 entries vs 0 (fog 0.74 vs 0);
  `WB.WorldState.Instability.Current` tag exists on the host only; `TimeBeforeInstabilityStarts` 1320 vs 0; hazards (all
  `BP_Base_Hazard` children): host 25 (10 Landmines/Tourists, 6 Bollards, 5 Tesla, 4 PhysicsGrabbers), guest 7 of its own (Tesla and
  grabbers are level-placed in the `_Mission_Sub` streaming level, Role 0 on the guest; their positions already drift apart).
  Host exit portals: 2 live (the rest destroyed), guest: 5 live.
- Landmines/Bollards/the zone storm are host-only spawns. `SetReplicates(true)` + `SetReplicateMovement(true)` on the host at
  runtime makes the guest create the actor (Role 1) at the same place; the default cull (15000 uu) hides them from a far guest, so
  `bAlwaysRelevant = true`. For level-placed actors (Tesla, grabbers, portals) the channel attaches to the guest's existing same-named
  actor (Role 0 -> 1). Replicated movement does not hold for grabbers: their own motion code (actor tick) moves them back.
- A replicated `BP_ZoneStormRoyale_C` starts on the guest with the same `FirstWallLocation` and `Vol_Rad_Main`; the collapse
  progress (`Vol_Rad_Weak`) differs (its timelines start when it arrives), so the host sends the radii.
- Managers live under `/Engine/Transient` (game instance); world actors under the map: filter transient only for actors.
- `BaseMissionManager.StartMission(Mission, bForce)` on a guest without a hook crashes the process (0x80000003, mutation run
  `20261021-113053-world-worldsync-noworldsync`). With the hook that nulls the mission argument it starts nothing.
- ToD: `BP_ToDManager` `Get/Set Current Time Of Day`, `Set New TOD Target(class)`, `AddTODWeatherOverride(struct)` /
  `RemoveTODWeatherOverride(name)`, `SetCurrentWeatherOverrideValues(7 floats)`; the override struct fields carry GUID suffixes
  (see `OV` in world.lua). Instability: route whiteboard float tag `WB.WorldState.Instability.Current`.

## Derived

- One generic mechanism covers every `BP_Base_Hazard` child (Tourists, Bunnies `BP_Boon_LootCreature`, grabbers, Tesla/spark towers,
  bollards, geysers ...), so the "run-shaping" list of W6 is covered by class, not by per-anomaly code. Hazards that are
  `BP_Base_Hazard_WorldItem` (Leech, BombRock) hold item instances and are NOT replicated today.
- The guest keeps its own copies of nothing: after 5 s of host state, any hazard/storm/portal that is not Role 1 is destroyed
  on the guest; replicated hazards have actor tick off on the guest and are placed by `g.world.pos` (host, 4 Hz changes, full
  resend every 2 s).

## What a playtester sees

Same time of day, rain/fog, same instability value, same storm (position, wall radius) and the same anomalies in the same places
(Tourists, bollards, grabbers, Tesla), moving with 250 ms to 2 s granularity; the gateway the host picked is the picked exit on the
guest too, and portals the host does not have are gone. The guest starts no quests; the host's story plays only on the host.

## Gaps at the time

- Anomaly effects on the guest's own character (grab, shock, steal, tourist step) run on the guest's local copies of the logic
  (Role 1, tick off, timers still run): partial. Tourists still creep toward camera 0 of the host (docs/research/tourists.md).
- Not replicated: Leech, BombRock and other item-world hazards; Pickpocket and Abductor were not located as separate classes
  (assumed `BP_Base_Hazard` children, unchecked); anomalies that spawn after the guest joined are replicated within 1 s.
- Storm: guest instability timer is left to its own state but its manager fields are overwritten each second; a storm the guest's
  own manager spawns is destroyed as a non-Role-1 actor. Storm audio/visual collapse is the guest's own timeline plus host radii.
- Weather: the guest's `ToD` director may still start its own weather event; the host's override list wins each second.
- Story: only missions are blocked (StartMission/StartObjective/AdvanceObjective pre-hooks) and `NarrativeBeatActor`s are
  destroyed; cutscenes, radio and VO of the guest's own process were not probed, no story audio mirrored (P1). A host mission
  step did not crash the guest in the test (`AdvanceAllObjectives`).
- Exit warp: the gateway travel itself is the session's travel (`sessiontravel`), not new here.
- Not tested: garage (no anomalies), a guest joining mid-storm, hazards spawned late.

## Unknowns

- Whether a Role 1 copy's timers (Tourist `ShouldCreep`) can move it between position updates in long play.
- Fidelity of the hazard transform stream under 150 ms lag.
