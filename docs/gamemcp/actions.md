# Game MCP actions

Tools that make a player do things in a RUNNING test game, one call each, for exploring gameplay
without writing a scenario first. Part of the `pacific-game` MCP (`docs/GAME-MCP.md`); code in
`tools/gamemcp/ext_actions.py` (tools, journal, promote) and `test/PacificTogetherTest/Scripts/mcp_actions.lua` (the
actions, run on the game thread). Test pairs only, never the real install.

Every action returns text that starts with `path:` (which game code did the work, and a clearly marked `FALLBACK` when it
was not the game's own path) and ends with state read back from the game. All take `side` (`host` default, `client`)
and `root`. The console cannot block, so an action starts in Lua and the server polls it until it finishes (default
limits 15-60 s, listed below); a stuck action is cancelled and reported.

Exploring is not proving: turn what you learn into a scenario (`promote`, below) and a check with a mutation.

## Tools

| Tool | What it does, and the game path it uses |
|---|---|
| `teleport` | `location=[x,y,z]` (uu, 1 m = 100) or `actor=<path or "nearest <Class>">`; beside the actor (`offset` 150) or exactly there (`exact=true`). `BaseCharacter:K2_HandleSetCharacterLocation`, the game's own player placement (what `BPI_TeleportPlayer` calls); `K2_SetActorLocation` only if it did not land (said in the result). Refused in the car. |
| `look_at` | camera to a point or actor (an interactable's collision centre) with `PlayerController:SetControlRotation`, which is where mouse look ends; result has the angle error read back. |
| `move_to` | walk to a point/actor: `PDP_MainCharacter:"Command Move Forward/Backward"(1.0)` every frame with the camera turned to the target (that handler stores an axis which real input rewrites every frame, so one call moves about 4 uu). Ends on `radius` (80 uu), stuck (< 20 uu in 1.5 s) or `timeout` (15 s); `sprint=true` adds `Command Sprint`. Reports distance walked and left. |
| `jump` | `"Command Jump"` pressed, released after 8 frames; stands up first when crouched (a crouched jump does nothing). Reports peak height and air time. |
| `crouch(on)` / `sprint(on)` | `"Command Crouch Toggle"` only when the state differs / `"Command Sprint"(on)`; reports `bIsCrouched`, `ALS_Gait` (1 run, 2 sprint) and `MaxWalkSpeed` read back. |
| `interact(target)` | what the interact key does: aim at the target's highlight collision, wait until `BP_HighlightManager.CurrentHighlight` is the target, press `"Command Interact"(true)`, hold, release. `target` = object path or `nearest <Class>`; `component` picks a highlight (e.g. `Highlight_EnterDoor`); `hold` overrides the hold (default: a 0.3 s tap, or the component's short/long duration + 0.5 s when it has one, e.g. 0.88 s for world items; measured in GAME seconds, because a loaded machine runs the game slower than real time and a real-time tap of 0.3-0.5 s then picked nothing up); `close_menu` (default true) closes a menu the interaction opened. Result: which `HighlightComponent` entry points fired (`InteractPressed/Released`, hooked on first use), backpack count / menu / highlight before and after, and which scalar properties of the target changed (door `IsClosing`, lid animation, ...). The trace starts at the camera (75 uu above the pawn), reaches 160 uu and is blocked by walls, so when out of reach it **teleports** next to the target and tries up to 16 spots on a ring around it (`approach=false` forbids that); the result says how many teleports. If the game never highlights it, the result says NOT interactable and nothing was pressed. |
| `enter_car` | host only. 1) the game's own door interaction: press the driver's door handle (the allowed `BP_CarPart_Interactive_C` / `BP_CarPart_Door_Base_C` nearest the car's `Highlight_EnterDoor`); the door opens, the character walks in, `PlayerCarState` goes 0 -> 2 -> 1 in about 3 s. 2) `BP_CarPart_Door_Base:StartEntry(false)` on `SLOT_FrontLeftDoor` (the call behind the enter-door highlight). 3) `Possess(car)` as a named FALLBACK. The result lists what was tried. |
| `exit_car` | host only. `BP_PlayerCarNew:ManualActivate_ExitDoor` (what the exit-door highlight calls), `Possess(character)` fallback. |
| `car_start` | host only. `ManualSetIgnition_NoAnim(2)`, `ManualActivate_Gearbox(0)` (drive), `VehicleController:SetParkingBrakeActive(false)`: the car's own manual entry points, no key animations. Note a started car in drive creeps by itself. |
| `drive(throttle, steer, brake, seconds)` | host only. `BP_PlayerCarNew:AccelerateBrake` + `SteerLeftRight` and the vehicle controller's `ThrottleInput/BrakeInput/SteerInput`, every frame, for `seconds`; needs `enter_car` (the game's own `PlayerCarState` 1, or a Possess) and `car_start`. Reports position, speed, distance moved and top speed. |
| `car_stop(park)` | host only. `AccelerateBrake(-1)` until stopped, then gearbox to park (`ManualActivate_Gearbox(1)`) and the parking brake. |
| `give_item(item, count)` | `BP_InventoryManager:GiveItemToPlayer(archetype)` `count` times (the game's own give, used by its `DbgActEvt_Give*` events). `item` = full asset path, `IA_Name`, the name's tail (`Raw_Scrap_Steel`) or a unique part; only archetypes the game has loaded can be found by name (`item_search`). Reads the backpack back. |
| `spawn_item(item, location/actor)` | `InventorySystem:SpawnItemActor` (how the game puts an item in the world); above an actor it drops 60 uu above it. Returns the actor's full name. |
| `spawn_actor(class_name, location/actor)` | engine deferred spawn (`GameplayStatics:BeginDeferredActorSpawnFromClass` + `FinishSpawningActor`); the game has no own spawner for arbitrary classes. `class_name` = `/Game/.../BP_X.BP_X_C` or a class with a live instance. |
| `pickup(target)` | the `interact` path on the item (hold included); if the backpack did not grow, the character's own `"Pickup Actor"(item, false)` and the result says FALLBACK. |
| `drop(slot)` | `ItemSlot:TransferStackIntoContainer(hand)` then `BP_InventoryManager:PlayerDropHandItem`; drops one item of the stack (reported count change). |
| `inventory`, `item_search(query)` | backpack and hand contents; loaded archetype names containing a text. |
| `journal(tail)`, `promote(name)` | below. |

Targets: an actor is an object path / full name (`find` gives them; a class name works too: its first live instance) or
`nearest <Class>` (nearest to the player; includes subclasses, so `nearest BP_Door_Single_C` found a `BP_Door_Double_C`).
The garage streams sub-levels (`Garage_Art`, `Garage_Mission`) whose actors have their own `World`; they count as live, the
`/Engine/Transient` copies with no world do not.

## Journal and promote

The server appends every `eval`, `call` and action to `<root>/mcp-journal.jsonl` (time, tool, side, arguments, ok, first 400
chars of the result); `session_start` clears it. `journal` shows the tail.

`promote(name)` writes `test/PacificTogetherTest/Scripts/scenarios/<name>.lua` from the journal since the last
`session_start`: fixture or map steps from the session's arguments, then one `T.act_begin(...)` step and one `check` per
action (passes when the action finished without error), with a `-- TODO check` line each and the explored result as a
comment. It skips failed calls and interactions the game refused. It is a skeleton: replace the TODOs with assertions on
the numbers in the result, add a mutation, run it with the command in its header (`run-test.ps1 -Scenario <name> -Clients 1
-Headless -Fixture <f> -FixturesDir <main>\local\fixtures`). `eval`/`call` entries are replayed with `T.mcp_run`.
Actions in a scenario: `id = T.act_begin(name, opts)` then `T.act_done(id)` -> `done, text, ok`.

## Validation

`python tools/gamemcp/selftest_actions.py --root C:/PTLanes/<lane> --port <n>` starts a headless garage session.
The original run recorded 30/30 tool checks; its promoted scenario recorded 27/27 completion checks. These are
historical tool checks, not gameplay-sync acceptance tests. Replace generated TODOs with state assertions and mutations.

## Limits

- **Remote player (`side=client`)**: the actions run the guest's OWN game. `interact`/`pickup` work through the game's path
  there only when the guest has its own `PDP_MainCharacter_C` (the host spawns and possesses one, M2/X13), and execute locally. Shipping gameplay modules may forward those actions to the host; the tool itself does not.
  Check both sides to establish synchronization. Without a character the tools fail with
  "no character: the controlled pawn is ...". The car tools refuse `side=client`.
- `interact` and `pickup` **teleport** to a spot with a clear line of sight (said in the result); they do not walk there.
  Use `move_to` first when walking matters.
- `drive` writes the car's inputs every frame from Lua, not through real key input; the game's physics does the rest. Steering
  and braking are only checked by the position/speed the result shows.
- Item pickup by interaction needs the hold (see `interact`); a long press on a car door does NOT open it, so the hold is per component, not one default.
- A first look at a far object can show stale collision bounds (all zeros): `enter_car` stands next to the car first; `interact` falls back to component locations.
- A menu left open blocks movement and jumping; `interact` closes the menu it opened by default.
- The ProcessEvent hooks that record `fired` are installed on first `interact` (one `RegisterHook` per entry point) and stay
  until the game ends; reloading `mcp_actions.lua` with `loadfile` (not `require`, which is cached) installs them again.
- Only one action runs sensibly at a time per side: they share the camera and movement.
