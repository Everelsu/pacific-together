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
```

Options: `-Root` (default `C:\PacificTogetherTest`), `-Clients 1|2` (default 2, dump 1), `-Seconds` (timeout,
default per scenario), `-KeepOpen` (leave the games running), `-Mutate <name>`.

The runner refuses to start if a game from `-Root` is running, and only stops processes it started (plus
`CrashReportClient` under `-Root`, closed without sending). Logs, crash folders and `summary.txt` go to
`local\test-results\<yyyyMMdd-HHmmss>-<scenario>[-<mutation>]\`. Exit code 0 = all checks passed.

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
runs `open`, so `client_connected_garage` and `host_two_pcs` fail).
