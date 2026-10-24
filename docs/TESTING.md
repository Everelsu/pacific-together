# Testing

Tests run real game instances from the test copies, never the real install.

## Prerequisites

- Steam running and logged in (the game initialises Steam under appid 1458140; runs without Steam are untested).
- `tools\setup-test.ps1` has made `C:\PacificTogetherTest\client1` and `client2` (UE4SS plus junctions to
  `mod\PacificTogether` and `test\PacificTogetherTest`). Repo edits apply on the next launch.

## Running

```powershell
tools\run-test.ps1 -Scenario boot                     # both reach the main menu
tools\run-test.ps1 -Scenario listen                   # engine listen server: host in RB_Garage, client joins
tools\run-test.ps1 -Scenario listen -Mutate skipconnect   # must FAIL: proves the listen checks can fail
tools\run-test.ps1 -Scenario dump                     # one instance, UE4SS dumps into local\dumps
tools\run-test.ps1 -Scenario travel                   # X1/X1b: game's own travel with a client; native LoadMap patch keeps the host listening, client rejoins
tools\run-test.ps1 -Scenario body                     # X13: guest gets a character in front of the host; mesh flags, screenshots, walk/crouch/sprint
tools\run-test.ps1 -Scenario zonejoin                 # X11: client connects ~40 s before the host listens (zone map)
tools\run-test.ps1 -Scenario guestsave                # X10: guest's SaveGames/Config unchanged through join, travel, autosave
```

Spike notes and results: `NOTES.md` sections "spike X1/X1b/X3/X10/X11/X13".

X5/X6 (`docs/spikes/X5.md`, `X6.md`): `-Tunnel "udp [lag=ms] [loss=pct] [hold=s]"` runs any two-player scenario through
the native tunnel (client opens `10.77.0.1:<port>`; mutations `notunnelpeer`, `tunnelbypass`, `nolag`). Shipping UE has no
`NetEmulation.*`, so lag/loss runs use the tunnel's own emulation. `-Scenario steamsolo -Clients 1 -Seconds 300` checks
the game's Steam session alone (mutations `nosteam`, `steamearly`); `steamhost` / `steamguest` are the two-PC human test.

Options: `-Root` (default `C:\PacificTogetherTest`), `-Clients 1|2` (default 2, dump 1), `-Seconds` (timeout,
default per scenario), `-KeepOpen` (leave the games running), `-Mutate <name>`.

