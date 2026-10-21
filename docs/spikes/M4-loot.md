# M4 loot: shared items, containers and trunk (W1, W2, C6, G1, P2, P3)

Lane items, 2026-10-21. Code: `mod/PacificTogether/Scripts/ids.lua` (containers as `archetype=count` strings, apply to a
container) and `loot.lua` (entities, scan, messages on `net.lua` kind `g.loot.b`). Scenario: `lootsync` (zone fixture, host and
guest, mutation `nointent`; `hold` keeps both sides up for the live console).

## Design chosen

Neither candidate as written. (a) replicate the host's actors and (b) sync the seeds were both dropped after one look at the zone fixture:

- The guest's zone has almost no loot at all: host 40 lootables + 16 world items, guest 1 lootable. The host's lootables carry save-file GUID names (restored
  from the save), the guest generates nothing comparable. Seeds cannot help (nothing to regenerate), and the host's loot is not
  replicated by the engine (lootables are placed by the host's run code, not net-relevant actors we control).
- So the guest **spawns copies**: the host tells it every lootable (class path, spot, contents) and world pickup (archetype, spot) in
  messages; the guest claims a local actor of the same class within 60 uu or spawns one (`BeginDeferredActorSpawnFromClass`
  with `ForceSpawnEvenifFailedChanceToLive`, world items by `InventorySystem:SpawnItemActor`), sets its contents to the host's, and destroys its own unclaimed random loot.
- Contents are diffed, not hooked: both sides look at `GetNumItems()` of every shared container every 500 ms, and on a change send the
  whole contents string. Guest to host is an intent (host applies and tells the other players), host to guest is state.
- World pickup: the guest's local pickup destroys its copy and puts the item in its own backpack (P3); the guest sees the destroyed copy
  has an outer slot (`Instance:GetOuterSlot()`) and sends `T id`; the host destroys its actor and tells everyone `D id`. A host
  pickup destroys the host actor, the next scan sends `D id`.
- Containers of the game's own (the car trunk is `BP_InventoryManager_C.Inventory_Trunk`, same object as the trunk actor's
  container component; garage storage `Inventory_Garage*`) sync the same way under ids `I:<property>`.
- Items the guest drops (an unknown world pickup within 500 uu of the guest) are sent to the host as `N` and become the host's.

## Observations

- Result folders under `local/test-results/`: `20261021-110810-items-lootsync` (33/34, trunk put fail); final 20261021-121017-items-lootsync 34/34, mutation nointent 20261021-120157-items-lootsync-nointent 23/34 (fails), session 20261021-120839-items-session 40/40, `20261021-111358-items-lootsync`
  (31/34), `20261021-115407-items-lootsync` (32/34: the guest had 2 own lootables left).
- Zone fixture, host: 40 `BP_Lootable_Base_C` of 17 classes, 16 `BP_WorldItem_C` (15 plain + a `GasPumpHandle`). Guest: 1 lootable, 0 world items; its
  own spawners add world items and lootables again a few seconds after the join.
- A deferred-spawned `BP_Lootable_Backpack_Civilian_C` on the guest populates itself (2 items) and is a normal actor; contents are replaced by ours.
- The host's pickup into `Inventory_Player` fails when it has 0 slots (the zone fixture's host has none): `TransferStackIntoContainer`
  returns nothing; into `Inventory_PlayerHand` (1 slot) it works (as in X2). Scenario takes into the hand.
- Guest pickup of a world item through `PDP_MainCharacter:"Pickup Actor"` leaves the actor pending kill within one tick, with the item in a slot of the
  guest's backpack container. (X4 saw "still visible" because it polled `IsValid`, not PendingKill.)
- `InventoryBlueprintLibrary:CreateItemInstance(world, archetype, 0)` makes an item, `ItemContainer:AddItem(inst, true)` adds it (creates a slot when full),
  `RemoveItemsOfType(archetype, n)` removes. `CreateItemInstance` is not on `InventorySystem`.
- The trunk of the fixture can hold car parts (`Door_Junk_Basic_01` showed up in its state string).

## Derived

- Host-authoritative contents by diffing per container works with no hook into the game's transfer code and covers the UI, our test's calls and
  anything else that moves items, in both directions.

## Guesses

- Taking through the real loot UI (drag/transfer by a human) changes `GetNumItems()` the same way as `TransferStackIntoContainer`; not tried by hand.

## Known gaps (not worked on, gameplay first)

- Items are rebuilt from archetype only: durability, upgrades, tints and other per-item properties do not travel (taking one gives the real item, putting one gives a fresh one).
- Two players changing the same container inside one 500 ms window: last writer wins, no merge.
- Visual state of a lootable (opened, empty) is not synced; the guest's copy looks closed until opened there. `RolledOnOpenItems` is synced.
- Wreck scrap, abandoned-car parts, gas pump handle (destroys itself on the guest), lockbox world items: not done (the car parts belong to the car lane).
- Garage containers (`Inventory_Garage*`) are in the sync list but the scenario runs in the zone only; not tested in the garage.
- Lootables or pickups that the guest spawns locally later (streaming) are destroyed on the guest if the host did not tell about them (unclaimed purge every tick).
- A guest that joins mid-session gets a full dump on its `H`; a guest that rejoins after a map change starts clean (state cleared on every map load).
- Messages are plain `g.loot.b` batches of up to 8000 bytes; a garage container with many distinct archetypes might need more.
