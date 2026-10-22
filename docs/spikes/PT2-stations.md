# PT2 stations: the guest uses the garage stations (PLAN G2, D21)

Lane pt2-stations. Code: `mod/PacificTogether/Scripts/stations.lua` (FEATURES "stations"), small edit in `garage.lua` (`M.applying`), scenario `stations`
(`tools/run-test.ps1 -Scenario stations -Fixture garage -Headless`, mutation `nostations`); the old one-game research probe is `stationsprobe`.
Research behind it: `docs/research/garage-stations.md`.

## Design

The guest keeps the game's own station UIs and functions (they are local). What each station does to SHARED state is turned into an intent, the host
performs it, and the existing syncs show the result: loot.lua (world items, garage storage), progression.lua (research graph host->guest), garage.lua
(installed upgrades host->guest).

| Station | Guest side | Host side |
|---|---|---|
| Part Shredder ("Unmaker") | post-hook `BP_Garage_PartShredder_C:ShredItem` collects the item specs and empties the local `SmashedProducts` (no second copy); `g.st.shred` 0.4 s after the last item | puts the items into ITS shredder container and calls `OnTransactionEnd` (what closing the container does); products come out of the host's dispenser as world items |
| Research / blueprints | pre-hook `BaseGenericGraphState:PurchaseNode` sends `g.st.buy node`; while it runs `InventoryRecipe:ExecuteRecipe` is emptied (the cost recipe: the host pays) | `SetActiveTier(3,true,true)`, `PurchaseNode(node)`, then the bench's own `OnNodePurchased(node)` (prints the blueprint / upgrade kit); progression.lua mirrors "purchased" to the guest |
| Garage upgrade | post-hook `BP_GarageInstallation_Spawner_C:InstallSpecificUpgrade` (not when garage.lua is the caller: `garage.applying`) sends `g.st.up spawner<TAB>class` | `InstallSpecificUpgrade(class,false)` on the same spawner; garage.lua shows it back |
| Fabrication | unchanged: local `Craft Recipe Asset`, garage materials ride loot.lua's storage sync, product is the guest's | none |
| Tinker, Detailing | not done | not done |

## Observations
(see Results; filled in as runs complete)

## Derived

## Guesses

## Unknowns
