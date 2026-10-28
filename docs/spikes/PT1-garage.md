# PT1 garage: doors (bug A), garage parts (bug B)

> Historical research; see the [index](README.md) for current implementation and later evidence.

## Observations
- Fixture garage, `-Scenario repl`, headless, game MCP-less probes (2026-10-21). Standalone (vanilla, PT main mod off): rear door
  `BP_GarageDoorRear` Opened, `CurrentDoorPosition` 1.0; the button (`BP_BackDoorButton_01.Highlight:InteractPressed`) toggles
  `GSS_Garage_RearDoorOpened` and the door moves (Closing/Opening, then Closed/Opened).
- After `open <map>?listen` (listen host, PT mod OFF): rear door sits Closed at 0.0 with `TryOpening=true`; the switch toggles but
  the state machine never leaves Closed. So the fault is the engine's listen mode, not our rewriting.
- Door state machine components (`DoorStateMachine`, Logic Driver `SMStateMachineComponent`): `NetworkTickConfiguration=0`,
  `NetworkTransitionConfiguration=0` (client only), `NetworkStateConfiguration=2`. Setting the first two to 2 live made the door
  move again in the same listen session (Opening 0.71 -> Opened 1.0).
- Switches: `GSS_Garage_FrontDoorOpened` is set every tick by `BP_Director_GSS_GarageFrontDoor` (scanned leg AND can embark),
  `GSS_Garage_RearDoorOpened` by the back-door button (state name `ButtonToggle`, ESwitchPosition ON=1, OFF=2),
  `GSS_Garage_ExitGateOpened` by `BP_Director_GSS_GarageExitGate`. Directors have `SetTickEnabled`.
- `ForceDoorToCompletion` called from Lua right after map load crashed the host (access violation 0x18); the debug event
  `DbgActEvt_Force Open Door_Execute` is safe.

## Derived
- Playtest "no door ever opened" = listen host's door state machines never run; the guest's own switches would also disagree
  with the host's (its directors read the guest's fresh game).

## Fix (mod/PacificTogether/Scripts/garage.lua, FEATURES "garage")
Both sides set the doors' network config to 2; the host sends the three switch values (`g.garage.sw`), the guest stops its two
directors and applies them with the game's own state names. Mutation `nogarage`.

## Unknowns / not done
- Bug B (Unmaker, fax, rooms on the guest): not started beyond reading the bytecode. Garage upgrades are item status effects
  in per-station slots (`BP_GarageInstallation_Spawner.InstallSpecificUpgrade`, `FindOrCreateGarageUpgradeSlot`); progression.lua
  syncs only the whiteboard tags. Needs a live host with upgrades installed to see what a guest's spawners lack.
- Scenario `garagesync` written, not yet run: the runner waited hours for a free game slot (3 slots, 6 lanes).
- Front door and "car drives out" not tested.

## Update (later in the lane)
- The config fix (`NetworkTickConfiguration`/`NetworkTransitionConfiguration` = 2) did NOT hold in the real two-player flow (door stayed Closed even
  with component tick on and after `Restart()`), so the shipped fix drives the door itself: every 50 ms `MoveDoorPosition` toward the switch's
  target over `MoveDuration`. Result `20261021-224850-pt1-garage-garagesync` (doors only) 22/22; mutation `nogarage` fails the 4 open/reopen checks.
- Bug B: each level-placed `BP_GarageInstallation_Spawner_C` (about 70: stations, Fax `BP_GarageStation_Fax`, framed mounts ...) keeps its upgrade as a
  status effect on the item in `BP_InventoryManager_C:FindOrCreateGarageUpgradeSlot(archetype, installTag):GetItem(0)`
  (`BP_StatusEffectManager_C:GetStatusEffects(item)`). Spawner actor names are equal on both sides. The host sends "name<TAB>class paths"
  (`g.garage.up`, every 4 s or on change); the guest calls the spawner's own `InstallSpecificUpgrade(class, true)` for missing ones.
  Result `20261021-230421-pt1-garage-garagesync` 25/25 (host installs the fax upgrade, the guest's fax slot gets it); `nogarage` 20/25
  (`20261021-231159-...-nogarage`).
- Unmaker: not named in the game's classes found (`find Unmaker` empty); the mechanism is generic over every spawner, so it is covered if it is a spawner
  upgrade, not verified by name.

## Not verified
- Front door / exit gate switch sync (code applies all three switches, scenario drives only the rear button); car driving out; obstruction reversal.
- Upgrades removed on the host (a deconstruct) are not removed on the guest; guest-side upgrade actors' own build animations.
- Rooms opened by the host (hidden-actor lists) are driven by the same spawner install (`GetHideActors`), not separately checked.

## Follow-up (rebased on main 7a0c687)
- Geometry (fixture): car in the yard at (-3847,-1883); rear door (-360,-496) faces -X; front door (771,-496) faces +X; the road is beyond x=771.
  A waypoint autopilot (steer by yaw error, throttle 1: (-1800,-1000) (-700,-496) (400,-496) (2500,-496)) drives the car out through both
  doors in about 20 s and it ends at x=3355. `GSS_Garage_ExitGateOpened` is only the level-transition switch (the director copies the front door's), not a
  blocking gate.
- Front door: its director writes the switch every frame (scanned leg AND can embark), so the scenario stops it and sets state `LegSelectedAndEmbark` ON,
  which is what a chosen route does. Setting another state name did not turn the switch on.
- Guest presses the rear button: post-hook on `BP_BackDoorButton_01_C:BndEvt__Highlight_..._OnHighlightInteract__DelegateSignature` (registered when the
  class is loaded) sends `g.garage.btn`; the host presses its own copy. Proved: guest press closes the host's door.
- Unmaker: no class or string of that name exists in the atlas or dumps. The shredder station (`BP_GarageStation_PartShredder`, upgrade
  `UP_Garage_PartShredder_Install`) is the closest guess ("unmaking" parts); fax, shredder and destabilizer are all spawner upgrades and all reach the guest.
- Results: `20261021-232034-pt1-garage-garagesync` 34/34; `nogarage` `20261021-233202-pt1-garage-garagesync-nogarage` 23/34 (11 FAIL: doors, exit gate,
  parts, car stuck behind the closed doors).
- Still not driven: a real route selection opening the front door; the guest riding in the car through the doors; obstruction reversal.
