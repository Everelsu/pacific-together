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
3. End it: `tools/repl.ps1 [-Root ...] -Stop`; the scenario passes `repl_session_stopped`, the runner closes both
   games and frees the slot.

The console also runs during every other scenario, so a failing test can be inspected while it runs. It exists only
in the test mod. Once a question is answered, turn the answer into a scenario check: the console explores, scenarios prove.
