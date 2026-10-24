# PT2 stations: the guest uses the garage stations (PLAN G2, D21)

> Historical research; see the [index](README.md) for current implementation and later evidence.

Lane pt2-stations. Code: `mod/PacificTogether/Scripts/stations.lua` (FEATURES "stations"), small additions in `garage.lua` (`M.applying`, `M.installedOn`,
`M.hostHas`), scenario `stations` (`tools/run-test.ps1 -Scenario stations -Fixture garage -Headless`, mutation `nostations`); the old one-game research
probe is now `stationsprobe`. Research behind it: `docs/research/garage-stations.md`.

## Design

The guest keeps the game's own station UIs and functions (they are local). What each station does to SHARED state is turned into an intent, the host
performs it, and the existing syncs show the result: loot.lua (world items, garage storage), progression.lua (research graph host->guest), garage.lua
(installed upgrades host->guest).

| Station | Guest side | Host side |
|---|---|---|
| Part Shredder ("Unmaker") | hook `BP_Garage_PartShredder_C:ShredItem` collects the item specs and empties the local `SmashedProducts` (no second copy); `g.st.shred` 0.4 s after the last item | puts the items into ITS shredder container and calls `OnTransactionEnd` (what closing the container does); products come out of the host's dispenser one by one as world items, loot.lua shows them to the guest |
| Research / blueprints | pre-hook `BaseGenericGraphState:PurchaseNode` sends `g.st.buy node`; while it runs `InventoryRecipe:ExecuteRecipe` is emptied (the cost recipe: the host pays), so the guest's local purchase returns false | `SetActiveTier(3,true,true)`, `PurchaseNode(node)` (pays from host backpack, garage, car), then the bench's own `OnNodePurchased(node)` (prints the blueprint / upgrade kit); progression.lua mirrors "purchased" to the guest |
| Garage upgrade | hook `BP_GarageInstallation_Spawner_C:InstallSpecificUpgrade` sends `g.st.up spawner<TAB>class` unless garage.lua applied it (`garage.applying`) or the host's list already has it (`garage.hostHas`: level defaults are installed by every spawner's BeginPlay) | `InstallSpecificUpgrade(class,false)` on the same spawner unless already installed (`garage.installedOn`); garage.lua shows it back |
| Tinker: quirk list and cure | host sends the quirk list (`g.st.q`, condition and behavior class paths, diagnosed flag, cure ingredient); the guest builds the same quirks with `BFL_StatusEffectQuirkUtils:BuildAndApplyQuirk(cond, beh, world)` and re-rolls until the random cure ingredient matches (max 40 tries), drops quirks the host does not have. A cure in its own UI (`CureCarQuirk` post-hook, Removed=true) sends `g.st.cure cond\|beh` | host does the rest of the cure WITHOUT paying again: bounty XP (`CA_MechXP`), `SendQuirkToGraveyard`, `RemoveStatusEffect`, `QuirksCured` +1, quest `OnCuredQuirk`. The cost was paid once, on the guest, from its own backpack and the garage that loot.lua syncs |
| Fabrication | unchanged: local `Craft Recipe Asset`, garage materials ride loot.lua's storage sync (`host_garage_lost_exactly_the_inputs_once` proves one payment), product is the guest's | none |
| Detailing | not done | not done |

## Results (local/test-results)

- `20261022-085308-pt2-stations-stations-nostations`: first run, module off, early scenario: 28/40; shredder products never reach the host, upgrade built by the guest
  never reaches the host. (Scenario bugs fixed afterwards: research node search needed the active tier, the products arrive one by one, compare garage storage not backpacks.)
- `20261022-091326-pt2-stations-stations`: 33/40 (hooks registered with a pre callback never fired for Blueprint functions: only one callback runs, after the function).
- `20261022-094546-pt2-stations-stations`: 39/48, every remaining failure a scenario fault (cascading timeouts, `L.holds` used as a wait).
- `20261022-095944-pt2-stations-stations`: 48/48.
- nostations: see the end of this file.

## Observations

- Part Shredder: `OnTransactionEnd(container)` on `BP_Garage_PartShredder_C` runs the whole shred (ShredItem per stored item, `ItemDispenser:DispenseItems`);
  a spare wheel gave plastic x2 and rubber x3..4 (random). Products are world items released over about 10 s. The container takes `AddItem(instance, out Added)`.
- Research: `PurchaseNode` is native; its cost is a recipe run through `ExecuteRecipe`. Most research nodes in the fixture are free (`ComponentsToBeConsumed` empty);
  mission nodes (`GenericGraphRecipeNode_108`: plasma x5) cost items. `CanUnlockNode` is false without `SetActiveTier(3,true,true)`.
- Upgrades: every level-placed spawner installs its default upgrade in BeginPlay on every side, so the guest's InstallSpecificUpgrade hook fires about 70 times at
  join; those must not become intents (garage.hostHas).
- Quirks: `CarQuirks` lives in `BP_StatusEffectManager_C`; quirks are `SE_Quirk_MixAndMatch_C` on the car's soul item (`IA_Internal_Soul`); `BuildAndApplyQuirk` takes
  (Condition class, Behavior class, WorldContext) in that order. Pain/obscurity are equal on both sides for the same classes; only the cure ingredient is random.
  `FindFirst*` on managers works, the scenario helper `first()` skips `/Engine/Transient` objects (managers live there).
- UE4SS: a Blueprint function hook takes ONE callback (runs after the function, out params filled); registering `pre, post` made neither run for BP functions.
  Native functions (`PurchaseNode`, `ExecuteRecipe`) take pre and post. A Lua-called BP function fires the hook too.
- `CureCarQuirk`'s argument is already destroyed when the post-hook runs: its key is looked up from an address table filled every second.
- `tools/repl.ps1 -Reload` does not re-run `stations.lua` (hooks stay as they were); restart the session to test module edits.

## Derived

- Costs are paid once because the host is the only payer for research (guest's cost recipe emptied), shredding (items are the guest's pack, the host's shredder only
  makes products) and quirk cures (paid on the guest, host skips the payment); fabrication already was once.

## Guesses

- The real station UIs (hold-to-invent button, shredder container screen, Tinker screen) call the same functions the scenario calls; not driven with real input.
- The blueprint / upgrade-kit item the bench prints on the host (OnNodePurchased) reaches the guest as a world item through loot.lua; not checked.

## Unknowns / not done

- Detailing (cosmetics: item-slot swaps, `UItemSlot::SwapSlotContents`) is not done.
- Tinker hints (diagnose, `CurrencyAdjust(CA_AnchorJuice_Stable, -cost)`): not synced; whether currencies are shared at all was not checked. The hint reveal state and the
  logbook/journal entry are not mirrored (only the Diagnosed flag).
- Quirk identity is condition + behavior: two identical quirks on one car count as one. A quirk that surfaces on the host through play (not the debug roll) is mirrored the same way;
  not driven.
- A research node bought by the host while the guest has the station open is fine; two players buying the same node at the same time: second PurchaseNode is refused (HasNodeBeenPurchased).
- The shredder: items put in by the host's own UI at the same moment as a guest batch share the host container (batched into one run).
- Guest research with a cost needs the host to have the items; if not, the host's PurchaseNode returns false and nothing happens (no message on the guest).

## Mutation

- `20261022-103638-pt2-stations-stations-nostations`: 37/48, 11 FAIL (shredder x3, research purchase, upgrade install, quirk mirror/cure x5, plus a scenario error when the guest has no quirk). The checks that still pass with the module off are the ones that were already true: guest-local research/upgrade/craft state and one-time garage payment for fabrication.
