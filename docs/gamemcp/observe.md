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

```
watch filter=Character:Jump|K2_SetActorLocation seconds=4 args=true results=true      (host calls p:K2_SetActorLocation({X=100,Y=200,Z=300}) meanwhile)
+0.00ms  Function /Script/Engine.Character:Jump  PDP_MainCharacter_C ...PDP_MainCharacter_C_2147464078
+0.11ms  Function /Script/Engine.Actor:K2_SetActorLocation  PDP_MainCharacter_C ...  NewLocation=(X=100.000000,Y=200.000000,Z=300.000000), bSweep=False, bTeleport=False
+0.81ms  <-Function /Script/Engine.Actor:K2_SetActorLocation  PDP_MainCharacter_C ...  SweepHitResult=(Location=(X=0.000000,...)...), ReturnValue=True

watch filter=InventoryContainerComponent_C:Get args=true results=true                 (GetInventoryName, GetAllItems on the garage tube)
+0.03ms  <-Function ...BP_InventoryContainerComponent_C:GetInventoryName  ...  InventoryContainerName=
+0.10ms  <-Function ...BP_InventoryContainerComponent_C:GetAllItems       ...  Stored Items=<array n=0>
```

Cost: with tracing off nothing is hooked. On: a mutex and a hash lookup per ProcessEvent call; matching functions (and their
parameter property lists, built once per function) cost a text export per parameter, capped at 12 parameters, 160 characters
each and about 700 characters per call, in a ring of `max_calls` (default 500). Keep the filter narrow: a broad filter such as
`Tick` records thousands of calls per second. Not benchmarked beyond the sub-millisecond pre-to-post gap seen above.
A bug fixed on the way: the old `max_calls` argument was never read (always 500); it works now.

## watch_property

`watch_property target=<object path | class name> properties=[...] seconds=5 interval_ms=100 cap=8`. A game-thread job polls
every `interval_ms` (minimum 20; it can not go faster than the game's frame rate) and logs only changes, with the time since
start. `target` with a `/` is one object (full name from `find`); a bare class name watches every live instance of the
current world, up to `cap`. A property is a name, a dotted chain (`CharacterMovement.MovementMode`), or a no-argument function
call ending in `()` (`K2_GetActorLocation()`). Structs print as `(X=.. Y=.. Z=..)`. At most 400 changes are kept
(`dropped=N` says more happened). Do the action meanwhile with a parallel `eval`.

```
watch_property target=PDP_MainCharacter_C properties=["K2_GetActorLocation()","CharacterMovement.MovementMode"] seconds=3   (host jumps)
targets=1 props=2 samples=26 changes=13
+32ms    PDP_MainCharacter_C_2147463348  K2_GetActorLocation()  = (X=100 Y=200 Z=194.5138)
+1115ms  ...                             K2_GetActorLocation()  (X=100 Y=200 Z=194.5138) -> (X=100 Y=200 Z=221.8155)
+1115ms  ...                             CharacterMovement.MovementMode  1 -> 3
+1484ms  ...                             K2_GetActorLocation()  (X=100 Y=200 Z=284.0927) -> (X=100 Y=200 Z=293.1786)   (apex)
+2033ms  ...                             CharacterMovement.MovementMode  3 -> 1
```

## net_stats

`net_stats root=... seconds=2`: samples host and client at the same time and returns text per side.

```
== host
window_s=2.65
net=listen
driver=IpNetDriver_2147480355 configured_tick_hz=30 measured_tick_hz=20.8 (lower bound: polled every ~20 ms, N polls)
connection IpConnection_2147462937 last_receive_age_s=-0.00
player DESKTOP-L4H66PM-9ED0 ping_ms=0 (Ping byte 0 x4: 4 ms steps, 0 = under 4 ms)
player DESKTOP-L4H66PM-0537 ping_ms=24 (Ping byte 6 x4: ...)
udp_out packets_per_s=39.3 bytes_per_s=488   udp_in packets_per_s=39.6 bytes_per_s=468
lost_packets: not exposed (UNetConnection counters are plain C++ members; reflection cannot read them)
frame_time_ms samples=56 avg=22.30 p50=19.44 p95=65.39 max=68.16
```

- **Packets and bytes** come from `net.cpp`: the first call patches the game exe's `ws2_32` imports `sendto`/`recvfrom` with
  counting wrappers (IAT patch). They count every UDP datagram of the process, not only the net driver's, and start at
  zero at the first `net_stats` (a first call after a fresh start reads the window from the patch on). Cost: two atomic
  adds per datagram, forever after the first call (until the game exits).
- **Ping** is `PlayerState.Ping`, the engine's compressed byte (ms / 4): 4 ms resolution, replicated, so the client sees the
  server's view too. `NetConnection.AvgLag` and the lost-packet counters are plain C++ members, not reflected: not available
  (the tool says so). Packet loss in tests: compare `udp_out` of one
  side with `udp_in` of the other.
- **Tick rate**: `configured_tick_hz` is `NetServerMaxTickRate`; `measured_tick_hz` counts changes of `NetDriver.Time` between
  game-thread polls (one poll per frame at most), so it is a lower bound that equals the frame rate when frames are slower
  than the configured rate. **Frame time** is the previous frame's duration (`GetWorldDeltaSeconds`) sampled on each poll:
  a distribution (avg, p50, p95, max in ms), not every frame. With several games on one machine expect large p95.

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

```
14:11:14.935 [mod]  PT|console servertravel /Game/Maps/RunProto/RB_Garage?listen
14:11:14.998 [game] connection/player left: LogNet: UNetConnection::Close: [UNetConnection] RemoteAddr: 127.0.0.1:63047 ...
14:11:18.996 [game] map load start /Game/Maps/RunProto/RB_Garage?listen
14:11:29.000 [game] map loaded /Game/Maps/RunProto/RB_Garage in 10.003298s
14:11:31.115 [mod]  PT|observe possess pawn=PDP_MainCharacter_C_2147450335
14:11:35.785 [game] player joined: DESKTOP-L4H66PM-0537
```

## Limits

- All of this is exploring, not proving (`docs/GAME-MCP.md`): turn a finding into a scenario check.
- `watch` still sees only ProcessEvent calls; the post-callback fires only when the call returns normally.
- One `watch_property`/`net_stats` job per side per call is the tested use; they share one 20 ms polling loop that idles when
  no job runs, so parallel jobs work but are not tested.
- `net_stats` window is the requested time plus about 0.5 s of console round trips (`window_s` reports the real one).
- Log-based `events` match this game's English log text; new game lines need a rule in `GAME_RULES` (`ext_observe.py`).
