# M4 loot 2: item state, wrecks, lootable visuals, garage storage

> Historical research; see the [index](README.md) for current implementation and later evidence.

Lane itemsx, 2026-10-21. Code: `ids.lua` (per-item state), `loot.lua` (kinds B, P, flags, garage tags, pieces). Scenario: `lootsync2`
(zone fixture: wrecks, state, visuals, trunk; garage fixture: trunk state and garage storage; mutation `nolootsync2`). Builds on `M4-loot.md`.

## What changed

- **Item state.** A container is `path:d37:f7.5*count,...` (ids.lua). `d` durability (int), `f` fuel, `b` battery, `h` health (floats). Read through
  `BFL_ItemPropertyUtilityFns_C` (`GetDurability`, `GetFuelableInfo`, `GetBattery`, `GetHealth`), written with
  `InventoryBlueprintLibrary:SetItemProperty(IP_*, item, FName("Durability"|"Fuel"|"Battery"|"Health"), value)`. The setter takes an
  int32: a float goes in as its bits (`string.unpack("<i4", string.pack("<f", v))`), which is how fuel and battery are set. An item that
  differs only in state from one already in the container is changed in place instead of removed and recreated.
  Tints, upgrades, chart data and nested containers are not carried. `h` was never seen on an item (a car door had no `IP_Health`).
- **Wrecks.** The guest has none of the abandoned cars in a zone except 6 map-placed stripped cars, whose parts differ from the host's. The host
  tells the guest every `ALootableTemplate` body (kind `B`) and every `ALootableTemplatePart` (kind `P`: class, transform incl. pitch and
  roll, item archetype and state, mesh). The guest claims a local actor of the same class within 60 uu or spawns it
  (`BeginDeferredActorSpawnFromClass`, `ItemInstance` and `RequestedMesh` set before `FinishSpawningActor`; a loose part has the same
  components as the host's, harvestable, health, highlight), and destroys its own unclaimed bodies and parts. Scrapping or taking a part on the guest
  destroys its copy: the guest sends `T id` and the host destroys its part (`D` back to everyone). A host removal reaches the guest as `D`.
  Siphoned fuel: the part's item state is diffed each tick (`S` for kind `P`), either side applies the other's.
- **Lootable visuals.** State flags digit (1 rolled, 2 `DataBlock_WasOpened`, 4 `Empty`); applying a flag calls the game's own
  `SwitchToOpenedVisuals()` / `UpdateVisualsForEmpty()`.
- **Garage storage.** The garage's storage is not `Inventory_Garage*` (nil in `RB_Garage`) but `BP_InventoryManager_C.Inventories_Garage`, a
  map keyed by station tag (`Stations.Install.Inventory.Starter` 457 items, `.BackRoom`, `.Expansion`, `.Corner`, `.Lobby`, `.BackEntrance`,
  `.Toolbox`). They are synced as `I:<tag>` now. The Toolbox tag is a lootable's container and does not exist on the guest: skipped.
- **Big states.** A state line over 7500 bytes goes as numbered pieces `P|id|i|n|keys`, put together on the other side (message limit is 32 KB;
  the Starter's state was 2 KB in the fixture, so the path is not exercised by a test).

## Observations

- Runs in `local/test-results/` (lane prefix `itemsx`): `20261021-140102-itemsx-lootsync2` 33/33 (zone), `20261021-140228-itemsx-lootsync2` 21/21 (garage), mutation
  `20261021-140836-itemsx-lootsync2-nolootsync2` 23/33 (fails), `20261021-141023-itemsx-lootsync` 34/34, `20261021-141357-itemsx-session` 40/40.
  The garage storage check is not affected by the mutation (it targets state, wrecks and visuals).
- `SetItemProperty` before `AddItem` does nothing (the item has no property components yet): add first, then set.
- The zone fixture's trunk is full (9 slots, 46 items); an `AddItem` into it fails quietly. The scenario empties it first.
- `ALootableTemplate` and parts of procedural abandoned cars are named by GUID/runtime names; duplicates of the 6 map-placed stripped cars exist
  in `/Engine/Transient` on the host (location 0,0,0): skipped. Parts' `GetAttachParentSocketName` is `None`, so they are copied by world transform.
- The guest world holds the host's map actors for map-placed templates (6), but none of the procedurally placed ones (29).
- A hot reload (`repl.ps1 -Reload`) in a running host and guest pair crashed the host once ("game thread did not wait, reinstalling anyway").
  Not investigated; every run here restarts the pair.

## Derived

- Item state travels as a per-item property string that both sides compute and apply with the game's own readers and setter.
- Abandoned-car parts can be copied loose (no template socket) and still behave as the host's: same component set.

## Guesses

- Scrapping a part on the guest with the real scrapper destroys the copy (the scenario destroys it directly, as the game's harvest ends with that).
  The harvest's drops spawn near the guest and become the host's through the existing `N` intent. Not run with the real tool.
- Anchors (W1 item): not touched; likely the same `D`/`T` path as a world item, unverified.

## Known gaps

- Real scrapper/cutter/siphon use on a wreck part, and anchors, were not run through the game's UI; scenario checks destroy the copy or set the state directly.
- Gas pump handle and lockbox world items: not done.
- Parts whose item has state other than durability/fuel/battery (tint, evolution) copy the archetype only.
- A wreck part that the guest copy fails to spawn is skipped (logged `PT|loot could not make`).
