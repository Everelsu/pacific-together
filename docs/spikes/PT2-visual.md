# PT2 visual: what one player sees that the other does not

> Historical research; see the [index](README.md) for current implementation and later evidence.

Lane pt2-visual, 2026-10-22. Module `mod/PacificTogether/Scripts/visual.lua` (messages `g.vis.*`, mutation `novisual`).
Scenarios `visual` (zone fixture) and `visualgarage` (garage fixture), see "Results". Method: two-player repl session on the lane's pair
(`-Fixture garage`, then `zone`; zone also reached the real way, `TravelToNextLeg`), host/guest diffs with the game MCP `compare` and Lua
`compare(lua=...)`, plus targeted probes. Other lanes own: hands/tools/flashlight (pt2-hands), car upgrade effects and quirks (pt2-upgrades),
garage stations (pt2-stations); nothing of those is touched.

## Ranked differences (most visible in normal play first)

| # | Difference | How visible | State |
|---|---|---|---|
| 1 | The zone's procedural dressing exists on the host only: 10 to 12 buildings (`BP_BuildingFrame_*`: radio station, houses, gas station, trailers, shed, tower), about 1000 prefab static meshes (walls inside buildings, shelves, furniture, pallets, clutter, boards), 22 to 25 doors, about 110 to 126 destructibles (fences, barricades, cones, barrels, signs), posters, wall lights, graffiti. The run's spawn pass never runs on a guest (`LogSpawnExecutor` host only). Host 1146 `StaticMeshActor` not placed in the map file, guest 14 | Always: the guest walks through an empty forest while the host sees a town | fixed (visual.lua props mirror, `visual` 26/26) |
| 2 | Garage dressing: the Fig DLC sublevel `/PDFeature_Fig/Maps/RunProto/Garage_Fig_Props` (876 actors: candles, 41 small + 5 large cult graffiti decals, 57 station-dependent prop groups, 32 point lights) is loaded at run time on the host only | Always in the garage (every host with the DLC) | fixed (levels, `visualgarage`) |
| 3 | Car part paint, decal palette, tinting: the guest builds parts from archetypes, so a part the host repainted stays stock on the guest | Whenever the car was painted (paint shelf, cosmetics) | fixed (paint and decal, `visualgarage`) |
| 4 | Wheels of the host's car on the guest: `WheelComponent` angular position stays 0, suspension 0.33 constant while the host's turn and compress (guest's vehicle controller is off) | Whenever the guest watches the car drive from outside | not fixed (native driven; no safe visual-only setter found, see Unknowns) |
| 5 | Items moved between players keep archetype, durability, fuel, battery, health only: tints, upgrades, chart data do not travel (ids.lua `PROPS`) | A painted part in a trunk/on the ground, an upgraded tool | not fixed, listed in M4-loot2 already |
| 6 | Doors and destructibles that the host's players change after the first listing: broken flag and door state are sent (1 s), but a guest's own open/smash does not reach the host (the copies are visual) | Guest interacting with a door in a house | partly (host to guest only) |
| 7 | Anomaly hazards, storm wall, gateway portals, time of day, weather overrides | | verified equal (world.lua; compare: time, preset, rain, fog, wind, darkness, override count) |
| 8 | Car doors, hood, trunk, headlights, ignition, gear, handbrake, part health, radios, horn, wipers | | verified equal (car.lua, carfeel.lua); part health compare equal for wheels, headlight, panel |
| 9 | Garage doors, light switches | | covered by garage.lua (PT1) |
| 10 | Level-placed lights, FX, audio of the garage (325 lights, FX, ambience): 171 compared components equal | | verified equal |
| 11 | `BP_VolCascade_Radiation_C`, `BP_Hazard_RadiatedZone_*`, `ManageChildrenActor` counts differ (garage 1 vs 41 on the guest; zone 8 vs 3 etc.) | Not in view (tens of thousands of uu away, volumes) | not fixed, not visible |

## Results

- `visualgarage` 22/22 (`20261022-110552-pt2-visual-visualgarage`): Fig level 0 -> 876 guest actors in about 5 s; paint and decal follow in about 1 s.
  Mutation `novisual` 15/22 (`20261022-114421-pt2-visual-visualgarage-novisual`).
- `visual` (zone) 26/26 (`20261022-161801-pt2-visual-visual`): 90 % of sampled meshes and every sampled building, door and destructible exist on the guest;
  door state, destructible break and removed mesh follow within the 3 to 8 s polls. Mutation 19/26 (`20261022-162331-pt2-visual-visual-novisual`); the break and
  removal checks pass vacuously under the mutation (no copy exists to be wrong), the mirror, door and garage checks fail.
- Before the module (observed live on the same pair): Fig actors 0 on the guest, a repainted door stock on the guest, guest run-time meshes 14 vs host 1146,
  buildings 0 vs 10 to 12.

## Observations

- Real run (`TravelToNextLeg` from the garage fixture) and the zone fixture show the same host-only counts: BuildingFrame 11, Destruct 106, Door 22, StaticMeshActor 1146.
- Messages are reliable RPCs. A burst of 4 x 7 KB right after the join overflowed the reliable buffer ("Reliable buffer overflow ... ClientMessage") and the host closed
  the guest. Now: nothing is sent before the guest's `g.vis.hello` (5 s after it has a pawn in a real map), one 2.5 KB message per 500 ms, paths sent once.
- The guest builds slowly at first (each new mesh is a synchronous `LoadAsset`, about 0.3 s each under load, 265 distinct assets); nearest to the players first,
  30 ms budget per tick. About 940 copies took 60 to 140 s in the headless test.
- `Set Door from State(n)`: 0 closed, 1 and 2 open either way, 3 and up shut. Simple destructibles break with `SimpleBreak(impulse)`, complex with
  `ComplexBreak(impulse, primitive)`; the host's broken actor is gone at once, so the guest breaks its copy when the host's entry disappears and removes it 8 s later.
- `UEHelpers.GetWorld()` / `T.world()` can be a stale menu world on a guest that just left a session; spawn only once the map name is a real map.
- Hot reload (`repl.ps1 -Reload`) dropped the guest's connection in this setup; every check restarts the pair.

## Derived

- Wheels of the host's car do not turn on the guest: `WheelComponent:GetAngularPosition` 0 and suspension 0.33 constant while the host's change; the wheel meshes'
  relative transforms read 0 on the host too, so the visual is applied natively and no Lua setter was found.
- `BP_BuildingFrame_*` carry their mesh components in the Blueprint, so spawning the class at the host's transform rebuilds the building; variants the frame picks at
  BeginPlay (dirt piles, foundation variants) are the guest's own random picks.

## Guesses

- Brake and reverse lights of the host's car are not mirrored (vehicle controller input); not measured.
- Radiation volume and hazard counts differ in the garage (1 vs 41) but lie far outside the play area.

## Unknowns / gaps

- Copies are visual only: a guest opening a door or smashing a crate does not reach the host; a door the guest opens locally stays until the host's state changes.
- Frame variants, destructible debris, random graffiti variants may differ.
- Not done: garage whiteboard/monitors/framed mounts, dropped-item tints and upgrades (ids.lua `PROPS`), wheels, brake lights.
- Headless: state and positions were compared, no screenshot of the real look.
