# M6 playpath: the guest with real input (lane `input`, 2026-10-21)

Every feature so far was proven by scenarios that call the game's functions. This lane drives the same features the way a
player does: the guest walks (`Command Move Forward/Backward` every frame), aims (`SetControlRotation`, then waits until the
game's `BP_HighlightManager` has the target), presses interact (`Command Interact` held for the highlight's own duration), uses
the loot menu's own transfers, and the host abandons through the pause menu's own confirm handler. Scenario
`test/PacificTogetherTest/Scripts/scenarios/playpath.lua` (fixtures `garage` and `zone`), actions `door_press` and `use_tool` in
`mcp_actions.lua`.

Runs (all headless, two clients): `20261021-165016-input-playpath` garage 24/24; `20261021-165825-input-playpath` zone 39/39.
Mutations: `nocarsync` garage 19/24 (`20261021-170231-input-playpath-nocarsync`), `nointent` zone 27/39
(`20261021-170947-input-playpath-nointent`). Before the two fixes below the zone run was 34/38 and, by the log, path 7 was
broken even though its old check passed (`20261021-165423-input-playpath`).

## Per path

| # | path | result |
|---|---|---|
| 1 | guest walks to the driver's door, presses its handle -> seated; exit -> out | works (door), exit key unverified, see below |
| 2 | guest opens a container with interact, moves a stack to its backpack, closes the menu -> host container lost it | works (move is the menu's own `TransferStackIntoContainer`, not the mouse) |
| 3 | trunk the way a player does | still broken / not drivable headless, see below |
| 4 | repair putty / fuel can from the hand, aimed at part / gas cap, use key | not drivable headless, see below |
| 5 | ARC screen: hover and press the gateway | not driven (see below) |
| 6 | guest picks up a world item with interact -> gone on the host | works |
| 7 | host abandons through the pause menu -> both in the garage, guest penalty, session alive | fixed (2 bugs) |

### 1 car door
Observations
- Only the DRIVER's door leads to `EnterCar` (`BP_CarPart_Door_Base` ubergraph: door location 0 starts entry, every other door only
  opens or shuts). A guest that presses the passenger door gets nothing; pressing the driver's handle seats it in the passenger
  seat (`g.car.enter` from the `EnterCar` hook, car.lua). The playtester must be told this.
- The handle (`BP_CarPart_Interactive` child actor) is what the highlight finds, not the door part; the press must be a 0.3 s tap
  (a longer hold does not open it).
- Pressing the passenger door's handle on the guest: the part gets `InteractPressed`, the door stays closed (kinematic car,
  no physics on the guest).
- A guest's own teleport (what `interact`'s approach does) is undone by the server; only walking or a host-side move counts.
  The car stands in a bay: walking straight to the driver's door from the far side is blocked by the car and by the wall.
- Exit is `RegisterKeyBind(Key.X)` (UE4SS, polls the keyboard). It cannot be pressed headless; the check sends the same intent
  (`g.car.exit`) and the host unseats the guest. The key bind itself is untested. The game's own exit highlight
  (`Highlight_ExitDoor`) is not allowed for the guest (its car state is 0).
Result: works. Unknown: the X key.

### 2 container
`interact` on the guest's copy opens the menu (`RolledOnOpenItems` flips on the guest, loot.lua's flags keep the host's contents).
`UMG_PlayerMenu_Inventory.TransferContainer` is the container; the click path is `Get Slot To Pickup` -> `BuildLinkageScheme` ->
`ContainerCursor:TransferSlotWithLinkage` (native, takes struct arrays: calling it from Lua with a wrong struct crashed the game,
`20261021-163131-input-repl`). The check uses what the grab path calls: `slot:TransferStackIntoContainer(hand)`, then the hand
slot into the backpack, then `RequestPlayerMenuClose`. The host's container lost the item.
Not done: a real mouse click / drag (needs a window), the `Try Pickup Slot` / `MouseDoubleClickTransfer` events did nothing when
called without a real hovered slot.

