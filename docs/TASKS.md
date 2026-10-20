# Tasks anyone can take

Self-contained work packages for contributors, so work doesn't wait on one PC. Each one gets its own branch, owns its own
files and merges into `main` on its own. They're sorted by cost; take one that fits your rig and your AI budget.

State on 2026-10-20: M1 is done and the M2 session core is merged. The owner's lane is closing the last M2 gaps (S5
abrupt disconnect, S6 run travel and run failure, S7 save writers, Q9 crash proof). **Don't take those**, and leave
`mod/PacificTogether/Scripts/session.lua` and `safety.lua` alone until that lane is merged (watch `main`).

## How to take a task

1. Read `CLAUDE.md`, `docs/PLAN.md` (requirement ids such as C3 or W6 refer to its tables), `docs/LANES.md` and `docs/TESTING.md`.
   Setup: `docs/DEVELOPING.md`. Most tasks need only its **Lua-only setup** (no C++ toolchain).
2. Claim it: open a **draft PR** titled `T12: <title>` as soon as you start. The list of open PRs is the claim board.
   If a task already has a PR, pick another one or comment there.
3. Branch from the current `main`, named as the task says (`feat/<area>-<topic>`, `research/<topic>`, `spike/<id>`).
4. Change only the files the task owns. Shared files take one-line additions only: the `FEATURES` list in
   `mod/PacificTogether/Scripts/main.lua`, `NOTES.md` (add your section), `docs/PLAN.md` (your row's state).
5. Before marking the PR ready: rebase on `main`, make your scenario pass, run its mutation (`run-test.ps1 -Mutate`) and
   show that it fails, then run the regression suite (T03, or the list in `docs/TESTING.md` until T03 exists). Paste
   the summaries into the PR. "Works" means an automated two-client test passed; report only checks that ran.
6. The owner reviews and merges. Squash-merge is fine.

You need your own copy of Pacific Drive on Steam, build 21896301 (the Whispers in the Woods DLC only for tasks that say
so). The game is Windows-only. A Mac can still do the "0 games" tasks: docs, reading the atlas, review.

## Sizes

Estimates for one contributor with Claude Code. Token figures come from the last lane run: 7 lanes cost about 3.0M
subagent tokens, roughly 0.4M per lane including verify and fix passes.

| Size | AI tokens | Wall time | Games at once | Who |
|---|---|---|---|---|
| **XS** | 0-50k (a chat, or none) | under half a day | 0-1 | anyone, also without an AI subscription |
| **S** | 50-300k | 1 day | 1-2 | a regular subscription |
| **M** | 0.3-1.5M | 2-5 days | 2 | a heavy user; split into sessions |
| **L** | 1.5-5M | 1-3 weeks | 2-4 | multi-agent lanes; mostly the owner's rig |

"Games" means test instances running at the same time. A headless one (`-Headless`) takes about 1.1 GB of RAM; a
windowed one takes several GB and a GPU.

Saving tokens: ask the running game (the game MCP `pacific-game`, `tools/repl.ps1`) before writing code that guesses. Start
from the fixtures (`-Fixture garage|zone|gateway`) instead of playing up to a state, and use `-Headless`. Use Sonnet for
the bulk of the work, write the failing test first (docs/LANES.md), and keep the diff to your own files.

## Index

| Id | Task | Size | Games | Needs | Depends on |
|---|---|---|---|---|---|
| T01 | Atlas tools into the repo | XS | 0 | owner (has the scripts) | |
| T02 | CHANGELOG.md | XS | 0 | | |
| T03 | Suite runner | S | 2 | | |
| T04 | Launcher: collect logs, uninstall, version | XS | 0 | | |
| T05 | Better remote body material | XS-S | 2 | | after M2 gaps merge |
| T06 | Playtest the dev preview | XS | 1 per PC | 2 people, 2 PCs | |
| T07 | Two-account Steam test (X6) | XS | 1 per PC | owner + Djecka | |
| T08 | Release build without test natives | S | 1 | C++ toolchain | |
| T09 | Name tag fade mutation | S | 2 | | |
| T10 | DLC report in the handshake (S4) | S | 2 | DLC | after M2 gaps merge |
| R1-R5 | Anomaly research: Abductor, Bunnies, Pickpocket, Spark Tower, Can Opener | S each | 1-2 | | |
| R6 | Junctions, routes and conditions (W3) | S | 1-2 | | |
| R7 | Instability, storm, exit warp, run failure (W4, W5) | S | 1-2 | | |
| R8 | Car state inventory (C3, C4) | S | 1-2 | | |
| R9 | Story, radio and cutscenes on the guest (G3) | S | 2 | | |
| R10 | DLC files for non-owners (W10) | XS | 0 | | |
| R11 | Guest damage, radiation, death (P4) | S | 2 | | |
| F1 | Lag and loss runs (Q2) | M | 2 | | T03 |
| F2 | One socket hook for counters and tunnel | M | 2 | C++ toolchain | |
| F3 | Tourists watched by any player (W7, P1) | M | 2 | | |
| F4 | ARC map marker (P8, P1) | M | 2 | | |
| F5 | Guest damage and death (P4) | M | 2 | | R11 |
| L1 | Car core: doors, passenger seat, smooth car (C1, C2, C7) | L | 2 | C++ maybe | |
| L2 | Intent channel and stable ids | L | 2 | | |
| L3 | Loot taken once, no duplicates (W1, W2, P2, G1) | L | 2-4 | | L2 |
| L4 | Car resources, repairs, trunk (C3-C6) | L | 2 | | L1, L2, R8 |
| L5 | Guest backpack and its persistence (P3, P5) | M-L | 2 | | L2 |
| L6 | Run lifecycle (W3, W4, W5, W11) | L | 2-4 | | L2, R6, R7 |
| L7 | Anomalies (W6), one PR per anomaly | M each | 2 | | L2, R1-R5 |
| L8 | Steam: tunnel, lobby, invite (S2, M6) | L | 2 | C++ toolchain, 2 Steam accounts for the last check | |
| L9 | Soak test (Q3) | M | 2 | | L6 |

Critical path: **L2** blocks most of M3-M5. **L8** (Steam) and the **R** tasks are independent of everything else, so they're
the best picks for a second person.

## XS: little or no AI, 0-1 games

### T01 Atlas tools into the repo
- Branch `feat/tools-atlas`. Owns `tools/atlas/`, the atlas section of `docs/research/game-atlas.md` and of `docs/DEVELOPING.md`.
- The scripts that build `local/atlas` (Blueprint listings, index TSVs, `xref.py`) live only in the owner's git-ignored
  `local/atlas/tools`. Move them to `tools/atlas/`, point their imports at `tools/kdis`, and make one command build the
  atlas from your own game copy into `local/atlas/`. Game data stays out of git.
- Done when: a fresh clone builds the atlas with that command, and the game MCP `xref` tool answers from it.

### T02 CHANGELOG.md
- Branch `docs/changelog`. Owns `CHANGELOG.md`.
- Keep a Changelog format (`docs/RELEASING.md`): an `Unreleased` section listing what M1 and M2 delivered, worded from
  `docs/PLAN.md`'s M1/M2 tables and `git log`. Players read it, so use plain words, not spike ids.
- Done when: the owner can cut 0.1.0 by renaming `Unreleased`.

### T04 Launcher: collect logs, uninstall, version
- Branch `feat/launcher-logs`. Owns `tools/package/launcher.ps1`, `tools/package/README.txt`.
- Add three things to the launcher window:
  - **Collect logs**: zips `ue4ss/UE4SS.log`, the mod's crash markers and `ue4ss/Mods/PacificTogether/version.txt` to the
    Desktop (Q6's "copy logs").
  - **Uninstall**: calls `install.ps1 -Uninstall` after asking first.
  - **Installed build**: a label showing the installed build.
- Test it against a fake game folder: hardlink the test copy's exe into an empty `PenDriverPro\Binaries\Win64` and set
  `$env:LOCALAPPDATA` to a scratch folder, so no real install or save is touched.
- Done when: all three work against the fake folder, and the window still fits at 100 % and 150 % display scaling.

### T05 Better remote body material
- Branch `feat/body-material`. Owns `docs/research/body-material.md`; one line in `session.lua` once the M2 lane has merged.
- Remote players are drawn with a cloth mannequin material because the game's own one is invisible (X13). Find a cooked
  material that looks like a person in a suit (atlas, FModel, or the `sessionmats` scenario), compare 3-5 candidates with
  screenshots from both sides, and pick one.
- Done when: `sessionlook` and `body` pass with the new material, and the doc shows the screenshots.

### T06 Playtest the dev preview
- No branch; file GitHub issues. Two people, two PCs, `launcher.cmd` from the newest dev zip.
- Script: join in the garage, walk around both, start a run, walk in a zone, come back, the guest leaves and rejoins.
  Write down what you saw. Every issue gets both players' `UE4SS.log` and a time.
- Done when: the issues are filed. This is the human check the release gate asks for (`docs/RELEASING.md`).

### T07 Two-account Steam test (X6)
- Owner and Djecka only. Follow `docs/spikes/X6.md`; record the results there and in `NOTES.md`.

### R10 DLC files for non-owners (W10)
- Branch `research/dlc-files`. Owns `docs/research/dlc-files.md`.
- Check, from the files alone, whether the Whispers in the Woods content ships to every owner of the base game: pak and
  depot lists, file sizes, chunk ids. List what the game checks before loading DLC content, if you can find it.
- Done when: the doc answers "can a guest without the DLC load a DLC map?" with yes, no or unknown, and the evidence.

## S: about 50-300k tokens, 1-2 games

### T03 Suite runner
- Branch `feat/test-suite`. Owns `tools/run-suite.ps1` and a "Suite" section in `docs/TESTING.md`.
- One command runs the regression list (all scenarios in `docs/TESTING.md`, excluding Steam and probe scenarios). It
  either runs them one after another, or takes `-Parallel N`, where each run gets its own `-Port` and `-ResultsDir`
  and the slot mutex caps how many games run at once. It prints a table (scenario, checks passed/total, time, result
  folder), exits non-zero on any failure, and writes `summary.md` for release notes and PRs.
- Done when: a full run on a clean `main` is green and a deliberately broken scenario turns it red.

### T08 Release build without test natives
- Branch `feat/native-release`. Owns `native/PacificTogetherNative/CMakeLists.txt`, the registration block in
  `dllmain.cpp`, `tools/build-native.cmd` (a flag) and `tools/package/package.ps1`.
- `PTNative_TestCrash` and `PTNative_TestAllowSentry` must not exist in a shipped `main.dll` (`docs/RELEASING.md`).
  Put them behind a CMake option that defaults to on for test builds, and make `package.ps1` refuse a DLL that still
  exports them, or build its own.
- Done when: `safety_crash` passes with a test build, and the packaged DLL doesn't contain the two names.

### T09 Name tag fade mutation
- Branch `test/nametag-fade`. Owns `test/PacificTogetherTest/Scripts/scenarios/nametag.lua`; may add a mutation switch to
  `mod/PacificTogether/Scripts/nametag.lua`.
- The fade-with-distance checks pass, but no mutation makes them fail (PLAN M2 table, P7). Add one (for example: fade
  turned off), and fix the checks if they pass anyway.
- Done when: `nametag` passes and `nametag -Mutate fade` fails on the fade checks.

### T10 DLC report in the handshake (S4)
- Branch `feat/session-dlc`. Owns the hello fields in `session.lua` (after the M2 lane merges) and `sessionmismatch.lua`.
- The handshake compares game build and mod version but doesn't report DLC. Add each side's DLC ownership to the
  hello, log both, and warn the host (don't refuse) when only one side has it.
- Done when: `session` and `sessionmismatch` pass, and a faked "no DLC" guest makes the host log the warning.

### R1-R5 Anomaly research (W6)
- Branch `research/anomaly-<name>`. Owns `docs/research/anomaly-<name>.md`. One task each: Abductor, Bunnies, Pickpocket,
  Spark Tower, Can Opener.
- Use `docs/research/tourists.md` as the model. Cover:
  - the classes and Blueprint functions, from the atlas or the game MCP;
  - which side runs what: start a zone fixture with a guest and watch it with the MCP `watch` / `trace` tools;
  - what the guest's own copy does wrong: a duplicate, a missing effect, or acting only on the host;
  - a sync plan of state broadcast and/or guest intents;
  - one test idea with a mutation.
- Done when: the doc exists with sources (scenario result folders, atlas paths) and no code outside `docs/`.

### R6 Junctions, routes and conditions (W3)
- Branch `research/run-routes`. Owns `docs/research/run-routes.md`.
- How the game picks the junction layout, route, weather, radiation and loot. Is it seeded? Is the seed in the save or
  in memory? Do host and guest pick the same thing today (X2 says zone loot is a separate random pick per side)? Then
  propose the smallest way to make the guest match the host.

### R7 Instability, storm, exit warp, run failure (W4, W5)
- Branch `research/run-lifecycle`. Owns `docs/research/run-lifecycle.md`.
- Map the run's timeline functions: instability rising, storm walls, gateway summon (lane E found `Select Exit Portal
  Actor`), the exit warp and the emergency protocol. For each one: what triggers it on the host, what the guest sees
  today, and what has to be sent. Coordinate with the owner's M2 lane, which is testing run failure travel now.

### R8 Car state inventory (C3, C4)
- Branch `research/car-state`. Owns `docs/research/car-state.md`.
- Every property and function behind doors, trunk, lights, wipers, ignition, gear, handbrake, horn, health, part
  damage, fuel, battery and tyres on `BP_PlayerCarNew_C` and its parts. For each, note:
  - its type;
  - whether UE replicates it today (check on the guest with the MCP);
  - the event that changes it;
  - the smallest state set that reproduces the dashboard on the guest.
- This feeds L4; X7 and X8 in `docs/spikes/` cover movement and seats.

### R9 Story, radio and cutscenes on the guest (G3)
- Branch `research/story-guest`. Owns `docs/research/story-guest.md`.
- Which actors play story missions, radio transmissions and cutscenes, what happens on a connected guest when the host
  triggers one (nothing, a broken camera, a stuck input, a crash), and what to block or route so the guest stays a safe
  bystander.

### R11 Guest damage, radiation, death (P4)
- Branch `research/guest-damage`. Owns `docs/research/guest-damage.md`.
- Where damage and radiation are applied to the player character, whether that runs for a guest's character on the
  host, the guest or neither, and what death does on a client. Feeds F5.

## M: about 0.3-1.5M tokens, 2 games

### F1 Lag and loss runs (Q2)
- Branch `feat/test-lag`. Owns `tools/run-suite.ps1` options (after T03) and the tunnel or `tools/udp-lag.ps1` glue.
- Run the core scenarios (session, sessionrejoin, travel, zonejoin, body, nametag) at 150 ms lag and 2 % loss through
  the tunnel emulation, and fix or file whatever breaks. Shipping UE has no NetEmulation (X5).
- Done when: those scenarios pass at 150/2, with the result folders in the PR.

### F2 One socket hook for counters and tunnel
- Branch `fix/native-socket-hook`. Owns `native/PacificTogetherNative/net.cpp`, `transport.cpp`.
- The game MCP's network counters (`net.cpp`) and lane A's tunnel (`transport.cpp`) both hook ws2_32
  `sendto`/`recvfrom`, so they break each other in one game (NOTES.md, lanes section). Make one hook that counts and then
  hands the packet to the tunnel when the tunnel is on.
- Done when: `listen` and `travel` pass with `-Tunnel` and the MCP counters on, and the counters show the tunnel's traffic.

### F3 Tourists watched by any player (W7, P1)
- Branch `feat/tourists`. Owns `mod/PacificTogether/Scripts/tourists.lua` and its scenario.
- Lane E proved a `CreepCheck` hook freezes Tourists (`docs/research/tourists.md`, scenario `tourist`). Turn it into a
  shipping feature: a Tourist counts as observed if either player is looking at it. P1 (owner deferred it to 1.1), but
  it's isolated and ready to build.
- Done when: a scenario passes with the guest looking and the host turned away, and a mutation fails it.

### F4 ARC map marker (P8, P1)
- Branch `feat/arc-marker`. Owns `mod/PacificTogether/Scripts/arcmarker.lua` and its scenario.
- Lane E registered a marker but didn't see it drawn (`docs/research/arc-marker.md`). Make the other player show on the
  ARC map, on both sides.

### F5 Guest damage and death (P4)
- Branch `feat/guest-damage`. Owns `mod/PacificTogether/Scripts/damage.lua` and its scenario. Starts from R11.

## L: 1.5M+ tokens, 1-3 weeks, multi-agent lanes

Check with the owner before starting one of these; they shape the architecture. Run them as lanes per `docs/LANES.md`.

### L1 Car core (M3: C1, C2, C7)
- Branch `feat/car-core`. Owns `mod/PacificTogether/Scripts/car.lua`, car scenarios (promote `carseat`, `carride`,
  `carlib` from the test mod), possibly native code for the kinematic car.
- The plans are ready: X7 (motion-time Hermite interpolation, an adaptive delay of 100-250 ms, and the guest's own car copy
  destroyed) and X8 (the mirrored driver seat, the guest-side seat guard, the ARC moved between the seats).
- Done when: both players enter through the game's own doors, the guest rides as a passenger, the car looks smooth at 100 ms
  (tools/car-error.ps1 numbers), and `carseat`/`carride` pass as shipping features.

### L2 Intent channel and stable ids (foundation)
- Branch `feat/intents`. Owns `mod/PacificTogether/Scripts/intents.lua`, `ids.lua`, and the channel's native part if needed.
- A reliable guest -> host message ("open container X", "take item Y") that the host runs through the game's own
  function, plus a host -> guest state broadcast. Ids: the path for loaded actors, class + spot + ordinal for spawned
  ones (X2). X4 says the guest interacts locally and hooked effect points send intents.
- Done when: one end-to-end intent (open a garage container) round-trips, with a scenario and a mutation; L3-L7 build on it.

### L3 Loot taken once, no duplicates (M4: W1, W2, P2, G1)
- Branch `feat/loot`. Depends on L2. Containers, pickups, scrap, siphoned fuel and anchors are taken once, and nothing the host
  spawns has a duplicate on the guest. X3 lists the duplicate classes.

### L4 Car resources, repairs, trunk (M3: C3-C6)
- Branch `feat/car-state`. Depends on L1, L2 and R8.

### L5 Guest backpack and its persistence (M4: P3, P5)
- Branch `feat/backpack`. Depends on L2. X12 proved the one-line record round-trips through a side file next to the
  host's save. Make it the shipping path, saved on every host save and when the guest leaves.

### L6 Run lifecycle (M5: W3, W4, W5, W11)
- Branch `feat/run`. Depends on L2, R6 and R7.

### L7 Anomalies (M5: W6)
- Branch `feat/anomaly-<name>`, one PR per anomaly. Depends on L2 and that anomaly's R task.

### L8 Steam (M6: S2)
- Branch `feat/steam`. Owns `native/PacificTogetherNative/steam.cpp`, `transport.cpp` (coordinate with F2), a
  `mod/PacificTogether/Scripts/steam.lua`.
- Tunnel the session over Steam Messages, with a friends-only lobby, invites, "Join game" from the friends list, rich
  presence and disconnect detection. X5 and X6 laid the groundwork. Known problem: the first unreliable send after a
  reliable one stalls the game thread 1-6 s, so send off the `sendto` path.
- Most of it can be built with one account (`steamsolo`, loopback); the last check needs two (T07).

### L9 Soak test (Q3)
- Branch `test/soak`. Depends on L6. Host and guest bots do runs for 2 hours with no crash and no desync.
