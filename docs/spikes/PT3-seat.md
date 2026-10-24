# PT3 seat: guest legs under the car (#12), slow car entry (#14)

> Historical research; see the [index](README.md) for current implementation and later evidence.

Later October 24 work added an explicit seat message and per-frame attachment checks; the earlier slow-entry conclusion below is superseded. See [../../NOTES.md](../../NOTES.md).

## Observations
- carsit baseline (20261024-040742-pt3-seat-carsit): seated guest body, both sides: ALS_MovementMode 1, foot_l 91 uu below the car origin.
- Setting ALS_MovementMode 5 (what the game sets for its own character in the car, PDP_MainCharacter ubergraph) leaves foot/pelvis/head heights unchanged live (garage, VisibilityBasedAnimTickOption forced to 0): no sitting pose behind it.
- The game has no sit animation: its seated driver is never shown (no hide/visibility code in the enter path, FP view).

## Derived
- Fix: car.lua sitPose() hides thigh_l/thigh_r (Mesh:HideBoneByName) on the host's body copy (seat) and on the guest's own pawn (ride); unhidden on exit (g.car.exit, stopRide). Mutation nosit.
- carsit with fix 23/23 (20261024-041127-pt3-seat-carsit), nosit 21/23 (20261024-041353-pt3-seat-carsit-nosit).

## Guesses / Unknowns
- Not seen rendered (headless only): the torso floats at seat height with no legs; the owner should look at it from both sides.
- #14 not fixed: host-side seating comes 0.2 s after the door intent in the playtest logs; the guest only notices its attach on the 250 ms guestTick poll. No multi-second wait found in car.lua; the slow cases are probably the game's door/entry flow before EnterCar fires. The playtest guest UE4SS log holds only the last session, no intent timing.
