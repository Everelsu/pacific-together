# PT2 visual: what one player sees that the other does not

Lane pt2-visual, 2026-10-22. Module `mod/PacificTogether/Scripts/visual.lua` (messages `g.vis.*`, mutation `novisual`).
Scenarios `visual` (zone fixture) and `visualgarage` (garage fixture), see "Results". Method: two-player repl session on the lane's pair
(`-Fixture garage`, then `zone`; zone also reached the real way, `TravelToNextLeg`), host/guest diffs with the game MCP `compare` and Lua
`compare(lua=...)`, plus targeted probes. Other lanes own: hands/tools/flashlight (pt2-hands), car upgrade effects and quirks (pt2-upgrades),
garage stations (pt2-stations); nothing of those is touched.

## Ranked differences (most visible in normal play first)

| # | Difference | How visible | State |
|---|---|---|---|
| 1 | The zone's procedural dressing exists on the host only: 10 to 12 buildings (`BP_BuildingFrame_*`: radio station, houses, gas station, trailers, shed, tower), about 1000 prefab static meshes (walls inside buildings, shelves, furniture, pallets, clutter, boards), 22 to 25 doors, about 110 to 126 destructibles (fences, barricades, cones, barrels, signs), posters, wall lights, graffiti. The run's spawn pass never runs on a guest (`LogSpawnExecutor` host only). Host 1146 `StaticMeshActor` not placed in the map file, guest 14 | Always: the guest walks through an empty forest while the host sees a town | fixed (visual.lua props mirror) |
| 2 | Garage dressing: the Fig DLC sublevel `/PDFeature_Fig/Maps/RunProto/Garage_Fig_Props` (876 actors: candles, 41 small + 5 large cult graffiti decals, 57 station-dependent prop groups, 32 point lights) is loaded at run time on the host only | Always in the garage (every host with the DLC) | fixed (levels) |
| 3 | Car part paint, decal palette, tinting: the guest builds parts from archetypes, so a part the host repainted stays stock on the guest | Whenever the car was painted (paint shelf, cosmetics) | fixed (paint) |
| 4 | Wheels of the host's car on the guest: `WheelComponent` angular position stays 0, suspension 0.33 constant while the host's turn and compress (guest's vehicle controller is off) | Whenever the guest watches the car drive from outside | not fixed (native driven; no safe visual-only setter found, see Unknowns) |
| 5 | Items moved between players keep archetype, durability, fuel, battery, health only: tints, upgrades, chart data do not travel (ids.lua `PROPS`) | A painted part in a trunk/on the ground, an upgraded tool | not fixed, listed in M4-loot2 already |
| 6 | Doors and destructibles that the host's players change after the first listing: broken flag and door state are sent (1 s), but a guest's own open/smash does not reach the host (the copies are visual) | Guest interacting with a door in a house | partly (host to guest only) |
| 7 | Anomaly hazards, storm wall, gateway portals, time of day, weather overrides | | verified equal (world.lua; compare: time, preset, rain, fog, wind, darkness, override count) |
| 8 | Car doors, hood, trunk, headlights, ignition, gear, handbrake, part health, radios, horn, wipers | | verified equal (car.lua, carfeel.lua); part health compare equal for wheels, headlight, panel |
| 9 | Garage doors, light switches | | covered by garage.lua (PT1) |
| 10 | Level-placed lights, FX, audio of the garage (325 lights, FX, ambience): 171 compared components equal | | verified equal |
| 11 | `BP_VolCascade_Radiation_C`, `BP_Hazard_RadiatedZone_*`, `ManageChildrenActor` counts differ (garage 1 vs 41 on the guest; zone 8 vs 3 etc.) | Not in view (tens of thousands of uu away, volumes) | not fixed, not visible |

## Observations

(filled in at the end)

## Derived

## Guesses

## Unknowns
