# How we run work lanes

Rules for every workflow or agent lane from M3 on (owner decision 2026-10-20: speed and token cost matter most).
Background: `coop-anything/playbook/multi-agent-workflows.md`, `methods.md` section 8, `lessons.md`.

## Priority: gameplay first, crucial checks only (owner, 2026-10-20)

- Gameplay and sync features come first: item sync, loot, the guest's backpack, the car, anything a player notices.
- Each feature gets **one** scenario that proves it works, plus its mutation. After each merge, run the smoke set:
  `session`, `travel`, `body`, `sessionrejoin`, `zonejoin`, `safety`, about 10 minutes. The full suite runs only before a
  build goes to friends or a release.
- **No full suites inside lanes (owner, 2026-10-21):** all scenarios together take more than 30 minutes. A lane runs
  only its own proving scenario and its mutation. The lead runs the full suite **once**, on main after all lanes merged;
  each failing scenario goes back to an agent, who fixes it and reruns **only the failing scenarios**, not the suite.
- Don't hunt edge cases (rare crashes, odd disconnect timings, rarely used save paths) and don't polish tests or
  over-engineer. Write a found edge case into `NOTES.md` as a known gap and move on, unless it breaks normal play.

## Roles

- **Lead (Opus):** splits the milestone into requirements, writes each requirement's **failing test scenario first**
  (the definition of done, with its mutation), verifies results, merges. Never implements a lane itself.
- **Workers (Sonnet):** one bounded job each: make the given scenario pass. Launch with `model: sonnet`.
- **Verifier:** for code lanes, rerun the lane's scenarios and mutations and read the checks for trivial passes
  (Sonnet is enough when the scenario came from the lead). Research-only lanes get a light check.

## One requirement = one tournament

1. **Predict first (cheap, no game):** read the game's own code before writing ours: `docs/research/game-atlas.md`,
   `local/atlas/xref.py` (Blueprint bytecode and call index), `local/dumps` (native classes). Lane E's Tourist work
   is the model: the bytecode reading predicted the behaviour, one test confirmed it.
2. **Probe the hooks you will rely on** with the live console (`tools/repl.ps1`, `docs/TESTING.md`): does the
   function fire on this setup (host, client, native travel)? Lesson 16: a hook that never fires wastes everything built on it.
3. **Write 2-3 candidate implementations** behind a switch (`PT_VARIANT=a|b|c`, read once at start), each small and
   independent.
4. **One batch run decides:** run the lead's scenario once per variant (headless, fixture save if the state needs
   one: `-Fixture`). The summary picks the winner; delete the losing variants and the switch. No agent debate.
5. **Only if every variant fails** does the lane iterate against the game (the slow, expensive path), using the
   console rather than relaunching per question.

## Speed tools

| Tool | Use |
|---|---|
| `tools/repl.ps1` + `repl` scenario | ask the running game questions in ~1 s instead of a relaunch per question |
| `tools/repl.ps1 -Reload` | load edited mod Lua into the running games in seconds instead of relaunching (not `main.dll`) |
| `tools/gamemcp` (MCP `pacific-game`, `docs/GAME-MCP.md`) | the same console as agent tools: find/describe/call objects, watch which functions fire, screenshot, logs, xref |
| `local/atlas`, `docs/research/game-atlas.md` | grep the game's Blueprint code and call graph instead of re-extracting it |
| `tools/run-test.ps1 -Fixture <name>` | start a test in a saved state (garage, zone, gateway) instead of building it each run |
| `tools/build-mod-fast.ps1` | build our C++ mod in a worktree in seconds against the main checkout's UE4SS build |
| `-Headless`, `-Port`, `-Root`, `-ResultsDir` | parallel lanes without cross-talk (`docs/TESTING.md`, "Parallel lanes") |

## Hygiene that keeps lanes mergeable

- **Progress lines (owner, 2026-10-21):** at each milestone (reproduced, cause found, fix written, scenario passes,
  mutation fails, blocked) a lane appends one line `HH:mm <lane> <under 20 words>` to `local/progress.log`. The owner
  watches it (`Get-Content local\progress.log -Wait`); it costs no lead tokens.

- One worktree, test pair (`C:\PTLanes\<lane>`) and port per lane; scenarios in their own files under
  `test/PacificTogetherTest/Scripts/scenarios/`; findings in `docs/spikes/<id>.md`; features in their own module
  files in `mod/PacificTogether/Scripts/` and `native/PacificTogetherNative/`.
- Shared files (`main.lua`, `common.lua`, `run-test.ps1`, `dllmain.cpp`) only get small additive edits, listed in the report.
- Commit WIP on the lane branch before any stop, so a stopped run continues instead of restarting
  (`local/resume/RESUME.md` shows how).
- At most 4 test pairs at once on the owner's PC (`PT_SLOTS`).
