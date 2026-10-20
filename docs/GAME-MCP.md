# Game MCP (`pacific-game`)

An MCP server that lets an agent (or you) ask a RUNNING test game things directly: run Lua, list objects, read a
class's properties and functions, call a function, record which functions fire, take a screenshot, read logs, query the
Blueprint atlas. It replaces "write a scenario, relaunch, read logs" for exploration. It builds on the live console
(`tools/repl.ps1`, `docs/TESTING.md`). Test pairs only, never the real install.

## Setup after a clone

- Python 3.9+ on PATH as `python`. Standard library only, nothing to install.
- A test pair (`tools\setup-test.ps1`, `docs/DEVELOPING.md`, "Test copies and tests"). Every tool refuses a root that is
  not `<root>\client1\PenDriverPro` and anything under the Steam install or `%LOCALAPPDATA%\PenDriverPro`.
- `watch` needs the native mod with `native/PacificTogetherNative/trace.cpp`: build it once (or after changing it) with
  `tools\build-native.cmd` (Epic/GitHub steps in `docs/DEVELOPING.md`, "Clone and build") or `tools\build-mod-fast.ps1` in a
  worktree. The DLL is locked while a game runs from a copy that junctions to this checkout: stop sessions first. The
  other tools work without the C++ build.
- `xref` needs `local/atlas` (git-ignored, game-derived; `docs/research/game-atlas.md`). Without it the tool says so;
  ask the owner for the folder or rebuild it as described there.
- Claude Code reads `.mcp.json` at the repo root (server `pacific-game`, `python tools/gamemcp/server.py`; the server finds
  the repo from its own file path, the working directory does not matter). Approve the project server once, and
  **start a new Claude Code session** after cloning or pulling: servers are loaded at session start.
- Check without an agent: `python tools/gamemcp/selftest.py --root C:/PTLanes/probe --port 7801` (starts real games).

## Tools

All take `root` (default `C:/PacificTogetherTest`) and `side` (`host` = client1, `client` = client2, default host).
Results are capped at 20k characters and say when cut. Errors come back as tool errors, never as a crash.

| Tool | What it does | Example |
|---|---|---|
| `session_start` | runs `run-test.ps1 -Scenario repl` detached, waits until host (and client) answer | `root=C:/PTLanes/probe port=7801 players=2 headless=true`; `fixture=zone`; `map=/Game/Maps/RunProto/RB_Garage` |
| `session_status` / `session_stop` | state of both sides / stop both, wait for the runner, kill only the runner it started if it hangs | |
| `eval` | Lua through the repl file protocol (same files and ids as `repl.ps1`); Lua errors are tool errors | `lua="return state()"`, `lua="out(first('BP_PlayerCarNew_C'):GetFullName())"` |
| `find` | live objects of a class in the current world, full names | `class_name=BP_PlayerCarNew_C limit=20` |
| `describe` | properties with current values and functions with parameters, own class first then parents | `target=<full name from find>` or a class name |
| `call` | call a UFunction with numbers, strings, bools, `{"obj": "<path>"}` | `object_path=<car> function=K2_GetActorLocation args_json=[]` |
| `watch` | records ProcessEvent calls whose function name contains the filter (`a|b` or a list), with the calling object, for N seconds | `filter=Character:Jump seconds=5` while another `eval` acts. The filter matches the whole function path, so a bare `Character` also catches `/Game/Characters/...` animation functions: include the class or function. Only calls through ProcessEvent are seen (Blueprint-to-Blueprint calls inside the script VM are not) and no argument values are recorded |
| `screenshot` | `HighResShot` in a non-headless session, returns the PNG path | open it with an image reader |
| `logs` | tail of the copy's `UE4SS.log` (`game_log=true`: `PenDriverPro.log`), regex filter | `pattern="PT\|" tail=50` |
| `xref` | `local/atlas/xref.py` callers / callees / class / find | `command=callers name=SaveGame` |

State and sync (`snapshot`, `compare`, `diff_snapshots`, `fixture_save`, and `session_start fixtures_dir=`): `docs/gamemcp/state.md`.

`session_start` waits for a free game slot (`PT_SLOTS`) and takes 15-60 s headless, longer in a queue. Use your own root
and port (`docs/TESTING.md`, "Parallel lanes"): one session per root, a second `session_start` on a busy root is refused.

How `watch` works: Lua `PTNative_TraceStart(filter, max)` / `PTNative_TraceRead()` / `PTNative_TraceStop()`
(`trace.cpp`). The ProcessEvent hook is registered on start and removed on stop, so tracing costs nothing when off; matching
is cached per function, and a bounded ring keeps the last `max_calls` (the header says `dropped=N` if it overflowed).

## Limits

- **Exploring is not proving.** Write the answer down and turn it into a scenario check (`docs/TESTING.md`) before relying
  on it; "works" still means an automated two-client run passed.
- `watch` sees only calls that go through the engine's `ProcessEvent` (native code, Lua, delegates, replication entry
  points). Blueprint-to-Blueprint calls inside the script VM are not seen, and no argument values are recorded: use
  `describe` for signatures and hook the function in Lua if you need its arguments.
- `call` and `eval` change the live game; out params of a UFunction come back as extra result lines in UE4SS Lua form.
  Object arguments must be given as `{"obj": "<path or full name>"}`; structs and arrays are not supported (use `eval`).
- `find` keeps only objects of the current world; widgets and other non-world objects need `any_world=true`.
- `screenshot` needs a rendered window (`headless=false`); a minimized window may not render.
- A hung or crashed game shows as "no answer within N s": see `session_status` and `logs`.
