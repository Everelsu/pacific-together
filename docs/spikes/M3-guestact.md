# M3 guest actions (C5, W11, D13, D22)

> Historical research; see the [index](README.md) for current implementation and later evidence.

Code: `mod/PacificTogether/Scripts/guestact.lua` (uses car.lua's exports). Scenario: `guestact` (`tools/run-test.ps1 -Scenario guestact -Fixture gateway -Headless`,
mutation `noguestact`). Results: `20261021-130017-act-guestact` 31/31, `20261021-133607-act-guestact` 31/31 (after throttling), mutation
`20261021-130524-act-guestact-noguestact` 24/31 (7 host/ARC checks fail).

## Observations

- UE4SS `RegisterHook` callbacks on Blueprint functions run AFTER the function returned: out parameters hold the result, but state read in the
  callback is already the new state. That is why heal, battery and fuel read the amounts the game's own functions report
  (`HealDamage` Amount_Healed, `ChargeBattery` Amount Charged, `TransferFuel` Transferred) instead of diffing before/after.
- A hook on a native function (`VehicleControllerComponent:GetSpeed`) fires but the callback gets no parameters and no return value: the result cannot be replaced.
- Effect points (the guest's real tool actors, in hand via `GiveItemToPlayer` + `TransferStackIntoContainer(hand)`):
  `BP_Tool_Target_Consumable_PatchKit:PatchPart` (heals `TargetedActor`'s health by the kit's HealAmount, 35 for the basic kit),
  `BP_Tool_Target_Consumable_ChargeBattery_Base:ChargeBattery` (via `BP_BatteryChargerComponent.DoCharge` -> `BP_BatteryComponent:ChargeBattery`),
  `BP_FuelableComponent:TransferFuel(Source, Target, Mult)` (0.13 per call from the can into the car's `BP_FuelableComponent_GasCap`, which reports and fills the tanks),
  `BP_Carpart_Internal_GobblerScreen_C:OnExitUseComplete(portal)`, `BP_Carpart_Internal_Gobbler_C:AddingAnchorCompleteLogic(anchorInstance)` (stable M anchor = +1.1 charge).
- `Set Battery` does not clamp to the capacity (a +28 intent made 58/30); the host clamps. `Set Fuel` on a spawned tool actor without an item instance stays 0.
- ARC charge is an item property of the Gobbler item instance (`GetGobblerItem`); on the guest it was 0/0 and `AbleToChooseExit` false. `GetAnchorCharge` on the screen part reads it.
  `InventoryBlueprintLibrary:SetItemProperty(IP, instance, name, value)` takes the property definition `/Game/Gameplay/Inventory/Items/Car/Internal/Gobbler/IP_Gobbler.IP_Gobbler`
  and the float's raw 32 bits as `Value` (a Lua float is read as an int32 and gives denormals).
- The gateway: the guest's screen is held at `AbleToChooseExit=false` (only read by the `popifnot` in `OnExitUseComplete`), so the guest's own chain never summons;
  the hook sends the portal name, the host checks its own `AbleToChooseExit` and calls `Select Exit Portal Actor`; world.lua shows it on the guest (checked: guest's `EvolvedGatewayExit` follows).
- Crash seen once with an eval-registered probe hook plus the module's own hook on `TransferFuel` while a tool actor was spawned without an item (client `0x248` read); not reproduced with the module alone.

## Derived

- Intents: `g.act.heal slot amount`, `g.act.fuel slot class amount` (negative = siphoned), `g.act.bat slot amount`, `g.act.gate portalName`, `g.act.anchor archetypePath`;
  host to guest `g.act.arc cur max charged` (1 s, on change and every 3 s). Heal/charge are noted by the component hook and sent only when the tool's own hook confirms within 0.5 s,
  so garage stations, evolution and the guest's own car systems calling the same functions are not forwarded. Item consumption stays in the guest's backpack.
- The guest's local effect shows at once and the host's state message (car.lua, on change) overwrites it with the host's result.
- Part install/remove needs nothing new: the state message mirrors the car equipment container; the guest's own install is overwritten.

## Guesses

- The real input path (tool in hand, aiming at the part, hold) ends in the same functions; the scenario sets `TargetedActor` and calls them directly (headless has no highlight).

## Unknowns / gaps

- Installing/removing parts by the guest through the game's UI is not wired: a guest's local install is overwritten by the host's state (not tested with real input).
- Speedometer needle / RPM / engine audio on the guest: the needle reads `GetSpeed` (native, 0 on the kinematic car). A post-hook on the speedometer part's `ReceiveTick` that turns `SpeedArm` (roll = cm/s * 0.036 * 0.6214 * 1.5556 * 2) did not move the needle in carsync (not debugged); reverted. Horn, wipers, headlight beam not done.
- Passenger camera wobble: carsync `guest_camera_rides` measured 29 to 109 uu against the 40 limit across runs on a loaded machine (4 lanes); lower when the guest has no extra per-frame work. Not fixed in the ride code.
- Route planning stays host-only (D22). Anchor deposit by the guest sends the archetype and the host rebuilds an instance: item properties of the actual anchor (unusual anchors) are not carried.
- The ARC `Charged` widget flag is mirrored, the real hover/press UI on the guest was not driven.
