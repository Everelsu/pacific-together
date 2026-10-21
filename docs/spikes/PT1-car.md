# PT1-car: ARC position and the guest's car exit (playtest 1)

## Observations
- Bug A repro (`20261021-232133-pt1-car-arckey`): with the old ARC spot (slots shifted car-local Y -42.5) the ARC screen's
  collision sits on the driver camera -> ignition key ray (`UICollision_Key`, a 12 uu box); the game's highlight shows the screen.
- Bug B repro (`20261021-221220-pt1-car-carexit`): after the exit intent the host detaches the guest and moves it ~250 uu outside, but the
  guest's own pawn stayed at the seat (own -3829,-1822 vs host view -3724,-2101). The pawn is an autonomous proxy with its movement off, so
  the host's move never reaches it.
- Fix B: the host sends `g.car.out` (world spot); the guest detaches, ends the ride and places itself there. carexit 29/29
  (`20261021-231736-pt1-car-carexit`); mutation `noexitfix` 27/29 (`...-231934-pt1-car-carexit-noexitfix`).
- Fix A: both ARC slots now shift car-local X -70 (behind the seats, Y unchanged). arckey 25/25 (`20261021-234850-pt1-car-arckey`);
  mutation `arcold` fails the key trace (`20261021-234702-pt1-car-arckey-arcold`: ARC ScreenCollision and another
  `CarPart_Interactive` box in the sphere sweep).
- The game's highlight trace (`BP_HighlightManager.PerformTrace`) is a sphere multi-trace for objects (radius 4 uu inside the car) from the
  view target's camera; the scenario runs that same trace from the driver's real camera to the key.

## Derived
- Key world spot is about car-local (132, -30, 22). The old ARC screen sat at about (113, -25, 33).
- The guest's highlight on the ARC screen still works from the seat at the new spot (turn round to the right-rear).

## Guesses
- Other panels/radio: only the key ray is traced; the new spot is behind the front seats, away from the dashboard, so nothing in front of the driver is covered.

## Unknowns
- The key highlight never showed headless (`none`, also with the ARC in its vanilla spot): the possessed car camera cannot be turned, and the
  character-seated view does not highlight it. So the proof is the trace, not `CurrentHighlight`.
- Only one guest seat exists (the mirrored driver seat), so there is no separate driver-exit case.
- The exit key X is a UE4SS key bind, not drivable headless; the scenario sends the exit intent it sends (as playpath does).