The runner refuses to start if a game from `-Root` is running, and only stops processes it started (plus
`CrashReportClient` under `-Root`, closed without sending). Logs, crash folders and `summary.txt` go to
`local\test-results\<yyyyMMdd-HHmmss>-<scenario>[-<mutation>]\`. Exit code 0 = all checks passed. Screenshots
taken during the run (`HighResShot`, written to `<copy>\PenDriverPro\Saved\Screenshots\WindowsNoEditor`) are copied
there as `<role>-HighresScreenshotNNNNN.png`, in the order of the `PT|shot side=.. n=.. tag=..` lines.

## Log contract

Roles come from environment variables set per process: `PT_ROLE=host|client`, `PT_SCENARIO`, `PT_HOST`
(client), `PT_STATUS=<ms>`, `PT_MUTATE`. All output is `print()` into `<copy>\PenDriverPro\Binaries\Win64\ue4ss\UE4SS.log`:

| Line | From |
|---|---|
| `[PacificTogether] PT\|boot version=.. protocol=..` | main mod, at load |
| `[PacificTogether] PT\|status net=<none\|standalone\|listen\|client> map=<name> pcs=<n>` | main mod, every `PT_STATUS` ms |
| `[PacificTogetherTest] PT\|plan side=<role> checks=<n>` | test mod, scenario start |
| `[PacificTogetherTest] PT\|check side=<role> name=<id> result=PASS\|FAIL detail=<...>` | test mod, per check |
| `[PacificTogetherTest] PT\|done side=<role>` | test mod, scenario end |
| `PT\|error ...` | either; any one fails the run |
| `[PacificTogetherTest] PT\|snap side=<role> tag=<tag>` | test mod; the runner snapshots that copy's `Saved\SaveGames` and `Saved\Config` (name, size, time, SHA-256) and checks `saves unchanged <first>-><tag>` by name+size+hash |
| `[PacificTogetherTest] PT\|actors side=.. tag=.. class=.. role=.. rep=.. loaded=.. owner=.. n=..` | test mod `survey()`; the runner writes `actors-<tag>.csv` with host and client counts |
| `PT\|loadmap pre\|post ...`, `PT\|info ...`, `PT\|save ...` | test mod, information only |

Per-run config: `$IniEdits` in the runner appends lines to a copy's `Saved\Config\WindowsNoEditor\Engine.ini` before
launch and restores the file after the run (zonejoin: `ResolutionConnectionTimeout=120` on the client).

A run passes when every side printed `boot`, `plan`, all planned checks as PASS, `done`, no `PT|error`, and no
new crash folder appeared.

## Adding a scenario

Add an entry to `scenarios` in `test\PacificTogetherTest\Scripts\main.lua`: a function returning the steps for
the current `ROLE`. Steps are `{check=id, timeout=s, cond=fn, tick=fn(t)}` (polled every second until `cond`
is true or the timeout; `tick` runs while waiting), `{wait=s}` or `{run=fn}`. Checks are counted for the plan
line automatically. All steps run on the game thread. Optionally add the scenario's client count and timeout to
`$Defaults` in `tools\run-test.ps1`.

## Mutations

`-Mutate <name>` sets `PT_MUTATE` for every process; the test mod breaks one behaviour on purpose so a run shows
that its checks can fail. Each new check should get a mutation. Existing: `skipconnect` (listen: the client never
runs `open`, so `client_connected_garage` and `host_two_pcs` fail); `nokeep` (travel: `PTNative_SetKeepListen(false)`,
so `host_listen_after_native_travel` fails and the `servertravel ?listen` fallback re-hosts); `norehost` (travel: keep-listen
off and no `servertravel ?listen` after the native travel, so the re-host and rejoin checks fail); `follow` (travel,
experiment: the host sends `ClientTravel` to the guest before native travel and the guest never runs `open`; fails
today, the connection close wins); `nospawn` (body: the guest stays a spectator, every body check fails); `noconfig` (zonejoin: no timeout fix, the client
times out at 20 s); `cdo` (zonejoin: no ini, the fix is set on the IpNetDriver CDO from Lua; must PASS); `noblock`
(guestsave: save hooks only log, the forced autosave writes `odsave_scratch.sav`).

## Parallel lanes

Several agents or developers can test at once, each in their own lane:

- **Own test pair:** `tools\setup-test.ps1 -Root C:\PTLanes\<lane> -LinkFrom C:\PacificTogetherTest\client1
  -UE4SSZip <main repo>\local\cache\ue4ss\zDEV-UE4SS_v3.0.1-1181-g83330635.zip`, run from the lane's worktree (the
  mod junctions point at the repo the script lives in). Hardlinks only: ~12 s and ~700 MB per pair.
- **Own port:** `run-test.ps1 -Port <n>`. Without it two lanes' guests join each other's hosts (seen in practice).
- **Headless:** `run-test.ps1 -Headless` runs `-nullrhi -nosound`: ~1.1 GB RAM per game, no GPU, main menu in ~8 s.
  Two-player `listen` passes headless. Screenshots (`body`) need a normal run.
- **Results:** `-ResultsDir <main repo>\local\test-results` keeps results after the worktree is removed; folder names
  carry the lane (`<stamp>-<lane>-<scenario>`).
- **Slots:** at most `PT_SLOTS` (default 5) runs at once on the machine; a runner waits for a free slot.
- **Scenario files:** put a new scenario in `test/PacificTogetherTest/Scripts/scenarios/<name>.lua`, returning
  `function(T) return steps end`, where `T` holds the helpers from `main.lua` (`T.onMap`, `T.join`, `T.console`, ...).
  The runner's defaults for an unknown scenario are 2 clients and 300 s; pass `-Clients` / `-Seconds` otherwise.

## Live console (explore without relaunching)

`tools/repl.ps1` runs Lua inside a running test game and prints the result in about a second, so questions like
"what does this function return" or "which actors exist now" need no new scenario and no relaunch.

1. Start a session in the background: `tools/run-test.ps1 -Scenario repl -Seconds 3600 -Headless [-Clients 1]
   [-Root ... -Port ...]`. The host opens `$env:PT_MAP` (default the garage) as a listen server, the client joins,
   both hold.
2. Ask: `tools/repl.ps1 [-Root ...] [-Side host|client] -Code "state()"` or `-File probe.lua`. An expression returns
   its value; a block can call `out(...)` for extra lines and `return` values. Every helper of the test mod's `T`
   table is in scope (`state`, `first`, `inWorld`, `console`, `map`, `netMode`, `dist`, ...), plus all UE4SS globals.
   Exit code 0 = ok, 1 = Lua error (message printed), 2 = no answer (game not running or not past the main menu).
3. Change Lua without a relaunch: edit `mod/PacificTogether/Scripts/*.lua`, then `tools/repl.ps1 [-Root ...] [-Side ...] -Reload`
   restarts the main mod's Lua in that game (UE4SS `RestartMod`; hooks are unregistered and registered again, Lua state
   starts fresh). `main.dll` stays loaded (it is its own mod, `PacificTogetherNative`); a native change still needs a
   relaunch. The game thread waits during the reinstall (`PTNative_ReloadLua`, test runs only): a plain `RestartMod` races
   the hooks (crashed a host with a guest once in 4 runs). Scenario `reload` proves it in a live two-player session (mutation
   `noreload`; `nowait` drops the wait but rarely fails).
4. End it: `tools/repl.ps1 [-Root ...] -Stop`; the scenario passes `repl_session_stopped`, the runner closes both
   games and frees the slot.

The console also runs during every other scenario, so a failing test can be inspected while it runs. It exists only
in the test mod. Once a question is answered, turn the answer into a scenario check: the console explores, scenarios prove.

## Fixture saves

Real saves that put a test straight into a game state instead of the main menu. They live in `local\fixtures\<name>\`
(git-ignored, game data): the `.sav` file and a `fixture.txt` with state, slot and how it was made. Each uses its own slot,
so several can sit in one SaveGames folder.

| Name | Slot | Map | State |
|---|---|---|---|
| `garage` | 7 | `RB_Garage` | story mode, car and character, stocked by the game's debug events (biggest container 457 items, anchor juice +5 each); no missions done |
| `zone` | 8 | `Rural_Forest_Radio_Scylla_02` | a real run map (started by the game's own `TravelToNextLeg`), car and character, ARC charge about 4 |
| `gateway` | 9 | `Rural_Forest_Radio_Scylla_02` | `zone` with the ARC `CurrentCharge` = 7.0 (`MaxCharge` 1.0, so the screen counts it charged); the game's own exit selection (`GobblerScreen:OnExitUseComplete(portal)`) sets the gateway (2026-10-24); the nearest portals are ~1.1 km from the car |
| `garage-return` | 1 | `RB_Garage` | back from a run through the exit portal's own return (`TravelToGarage(2, ...)`), loot in the car (trunk 129 items on the guest); fixture.txt has the steps |

- `run-test.ps1 -Fixture garage[,zone,gateway]` moves the host copy's `Saved\SaveGames` aside, copies the fixtures' `.sav`
  files in, sets `PT_FIXTURE`, and puts the original folder back after the run (a leftover `.ptbak` from a killed run is
  restored at the next start). What the game saved during the run is kept in the results folder as `fixture-saves-after`.
  `-FixturesDir` overrides `<repo>\local\fixtures` (worktrees do not have it).
- In a scenario: `T.loadFixture(name[, fromMenu])` returns steps that call the game's `UserLoadGame(slot, STORY, 0)` and pass
  `fixture_<name>_map` once the map, the character and the car are there. Chain several with `fromMenu=false` (the game loads
  from any map). `T.arcCharge()` and `T.maxContainerItems()` read the state the fixtures were made with.
- `-Scenario repl -Fixture <name>` opens the console already in that state (standalone, no listen server: a reload would drop it).
- `-Scenario fixtureload -Fixture garage,zone,gateway -Clients 1`: loads all three and checks map, stock, run map and ARC
  charge. Mutations: `nofixture` (nothing loaded), `wrongfixture` (the gateway step loads the zone save).
- Load times (headless, warm cache): menu to garage 8 s, garage to zone 18 s (first load of that map), zone to zone about 6-18 s.
  No other automatic way to a zone with a car exists (the intro would need a bot to play it).
- Remake (build or game update): start `-Scenario repl` (no `-Fixture`), follow each `fixture.txt` through `tools\repl.ps1`,
  copy `odsaveN.sav` from `<root>\client1\PenDriverPro\Saved\SaveGames` into `local\fixtures\<name>\`. Never copy saves from
  the real install. `UserNewGame(slot, CHALLENGE)` (expedition) hangs and then crashes the game, do not use it.

## Crash dumps

`python -I tools/dmpstack.py <ue4ss/crash_*.dmp> <folder with UE4SS.dll and UE4SS.pdb>` prints the exception address and the
UE4SS and game frames found on the crashing stack, symbolized (a stack scan, not a real unwind). Example, 2026-10-24: `luaH_next`
under `luaL_traceback` (a corrupted Lua table while an error was reported) pointed at a `NotifyOnNewObject` callback running Lua
off the game thread.

## Playing by hand

`tools/play-local.ps1` starts the two test copies windowed side by side (half the main screen each, 752x423 on a 1536-wide desktop; `-ResX/-ResY` to change) with no
test bots, so you can try things yourself. The guest joins the host by itself (`PT_JOIN=127.0.0.1:<port>`, retried at the
menu until the host listens); the host's shipping mod listens like a real player's. The test mod stays inert (no `PT_SCENARIO`).

- `tools/play-local.ps1`: both stop at the main menu; start or load a game on the host, the guest joins once it listens.
- `tools/play-local.ps1 -Fixture garage|zone|gateway|garage-return`: the host loads that fixture save (the test mod's `repl` scenario does only
  that), the guest follows. The host copy's own saves are put back when the script ends.
- `-Root` (default `C:\PacificTogetherTest`), `-Port`. It refuses to start while a game from `-Root` runs, waits until
  both games are closed (Ctrl+C closes them) and prints each side's `UE4SS.log` path.

## Live bug-fix loop (preferred for bugs found in play)

The owner's preferred way to fix a bug seen in play (2026-10-23: five bugs in about 40 minutes that no scenario had
caught). It needs the owner at the PC; suites and bots come after, as regression.

1. Start two rendered games that both answer the live console: game MCP `session_start players=2 headless=false
   seconds=3600` (plus `fixture=zone|garage`). `tools/play-local.ps1` does not do this: its guest has no console.
2. The owner plays and reproduces the bug (or describes it), then leaves the broken state alone (no F8, no keys).
3. Read the live state on the side that is wrong and compare it with the other side (`eval`, `describe`, `watch`,
   `screenshot`). Before writing code, prove the cause with a live poke where possible (for example setting a field back
   and asking the owner whether it moves now).
4. Patch the files, copy both `UE4SS.log` first if they hold anything worth keeping, then `session_stop` and
   `session_start` again. Restart; do not hot-reload (RestartMod crashed a guest after a few reloads in one session).
5. The owner retests by hand. Report what the owner saw fixed and what was not seen yet; record the cause in NOTES.md.
