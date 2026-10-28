# Game MCP: state and sync tools

Four tools on the `pacific-game` server (`docs/GAME-MCP.md`) that answer "do host and guest see the same thing?" in one call.
Code: `tools/gamemcp/ext_state.py` (tools, diff engine), `test/PacificTogetherTest/Scripts/mcp_state.lua` (reads the game),
selftest `tools/gamemcp/selftest_state.py`. Test pairs only, like every game MCP tool. Everything below was read from the
live game with the atlas (`docs/research/game-atlas.md`) and reflection; fields the game does not expose are listed under Limits.

| Tool | Does |
|---|---|
| `snapshot(domain, side, root, save_as?, detail?)` | one domain as plain JSON on one side; `save_as` writes `<root>/mcp-snapshots/<save_as>-<side>.json` |
| `compare(domain \| lua, root, tolerance, value_tolerance, match_radius, detail, ignore)` | the same snapshot (or Lua expression) on host AND client, then a field-by-field diff |
| `diff_snapshots(a, b, root, ...)` | two saved snapshots (`before-host`, `after-host`, or file paths), same diff engine: before/after an action |
| `fixture_save(name, side, root, overwrite?, save_type?, note?)` | the live state as a new fixture in the main checkout's `local/fixtures/<name>/` |

A reply over about 19k characters is not returned: the snapshot goes to `<root>/mcp-snapshots/_last-<domain>-<side>.json` and the
reply names it with the size of each section.

## Domains

Values are plain: numbers rounded to 2 decimals, objects as class or item names, never object paths. `loc` is `[X, Y, Z]` in
unreal units (cm), `rot` is `[Pitch, Yaw, Roll]` in degrees, `vel` `[X, Y, Z]`. `role` is the engine's `Role` (0 none, 1 simulated,
2 autonomous, 3 authority); `rep` is `bReplicates`; `loaded` is "placed in the map file" (`RF_WasLoaded`).

| Domain | Contents |
|---|---|
| `players` | `players[]` (one per PlayerState, key `player:<PlayerId>`, with `pawn`), `controllers[]` (key `pc:<PlayerId>`: role, remote role, local, pawn class, view target, control rotation), `pawns[]` (every Pawn of the world: class, loc, rot, vel, movement mode, crouched, controlled, attached-to class, percent in car, role), `alive_local`. Player entries carry `storm_exposure` and `protected` from `AC_PlayerHealthReceiverHelper` |
| `car` | `cars[]` (every `BaseNewCar`: class, role, loc/rot/vel, engine on, handbrake/throttle/brake/steer input, upside down, possessed), `manager` (`BP_CarManager`: ignition, gear, lights, fuel and max, battery and max, engine broken, horn, radio, car state, distance, doors `door_0..5` as `EOpenableDoors` values, flat parts), `parts[]` (one per equipment slot tag `Car.Equip...`, key = slot: item archetype, health, max, percent, breaking, dead, status effects, `state` hash), `quirks` (status effects on the soul slot), `part_actors` (count of part manifestation actors by class) |
| `inventory` | `containers[]` (every `ItemContainer` with items, plus the named ones: Trunk, Pack, Hands, Locker, Storage, Garage Stations, Anchor ...; key `<title>#<nth>`, `role`, `slots`, `items`, `by_item` counts per archetype, with `detail=true` also `contents[]` per slot: `i`, item, `n` count, `state` hash, health/durability when set) and `hotbar` (cursor and the item in each quick slot) |
| `run` | `map`, `net`, `game` (master seed, gameplay state, in garage), `progression` (map name, left garage, reveals, quirk guesses, expedition difficulty), `route` (phase, world seed, last reset, current leg: active/visited/discovered/reveal state/flags/applied modifiers = conditions), `storm` (state, tolerance, instability time, player/car inside, red wall, gateway selected and its actor), `exit_portals[]`, `arc_charge` |
| `world` | `counts` by class (n, replicated, authority, loaded, empty) and `actors[]` (max 600) for lootables (`BP_Lootable_Base`: `empty`, `items`), item spawners (`spawned`), world items (`item`), hazards (anomalies) and lootable car templates |

`state` (parts and inventory items) is a hash of the item's data block (`ItemInstance:GetDataBlockDump`, the game's own save form).
That dump holds only values that differ from the archetype defaults, so `health`/`durability`/`charge` appear on an item only
once it changed; matching hashes are a compact sync signal, not a collision-free proof of equality. Inspect the underlying state when needed.

## compare: matching and tolerance rules

1. **Keyed entries** (`key` field: part slots, containers, players, controllers, level-placed actors) match by exact key.
   A level-placed actor's key is `class|<level path of the actor>`, which is the same string on both sides because the map file
   fixes it. Slots inside `contents` match by index `i`.
2. **Everything else** (runtime-spawned actors, cars, pawns) matches by `class` first, then by the nearest `loc`: all candidate
   pairs of one class within `match_radius` (default 500 cm), closest first, one-to-one. Without `loc` they pair in order.
