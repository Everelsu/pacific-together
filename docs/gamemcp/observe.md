# Game MCP: observe and measure

Tools for milestones that need to see what changed (M3 car feel, M4 item sync, M7 hardening). They extend `pacific-game`
(`docs/GAME-MCP.md`); code in `tools/gamemcp/ext_observe.py`, `test/PacificTogetherTest/Scripts/mcp_observe.lua` and
`native/PacificTogetherNative/{trace,net}.cpp`. Test pairs only. The native parts need a rebuild
(`tools/build-mod-fast.ps1` in a worktree, `tools/build-native.cmd` otherwise); the other tools work without it.
Check: `python tools/gamemcp/selftest_observe.py --root C:/PTLanes/<your pair> --port <port>` (starts real games; 19 checks).

## watch with arguments (`watch args=true results=true`)

`PTNative_TraceStart(filter, max, flags)`: flag 1 adds a 4th column "Name=value, ..." with the call's input parameters, read in
the ProcessEvent pre-callback; flag 2 also registers the post-callback and adds a `<-Function ...` line after each call with the
return and out values. Values are the engine's own text export (ints, floats, bools, enums, names, strings, text, object refs
as `Class'/Path.Name'`, structs such as `(X=..,Y=..,Z=..)` or `FHitResult`). Collections are summarised: arrays show
as `<array n=3>`, maps and sets as `<map>` `<set>`, structs over 256 bytes as `<struct Name>`.

Cost: with tracing off nothing is hooked. On: a mutex and a hash lookup per ProcessEvent call; matching functions (and their
parameter property lists, built once per function) cost a text export per parameter, capped at 12 parameters, 160 characters
each and about 700 characters per call, in a ring of `max_calls` (default 500). Keep the filter narrow: a broad filter such as
`Tick` records thousands of calls per second. No broader performance benchmark was recorded.

## watch_property

`watch_property target=<object path | class name> properties=[...] seconds=5 interval_ms=100 cap=8`. A game-thread job polls
every `interval_ms` (minimum 20; it can not go faster than the game's frame rate) and logs only changes, with the time since
start. `target` with a `/` is one object (full name from `find`); a bare class name watches every live instance of the
current world, up to `cap`. A property is a name, a dotted chain (`CharacterMovement.MovementMode`), or a no-argument function
call ending in `()` (`K2_GetActorLocation()`). Structs print as `(X=.. Y=.. Z=..)`. At most 400 changes are kept
(`dropped=N` says more happened). Do the action meanwhile with a parallel `eval`.

## net_stats

`net_stats root=... seconds=2`: samples host and client at the same time and returns text per side.

- **Packets and bytes** come from `net.cpp`: the first call patches the game exe's `ws2_32` imports `sendto`/`recvfrom` with
  counting wrappers (IAT patch). They count every UDP datagram of the process, not only the net driver's, and start at
  zero at the first `net_stats` (a first call after a fresh start reads the window from the patch on). Cost: two atomic
  adds per datagram, forever after the first call (until the game exits).
- **Ping** is `PlayerState.Ping`, the engine's compressed byte (ms / 4): 4 ms resolution, replicated, so the client sees the
  server's view too. `NetConnection.AvgLag` and the lost-packet counters are plain C++ members, not reflected: not available
  (the tool says so). Cross-side UDP counts are diagnostic only: they include other traffic and differently timed windows, so they do not directly measure packet loss.
- **Tick rate**: `configured_tick_hz` is `NetServerMaxTickRate`; `measured_tick_hz` counts changes of `NetDriver.Time` between
  game-thread polls (one poll per frame at most), so it is a lower bound that equals the frame rate when frames are slower
  than the configured rate. **Frame time** is the previous frame's duration (`GetWorldDeltaSeconds`) sampled on each poll:
  a distribution (avg, p50, p95, max in ms), not every frame. With several games on one machine expect large p95.

The counter wrappers and transport tunnel both patch socket imports. Their combined behavior needs a runtime check;
do not assume `net_stats` is valid during a tunnel session (see [../../NOTES.md](../../NOTES.md)).

## screenshot_burst

`screenshot_burst count=3 interval_ms=500` (non-headless session only, `session_start headless=false`): a game-thread job
issues `HighResShot 1` every `interval_ms` (minimum 100); the tool waits for the new PNGs and returns the paths, oldest first.
Test run: 3 PNGs in 3.2 s at 600 ms (`.../Screenshots/WindowsNoEditor/HighresScreenshot00000.png` ... `00002.png`). If fewer files
appear it says so; use a longer interval. PNGs are written asynchronously, so the shot is the frame near the command, not exact.

## events

`events side=host since=60s|5m|2h|13:58:00|"2026-10-20 13:58:00" limit=200 include_status=false`. Reads `UE4SS.log` and
`PenDriverPro.log` directly (works after a crash too) and merges them into one local-time timeline. Sources:
`PT|` lines of our mods (except the periodic `PT|status`/`PT|repl` unless `include_status`), and these game lines: `LoadMap`
start and "Took N seconds to LoadMap", ServerTravel, "Welcomed by server", accepted connections, "Join succeeded", connection
close/timeouts/logout, LogNet errors, fatal errors and assertions. Possess changes and players coming and going are not in
the game log, so `mcp_observe.lua` polls twice a second and writes `PT|observe possess pawn=...` and
`PT|observe players n=2 <names>` when they change (test copies only). Identical consecutive events collapse to `xN`.

## Limits

- All of this is exploring, not proving (`docs/GAME-MCP.md`): turn a finding into a scenario check.
- `watch` still sees only ProcessEvent calls; the post-callback fires only when the call returns normally.
- One `watch_property`/`net_stats` job per side per call is the tested use; they share one 20 ms polling loop that idles when
  no job runs, so parallel jobs work but are not tested.
- `net_stats` window is the requested time plus about 0.5 s of console round trips (`window_s` reports the real one).
- Log-based `events` match this game's English log text; new game lines need a rule in `GAME_RULES` (`ext_observe.py`).
