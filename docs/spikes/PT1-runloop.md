# PT1 runloop: the full run loop together (D4, W3/W4/W5/W11, P5)

Scenario `runloop` (`test/PacificTogetherTest/Scripts/scenarios/runloop.lua`, fixture `garage`, mutation `nokeep`).

## Observations

- Loop driven through the game's own calls: garage -> zone `BFL_ProgressionHelpers:TravelToNextLeg`; zone -> garage
  (a) `BP_StormManager."Select Exit Portal Actor"(portal)` + `TravelToGarage(2)`; garage -> zone again; zone -> garage
  (b) the emergency protocol as `RunFinished_Failure` makes it (`RemoveItemsPenalty`, `DepositPostRunItems(false)`,
  `SetPlayerCarState(1)`, `TravelToGarage(3)`).
- Nothing broke on current main (0.0.5-dev, 11e3841): runloop 49/49, run `20261022-000658-pt1-runloop-runloop`; a
  repeat run 49/49, `20261022-001322-pt1-runloop-runloop`.
- At every arrival the guest reports map, body (character possessed), car, backpack count, time of day, weather override
  count; the host compares: same map, guest has a character, car on both sides, zone time of day within 0.03 and equal
  weather override count. After the gateway return the guest's 10 steel are still there (P5); after the failure it has 0 and
  the host's guest file says 0 (the host's penalty hits the guest too).

## Derived

- Guest rejoin after native travel works in both directions (garage->zone, zone->garage via TravelToGarage 2 and 3).

## Guesses / Unknowns

- Mutation nokeep (keep-listen off): 22/49, run `20261022-004358-pt1-runloop-runloop-nokeep`.
- Not driven: the portal's car-in-range trigger (TravelToGarage is called directly), the ARC screen's own press (the
  summon is the call the screen makes), route planning on the route map (TravelToNextLeg uses the fixture's chosen leg),
  the real emergency-protocol trigger (car critical) and the widget click (the widget's calls are made directly).
- The failure penalty removed all 10 items (`RemoveItemsPenalty(-1)`); partial loss is not tested.