3. An entry that finds no partner is listed under `only_host` / `only_client` with its identifying fields. For example, a duplicate
   client-local car would appear as `cars[BP_PlayerCarNew_C@...]` in `only_client`.
4. Transform fields (`loc`, `rot`, `vel`, `control_rot`) use `tolerance` (default 2.0, angles wrap at 360); all other numbers use
   `value_tolerance` (default 0.05, because fuel and similar values drift while the two snapshots are taken a moment apart).
5. Fields named in `ignore` are not compared, default `name, side, role, role_name, remote_role, rep, is_local, controlled,
   possessed` (they differ by design between host and client). Pass `ignore=[]` to see them.
6. The result: `summary` (equal, differing, only-one-side, ignored counts, equal per section), `differ_by_field` (how many
   entries differ per field name, so 24 identical complaints read as one line), `differ` (path, host value, client value; first
   60), `only_host`, `only_client` (first 60 each), the tolerances used.
7. `compare(lua=...)` takes a Lua expression or block with the console's scope (`first`, `T`, ...) whose value must be plain
   (numbers, strings, booleans, tables, arrays); objects become their full name. Example below.

## Examples

```text
snapshot domain=car save_as=before
snapshot domain=car save_as=after
diff_snapshots a=before-host b=after-host
compare domain=car
compare lua="{map = T.map()}"
fixture_save name=my-state
```

Run `python tools/gamemcp/selftest_state.py` for tool checks (starts real games). Old prototype snapshots with duplicate
cars or unsynced fuel describe that code revision, not expected output from the current mod.

## fixture_save

Saves the running session through the game's own save manager (`SetCurrentSlot(n)`, `SaveGame(n, "", type)`; type 1 = MANUAL,
2 = AUTOSAVE) into the first free slot of 1-6 (the game has 9 slots, `GetMaxSaveSlots`; 7-9 are the built-in fixtures; `slot=` picks another; a slot used by an existing fixture or by the copy's SaveGames is skipped), waits for the
`odsave<n>.sav` to be written, copies it to `<main checkout>/local/fixtures/<name>/` (`fixtures_dir_path` or `PT_FIXTURES_DIR`
override; a worktree has no `local/`, so the tool finds the main checkout through `git rev-parse --git-common-dir`) and writes
`fixture.txt` (state, slot, how it was made, a short state summary from `run`, `car`, `inventory`) in the style of the existing
ones. It also writes `fixture.json` (`{"slot":n,"map":"..."}`): `run-test.ps1 -Fixture <name>` turns it into `PT_FIXTURE_SPEC`
and `T.loadFixture(name)` (`fixtures.lua`) uses that for fixtures that are not in its built-in table, so
`session_start fixture=<name> fixtures_dir=<main>/local/fixtures` loads a saved fixture with no code edit. An existing fixture is
refused unless `overwrite=true` (it then keeps its slot). Never save from the real install: the tool only works on test pairs.

`session_start` got `fixtures_dir` for the same reason (a worktree has no `local/fixtures`); it is passed to `run-test.ps1 -FixturesDir`.

## Limits

- **Player health:** the pawn has no plain health number (`AC_PlayerHealthReceiverHelper` only holds damage intake); not
  snapshotted. `alive_local` is the character manager's flag for the local player.
- **Car manager is one object per game.** On a client the manager follows whichever car it adopted, so `manager` and `parts`
  describe that car; `cars[]` lists every car actor. Door numbers are raw `EOpenableDoors` values (`door_0`..`door_5`), not named;
  handbrake is the controller's `HandbrakeInput`, not the parking brake state.
- **Items with no change look empty:** `health`/`durability` appear only once the data block holds them (see `state` above);
  car parts always have `health` because their health component reports it.
- **Inventory:** only containers with items plus the named ones are listed; empty unnamed ones (the 40 "Wall Anchor"
  containers) are skipped. Container titles repeat (`Oppy's Pneumatube`), so the key is `<title>#<nth>` in `FindAllOf` order,
  which is not guaranteed equal on both sides: an out-of-order pairing shows as differing contents, check `by_item` first.
  `detail=true` in a fixture with 450+ items reads 450 data blocks (about a second).
- **World:** only the base classes listed in the table, 600 actors per snapshot (`truncated: true` after that); anything else
  (destructible props, spawners of other kinds) needs `compare(lua=...)` or `describe`.
- **Matching by position** can pair the wrong two actors when many of one class sit within `match_radius` (raise or lower it).
  Level-placed actors are matched exactly by path, so prefer them for sync checks.
- `compare` runs the two snapshots one after the other (host first, a fraction of a second apart): fast-moving values differ by
  what moved in between. Compare while the game is idle, or use `tolerance`.
- Snapshots read live state through the console on the game thread; reading is not free in a 2000-actor zone (`world` about
  a second). They change nothing.
