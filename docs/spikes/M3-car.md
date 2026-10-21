# M3 car (C1, C2, C3, C4, C7)

Code: `mod/PacificTogether/Scripts/car.lua`. Scenario: `carsync` (`tools/run-test.ps1 -Scenario carsync -Fixture garage -Headless`,
mutation `nocarsync`). Result folders: `20261021-114505-car-carsync` (36/36 with the door path), earlier
`20261021-113933-car-carsync` (intent only, before the reach check was dropped), `20261021-112004-car-carsync` (crash, see below).

## Observations

- The guest's replicated car (Role 1) builds its 124 attached part actors from the guest's own car equipment container
  (`BP_InventoryManager_C:GetCarEquippedContainer`, 81 slots named `Car.Equip.*`, one ItemInstance per installed part). The guest's own
  Role 3 car has the same. So part sync = sync that container; `GetItemManifestationEquippedInSlot` returns the part on the replicated car.
- `slot:RemoveAllItems({})` removes the part actor at once; `archetype:CreateInstance(ctx, 0)` + `slot:SetItem(inst, {})` installs it and the
  part actor appears in the same call.
- Health, fuel, battery live in property components on the part actor: `BP_HealthComponent_C` (`GetHealth`/`SetHealth`),
  `BP_FuelableComponent_C` (`GetFuelStatus`/`Set Fuel`), `BP_BatteryComponent_C` (`GetBatteryStatus`/`Set Battery`). Setting them on the guest moved
  `BP_CarManager_C.AggregateFuelCurrent` / `AggregateBatteryCurrent` to the host's values within 1.
- Door part `BP_CarPart_Door_Base_C:StartEntry(false)` (what the highlight calls) -> `EnterCar` -> broadcast of the character's `CommandEnterCar`.
  `PTNative_Mute` on the guest's own pawn drops `CommandEnterCar` AND the Lua hooks on it, so the intent hooks the door's `EnterCar` instead.
- After the door flow the host's char is attached with PlayerCarState 1 and the PC does not possess the car in a headless run
  (`Possess` fallback as in X7/X8); not investigated.
- A UE4SS hook parameter (`self`) must not be used after the callback returns: `self:get()` 500 ms later crashed the guest
  (EXCEPTION_ACCESS_VIOLATION 0x40, run 112004). Capture `self:get()` inside the callback.
- A client-side `K2_HandleSetCharacterLocation` of the guest's character does not move it on the host (the host measured the guest 8675 uu from the car
  when the scenario "walked it to the door"), so the host side has no reach check on the enter intent.

## Derived

- Host broadcasts one text message (`g.car.s`, ~5 KB, on change and every 3 s): head line (ignition, gear, lights, handbrake, door bits) plus one line per
  installed part (slot, archetype path, health, fuel, battery) and a count line the guest checks before applying.
- Guest applies by installing/removing parts to match and setting the three values; ignition/gear/lights/doors/handbrake through the manager and car functions.

## Guesses

- Real input on the door highlight goes through the door's highlight-interact event and then `StartEntry`; only `StartEntry` was driven in the test.
- Guest saves would contain the host's car; `safety.lua` blocks guest saves (S7).

## Unknowns / gaps

- Flat tyres (status effect on the wheel), wipers, horn, radio, headlight beam on the guest are not synced (wheel health is).
- Guest speedometer: the guest's car is kinematic, so the speed dial does not move (not checked).
- The guest's brown-blotch camera overlay (X8) is not investigated.
- Exit is key X while seated (intent `g.car.exit`); the game's own exit door interaction is not wired for the guest.
- Doors opened by SetDoorState on the guest were not checked visually.
- No reach check on the enter intent; two guests are not handled (one passenger seat).
- Map change with the guest seated: session.lua removes the guest's character before travel, so it is unseated by that; not tested with the car.