### 3 trunk
The trunk door and its storage have no highlight collision entry (`BP_Storage_Trunk_Base_C.Highlight.HighlightCollision` has 0
entries); the trunk door's handle takes `InteractPressed` on both host and guest but the door state stays closed and no menu opens
(host and guest alike), so this harness cannot tell a guest bug from a headless limit. Still open: the owner opens the trunk as a guest
and says what happens.

### 4 tools
`BP_BaseToolHoldUntilComplete_Manifestation.TrySpinUp` re-reads `GetHighlightedActor` (the highlight manager), so the tool's target
has to come from a real highlight on the part. In a headless run the highlight manager never highlighted a body panel, a door
(the door's handle wins) or the gas cap (null highlight collision) with a tool in hand, on the HOST as well, so this is not a guest
bug. Setting `TargetedActor` by hand does not start the tool. What is proven (guestact scenario): the effect points
(`PatchPart`, `TransferFuel`, `ChargeBattery`) and the host applying the guest's intent. What is not: the aim, the use key
(`ToolPrimaryUse` = left mouse button, delivered as `InpActEvt_ToolPrimaryUse_..._2/_3` on the tool). `PlayerController:InputKey`
is native-only and cannot be called from Lua.

### 5 ARC
The screen takes `InteractPressed` from the seated guest (`ScreenHighlight` is allowed). The gateway choice is hover (cursor box select
over the map icons each tick, `UMG_Gobbler_Cursor.TickSelection`) then a HOLD on the select action (`UseSelectedWidget` ->
`BP_LevelTransition_ExitPortal:StartPress` ... `PressComplete` -> `ExitUseComplete` -> `OnExitUseComplete`, the guestact hook). Not driven
in this lane: needs the cursor moved over an icon on a rendered map.

### 6 world item
`interact` with the highlight's own hold (0.88 s) on the guest's copy: the item is in the guest's backpack and gone on the host.

### 7 abandon
Real path: pause menu -> Abandon -> confirm popup -> `PDP_PauseMenu:OnReturnGarageSelected(1)` (sets `WB.ActiveRun.RunAborted`,
`RemoveItemsPenalty(AbandonRunConsequences)`, `SaveTombstoneRunInfo`, `TravelToGarage`). The run calls that confirm handler. Pressing the
Abandon button handler itself in a headless host crashed the host (`20261021-164547-input-repl`, access violation reading
0x178, popup creation); not investigated, headless only is likely.
Bugs found and fixed:
1. The guest "died" 3-4 s after EVERY level change (`health guest died` in the old sessiontravel logs too): a fresh level starts
   at `Minimum` 1 until the game fills the health, `health.lua` took that for a death, dropped the whole backpack as a crate at the
   host's car and black-screened the guest. Fix: `health.lua` dies only after it saw health above 1 in this level.
2. The abandon's penalty was undone: the guest applied it (10 -> 0 items), its save to the host was lost in the travel, and on
   rejoin the host's older record (10 items) overwrote the guest's backpack. Fix: `backpack.lua` keeps the unsaved post-penalty
   line and, when the host answers with an older record, keeps its own backpack and sends it.
After the fixes: no death crate, the guest's backpack is the penalized one (`bp guest keeps its backpack over the host's older record`).

## Files
- new: `test/PacificTogetherTest/Scripts/scenarios/playpath.lua`, this doc.
- test code: `mcp_actions.lua` (`door_press`, `use_tool`, `T.action_event`, `interact` reach 160 uu when `approach=false`).
- shipping: `health.lua` (death only after health was seen above 1), `backpack.lua` (unsaved line kept over an older host record).
- shared: `tools/run-test.ps1` (`playpath` in `$Defaults` and `$AutoJoin`).

## Observations / Derived / Guesses / Unknowns
Unknowns: the X key; trunk; tool aim and use key; ARC hover and hold; the real mouse in the loot menu; Abandon button popup in a
windowed game; two guests.
