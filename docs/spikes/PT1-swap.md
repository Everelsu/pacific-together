# PT1 swap: the guest works on the car (PLAN C5, C6, W1)

Lane pt1-swap, branch worktree-agent-a26480ef0085121cf. Code: `mod/PacificTogether/Scripts/guestswap.lua` (+ `"guestswap"` in FEATURES),
scenario `guestswap` (`tools/run-test.ps1 -Scenario guestswap -Fixture gateway -Headless`, mutation `noswap`).

## Results (local/test-results)

- `20261022-010506-pt1-swap-guestswap`: 32/33 on the code of that time (all part checks and the trunk take passed; the trunk put-back check compared with the
  start count and failed, see Unknowns). Scenario reworked afterwards to compare the host's trunk with the guest's count.
- `20261022-015210-pt1-swap-guestswap-noswap`: mutation 27/33, the part checks FAIL as the playtest did (host door never removed, guest slot refilled by the
  host state with the door also carried, install does not reach the host).
- `20261022-023906-pt1-swap-guestswap`: 33/33 with the reworked scenario (host trunk equals the guest's after the take and after the put).

## Observations

- Before the fix (live console, gateway fixture, `20261022-000523-pt1-swap-repl` pair): the guest's `BP_CarManager_C["Swap Equipment"](1, interactActor)` takes the
  door off into the guest's pack/hand and empties its local slot; the host never hears of it, its state message (car.lua, every 3 s) puts the door back
  into the guest's slot: the guest then carries the door AND the car has it (dupe), the host's car never changed.
- Game functions: `BP_CarManager:Swap Equipment(SwapAction, InteractActor, out Success)` (the end of the hold-to-swap, `SetSwappingEquipment` is the
  hold UI). `CanSwapEquipment` translates the action: 0 install from hand into an empty slot, 1 take off into hand/pack, 2 swap with the hand (empty hand
  turns it into 1), 3 easy swap. It ends in `ItemSlot:SwapSlotContents` / `Player Give Item`. The interactive actors (`BP_CarPart_Interactive_C`, one per slot, `GetSlot` out
  `TagName`) exist on both sides, also on the guest's replicated car.
- Out-parameter keys with spaces are keyed with the space (`"Can Swap"`, `"Hand Slot"`).
- Fuel (`g.act.fuel`) and battery (`g.act.bat`) by the guest were already forwarded and proven in `guestact` (31/31). The trunk (`Inventory_Trunk`,
  `Inventory_LargeTrunk`: the roof rack and side storage parts only add capacity to the same container) was proven both ways in `lootsync`.

## Derived

- Fix: a post-hook on `Swap Equipment` on the guest sends `g.swap.set slot<TAB>spec` (the slot's content after the swap, ids.lua item string, "-" = empty). The host
  applies it to its equipment container (remove, or SetItem of a fresh instance with the item state). The removed part exists once: as the guest's own item.
- car.lua's `applyState` skips a slot the guest swapped in the last 4 s (`car.holdSlot`), so a state message that was already on the way cannot undo the swap.

## Guesses

- The real hold-to-swap input ends in `Swap Equipment` like the scenario's direct call (the headless pair has no highlight to point at).

## Unknowns / gaps

- Real hold-to-swap input with the highlighted part on the guest was not driven (interactive actors on the guest's replicated car are local actors; not checked
  whether the guest's highlight finds them).
- Replace (swap with a different part in hand) uses the same hook (slot content after the swap) but only remove and install are in the scenario.
- A part the host removed/installed at the same moment as the guest: last writer wins.
- Trunk (loot.lua, not changed; the reworked scenario compares host with guest and passes, so this is a count drift of the full fixture trunk, not a host/guest split in that run): in the gateway fixture the guest took a stack of 10 headlights out of the full trunk (46 items): the host's trunk went 46 -> 35
  (one item more than the guest took), and after the guest put the 10 back the host had 45 while the guest had 46. Likely `ids.apply` rebuilding a stack in a
  full container on the host (spec merge / reuse of an "extra" item); not investigated (lootsync2 area).
- Fuel/battery by item (jerry can into the car, charger) not repeated here; see `guestact`.
