# M4 backpack: the guest's backpack persists, and drops when the guest dies (P5, D7, D6)

Lane pack, 2026-10-21. Code: `mod/PacificTogether/Scripts/backpack.lua` (record format and API facts from X12, `docs/spikes/X12.md`).
Scenario `backpacksync` (zone fixture, mutation `nobackpack`). Small edit in `health.lua` `die()`: calls `backpack.died()`.

## Design

- The guest's backpack stays in the guest's process. The guest sends its record (one text line: items, counts, grid spot, rotation,
  durability, hand, quick slots) to the host on every change (`g.bp.save`); the host keeps it and writes
  `Saved/SaveGames/odsave<slot>.pt-<guest>.txt` next to the host's slot (on every change, and again after each host `SaveGame`). The game's own
  `.sav` and the guest's saves are untouched.
- Join: the guest asks (`g.bp.hi`, every 3 s until answered); the host answers `g.bp.rec` with the file's line (memory as fallback) or `none`.
  A known guest gets its backpack rebuilt; a new guest keeps what the game gave it. Nothing is sent up before that answer, so a fresh
  backpack never overwrites a stored one. Every map load resets the handshake (the host's map changes drop and rejoin the guest).
- Guest id = the guest's player name on the host's PlayerState (sanitised). Slot = last slot seen in `SaveGame/LoadGame/UserLoadGame/UserNewGame`
  hooks, else `GetCurrentSlot()`.
- Death: `die()` calls `backpack.died()`: the guest sends its line (`g.bp.death`) and empties backpack, hand and quick slots. The host spawns a
  `BP_Lootable_Crate_Large_C` at the guest pawn, fills it with the items (durability kept on the host's copy) and sets `RolledOnOpenItems`.
  `loot.lua` picks it up like any lootable, so the guest sees it and either player can take from it.

## Observations

Runs (`local/test-results/`): `20261021-133415-pack-backpacksync` 32/32; mutation `20261021-131826-pack-backpacksync-nobackpack` 22/32 (fails);
`20261021-133216-pack-session` 40/40; `20261021-132500-pack-playerhealth` 26/26; `20261021-132641-pack-lootsync` 34/34.

- In a session the guest's `disconnect` returns straight to the host (native rejoin), not through the menu; the restore ran without it.
- `BP_Lootable_Backpack_Civilian_C` holds only 8 items (2 of 10 refused by `AddItem`); `BP_Lootable_Crate_Large_C` took all 10. The bag is therefore a crate.
- A stack moved into the hand slot has a `Location` that is not a number; reading it made the encoder throw (fixed: such slots record 0,0).
- The file is written next to `odsave8.sav` with the guest's player name (`DESKTOP-...`: Windows machine name in tests, so two guests on one PC would share an id).

## Derived

- Persistence goes through the host file on every join (the scenario host answers from the file), so a host reload needs nothing extra; the X12 reload
  path was not re-run here.

## Guesses

- The player name is stable per player on Steam; a Steam id is the better key when Steam lands (D7 note in the plan).

## Unknowns / known gaps

- Items in the death crate lose their grid spot; on the guest's copy (via `loot.lua`) they also lose durability (`ids.lua` is archetype + count).
- The crate is a plain crate, not a backpack model; no map marker.
- Two guests with the same player name would share a record; a new host save slot starts guests as new (file is per slot).
- A guest that dies and then rejoins before the crate is looted keeps an empty backpack (the items are in the crate).
- Host's own death is the game's; unchanged.
