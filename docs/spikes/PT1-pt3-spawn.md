# PT3 spawn: guest seated as DRIVER on a zone join (Steam playtest #3, #17)

> Historical research; see the [index](README.md) for current implementation and later evidence.

Observations
- Steam playtest guest log (local/playtest-20261023-steam/UE4SS-last.log): `PT|car riding ... offset=63.4,-31.5,-8.2` right after the zone join and
  `offset=51.4,-40.6,-11.8` after the garage rejoin: car-local Y < 0 is the driver seat. No `PT|car seated` line: our seat() never ran, the game attached it.
- Reproduced when the host's pawn is the car (host driving in): `20261023-232622-pt3-spawn-zonespawn`, guest at car-local 47,-46,-12 attached for the
  whole watch (32/34, the two driver-seat checks fail). With the host on foot (first run, `20261023-231700-...`) the guest spawns 390 uu behind the car, not attached: no bug.
- Fix (car.lua, host loop 250 ms): a guest character attached to the car that our seat() did not seat is re-seated by seat() (passenger seat, same path
  as a door entry). With it: `20261023-234721-pt3-spawn-zonespawn` 34/34 (join, X exit to ground, car drift < 60 uu, rejoin, X again). Mutation nozonefix:
  `20261024-001108-pt3-spawn-zonespawn-nozonefix` 32/34 (both driver-seat checks fail).
Derived
- The game (not our code) attaches a freshly spawned character next to a driven car as driver; the old attach plus X on the guest = guest in the car's collision / launch (#3, probably #17).
Guesses / unknowns
- #17 (40-60 s stuck, car launched) not reproduced separately; assumed same cause. The host-side X path was not changed.
- #12 (legs under the car) and #14 (slow entry) not looked at.
- Scenario does not press the real X key (sends g.car.exit as the key handler does) and not the real zone-from-garage travel.
