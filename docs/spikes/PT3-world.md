# PT3 world: the guest's world differs from the host's (first Steam play #1, #15, #7b, #5)

> Historical research; see the [index](README.md) for current implementation and later evidence.

Later October 24 work also mirrors host garage-door unlock/open/shut state. Guest anchor pickup still duplicates on the host; see [../../NOTES.md](../../NOTES.md).

Lane pt3-world, branch worktree-agent-a28acfaa7505fc85b. Scenarios: `worlddoors` (fixture garage), `worldzone` (fixture zone).

## Observations
- #1 garage chained side doors: the doors are map-placed (BP_Door_Single_C, e.g. `BP_Door_Single_Garage_Exterior_Rear`, CurrentState 3 =
  locked and shut, LockStrength 1-3), so they exist on both sides and nothing mirrors them. The guest working the lock
  (BP_LockedComponent:WorkLock, what the prybar's damage message ends in) opened only its own door (state 2); the host's stayed 3
  (`worlddoors` with PT_MUTATE=novisual: 19/21, run 20261023-232132). Host `door:ForceUnlockDoor()` (the same WorkLock) opens the
  host's door to state 2 as well.
- #7b plasma generator (BP_Spawn_Resource_Plasma_PlasmaGenerator_C, a BP_Spawn_ResourceBase child, loot kind R): breaking it
  (OnHarvested) sets `Broken`, swaps SM_Plasma_Generator_Glass to BrokenMesh, light intensity 0, highlight off. Also at BeginPlay
  each side rolls its own `Broken` (ChanceToBreakOnSpawn), so host and guest copies disagreed from the start (live: 4 of 16 vs 3 of 16).
- #15 ARC anchor structures (BP_Spawn_Anchor_Stable/Unstable/Corrupted_S/M/L, BP_Spawn_Anchor_Locked_*; chain BP_Spawn_Anchor_Base_01 <
  BP_Spawn_Resource_GrabBase < Actor) are not BP_Spawn_ResourceBase, so loot kind R never covered them; the visual props mirror did not
  list them either. A host-spawned one never existed on the guest (live check). The zone fixture has none by itself.
- #5: a converter ("transmuter", BP_Spawn_Resource_Converter_Small, ResourceBase child) spawned on the host arrives on the guest through
  loot kind R, but only after a long while (guest had 0 after ~20 s, 2 about a minute later).

## Derived (fixes)
- visual.lua: the guest's door hooks now cover map-placed doors too (a scan of door classes every 10 s) and a second event,
  `OnLockOpened_Event_0` (the door's handler of its lock opening): g.vis.unlock -> host `ForceUnlockDoor` (only if still locked).
  g.vis.door (E on a door) now also applies to map-placed doors (name = actor name); the host skips the Transient duplicates.
- visual.lua: `BP_Spawn_Anchor_` added to ALLOW (copies mirrored, removed when the host's is taken: dispose).
- loot.lua: kind R lines carry "br" for a broken generator; the host sends `S|id|br` when `Broken` flips; the guest applies the game's
  own broken look (Broken, glass mesh, light 0, highlight off). Mutation noplasma.

## Guesses and open questions at the time
- #5 not reproduced: in the open the host's transmuter reaches the guest. Guess: in a small building the guest's own spawn pass rolled an
  ARDA container (a prop, not a BP_Lootable_Base_C or ResourceBase, so loot's purge does not remove it) at the same spot, and it hides
  or replaces the copy. Needs a hand check in such a building (list the guest's actors within 200 uu of the host's transmuter).
- The guest cannot pick up an anchor structure (the copy has no gameplay); the host's pickup removes it. A guest that rolled a
  broken-at-spawn generator where the host's is whole keeps it broken (not undone).
- Doors a guest shuts again after the host opened are forwarded by E (g.vis.door); a door the host unlocks/opens is not pushed to a
  map-placed guest door (host-first opening in the garage was reported as working for both).
