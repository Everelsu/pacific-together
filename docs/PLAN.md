# Pacific Together: plan

Status: draft 1, 2026-10-19. Source research: `docs/research/` (game context, networking, PDCoopNet facts).
Anything marked **(spike)** is a design assumption that a milestone M1 experiment must confirm before we build on it.

## 1. Product decisions (made by the owner)

| # | Decision |
|---|---|
| D1 | **2 players**: host + one guest. 3-4 players is a later phase, not designed against but not built for. |
| D2 | **Host's save only.** The guest plays in the host's world. Nothing the mod does may write to the guest's own saves. |
| D3 | **Steam invite / join** is the target way to connect. Direct IP stays for tests and VPN users. |
| D4 | **v1.0 = full run loop**: garage -> junctions -> gateway -> garage together, with shared car state and loot. Story plays as far as the host's save allows. |
| D5 | Name: **Pacific Together**. Mod folder `PacificTogether`. |
| D6 | **Guest death**: respawn at the car, backpack contents dropped as a recoverable bag. Host death or a wrecked car = run failure for both, with the host's failure penalty applied to both backpacks. |
| D7 | **Guest loot persists**: the guest's backpack is stored with the host's save (per guest SteamID) and restored on their next join. Full immersion, no fresh starts. |
| D8 | **DLC**: only the host needs to own Whispers in the Woods. |
| D9 | Team: ikeepcalm (owner) and Djecka. Two Steam accounts, both with the game and the DLC. |
| D10 | Public repo https://github.com/ikeepcalm/pacific-together, MIT license. |
| D11 | **Only the host drives in v1.0.** Guest driving is v1.1 (C8). |
| D12 | **Guest sits in the passenger seat; the ARC device moves** (dashboard or between the seats) so both can reach it (C7, spike X8). |
| D13 | **Both players control the run**: either can plan the route, summon a gateway, use ARC energy. The host performs every action (W11). |
| D14 | **Sessions are always open to Steam friends** while the mod is installed and a save is loaded (friends-only lobby, "Join Game" or invite). No hotkey (S1, S2). |
| D15 | **Host crash or disconnect**: the guest's backpack rolls back to the host's last save, same as the host's own progress. |
| D16 | **Crash reports**: the mod turns off the game's crash upload (Sentry, CrashReportClient) while installed and writes its own crash log for our GitHub issues (Q9). |
| D17 | **Finding each other**: a Steam name tag over the other player and a marker for them on the ARC map (P7, P8). |
| D18 | **No outside testers before 1.0**: only ikeepcalm and Djecka. Pre-1.0 builds are GitHub draft releases (collaborators only). |
| D19 | **Tourists freeze if any player looks at them** (W7 moves to P0). |
| D20 | **No co-op difficulty scaling**: the host's difficulty preset rules; the mod changes no balance values. |
| D21 | **Guest can use the garage stations** (Fabrication, Tinker, Detailing) in v1.0, spending the host's shared resources (G2). |
| D22 | **ARC scope for the guest in v1.0: gateway summon and energy use only.** Route planning stays host-only until v1.1 (it runs through native `UBaseRouteState`; lane E research, 2026-10-20). Narrows D13 / W11. |
| D23 | **Prove the crash-upload block (D16/Q9) before 1.0** with one deliberate test-copy crash while a Windows Firewall rule blocks the test copy's CrashReportClient outbound (owner approved; needs a UAC prompt). Until then test copies have no CrashReportClient.exe at all (`setup-test.ps1` removes it). |
| D24 | **Deferred to v1.1** (not immersion blockers): guest use of the garage stations (D21, G2), the other player's marker on the ARC map (D17 second half, P8), Tourists freezing for any player's view (D19, W7). Name tags (P7) stay in v1.0. Research for all three is done (`docs/research/garage-stations.md`, `arc-marker.md`, `tourists.md`). |

## 2. Fixed constraints

- One game build: Steam buildid 21896301 (v1.15.0, last patch 23 Feb 2026), exe SHA-256 in `CLAUDE.md`. Steam only;
  Epic / Xbox / Game Pass builds are out of scope.
- Both players run the same game build and the same mod version. The mod checks both on join and refuses with a
  clear message otherwise. DLC ownership may differ (D8): the handshake reports it, see W10.
- No game files or extracted assets ship or get committed. The release is our code plus a pinned UE4SS.
- Ironwood says "no plans for multiplayer" and has no official mod support; stay a pure client mod, no online services.

## 3. Architecture (provisional)

The prototype proved UE 4.27's own listen server works in this game: join, character replication with prediction,
actor and attachment replication. The game's own code has zero replication. So:

| Layer | Choice | Why |
|---|---|---|
| Bodies (characters, car transform, host-spawned actors) | Stock UE replication over the game's `IpNetDriver`; host is the listen server | Already works; gives prediction, possession, attachment for free |
| Game state (inventory, loot taken, car parts and health, fuel, battery, run and storm state, quest flags) | **Intent messages**: the guest sends an intent ("open container X"), the host runs the game's own function and broadcasts the result as state. Stable ids for every object (spike) | No runtime replication flag surgery (unproven); host stays the only real game; pattern from Multivoid |
| Hook layer | UE4SS (pinned build) + **Lua** for gameplay logic, plus **one C++ DLL** for what Lua cannot do: transport, Steam, native travel if needed | Lua iterates fast; C++ only where required |
| Transport | **Tunnel UE's UDP packets over Steam P2P** (`ISteamNetworkingMessages`) by hooking the game socket's `sendto/recvfrom` in-process, using the game's own `steam_api64.dll` under appid 1458140. A second reliable channel carries intent messages: **built** (`msg.cpp`, `net.lua`): guest to host on `ServerExecRPC` (a no-op in shipping), host to guest on `ClientMessage`, both on the game connection | Keeps the working listen server; no ports to forward; precedent: HSMMod uses the game's own Steam DLL |
| Connect | Friends-only Steam lobby, rich presence `connect`, overlay invite, "Join game" from the friends list | D3 |
| Authority | Host owns the world, the car, anomalies and saves. The guest owns only their input | D2; simplest consistent model |

Open alternatives kept on the table until spikes finish: own state sync for everything (if UE replication fights us),
VPN-only internet play (if Steam relay does not work for this appid).

## 4. Requirements and priorities

P0 = needed for v1.0. P1 = v1.x. P2 = later, maybe. Won't = out of scope.

### Session

| Id | Requirement | P |
|---|---|---|
| S1 | Loading any save opens a friends-only session automatically (D14), in the garage or mid-run | P0 |
| S2 | Guest joins via Steam invite or friends list "Join game" | P0 |
| S3 | Guest joins via direct IP (tests, VPN) | P0 |
| S4 | Handshake checks game build and mod version (mismatch -> clear message, no join) and reports both players' DLC | P0 |
| S5 | Guest can leave and rejoin at any time, also mid-run and while the car is moving; host never crashes from it | P0 |
| S6 | The session survives every map change the game makes (garage <-> junctions <-> garage, run failure, quit to menu) without a second map load | P0 |
| S7 | Guest's own saves and settings are never written while in a session (the game's client-side autosave must be blocked) | P0 |
| S8 | In-game menu entries (session status, kick, close the session) | P1 |
| S9 | 3-4 players | P2 |

### Players

| Id | Requirement | P |
|---|---|---|
| P1 | Each player has their own character, sees the other move and animate (walk, crouch, carry, tool use) | P0 |
| P2 | Guest uses the game's own interaction (doors, containers, pickups, anchors, tools) with host authority | P0 |
| P3 | Guest has a working backpack and quick slots | P0 |
| P4 | Damage, radiation and death for the guest (D6) | P0 |
| P5 | Guest backpack persists between sessions, stored next to the host's save slot per guest SteamID, saved whenever the host saves and when the guest leaves; a new guest starts empty (D7). Must not change the game's own save format | P0 |
| P6 | Voice/text chat | Won't (Steam has it) |
| P7 | Steam name tag over the other player, fading with distance (D17) | P0 |
| P8 | The other player shown on the ARC map (D17; deferred by D24) | P1 |

### Car

| Id | Requirement | P |
|---|---|---|
| C1 | Host drives; guest rides as passenger; both enter and exit through the game's own door interaction | P0 |
| C2 | Car moves smoothly on the guest's screen (interpolation), also at 100 ms ping | P0 |
| C3 | Visible car state matches: doors, trunk, lights, wipers, ignition, gear, handbrake, horn | P0 |
| C4 | Car health, part damage and status effects, fuel, battery, tyres: one truth on the host, shown on the guest's dashboard | P0 |
| C5 | Guest can repair, refuel and swap parts on the car during a run (intents) | P0 |
| C6 | Trunk and car storage shared | P0 |
| C7 | Guest sits in the passenger seat; the ARC device is moved so both can reach it (D12, spike X8) | P0 |
| C8 | Either player can drive (swap driver) | P1 |
| C9 | Car sounds and radio on the guest's side | P1 |
| C10 | Rear seats for players 3-4 | P2 |

### World and run

| Id | Requirement | P |
|---|---|---|
| W1 | Loot is taken once: containers, pickups, scrap from wrecks, siphoned fuel, anchors | P0 |
| W2 | No client-side duplicates of anything the host spawns (cars, loot, props, anomalies) | P0 |
| W3 | Same junction for both: route choice, conditions, weather, radiation | P0 |
| W4 | Instability, storm walls, gateway summon and the exit warp happen for both at the same time | P0 |
| W5 | Run failure (emergency protocol) returns both players to the garage with the host's failure penalty | P0 |
| W6 | Anomalies run on the host and look and act the same for the guest; the run-shaping ones first: Abductor, Bunnies, Pickpocket, Tourists, Spark Tower, Can Opener | P0 |
| W7 | Tourists count as observed if any player looks at them (D19; deferred by D24) | P1 |
| W8 | Remaining anomalies and Whispers in the Woods content | P1 |
| W9 | Expeditions mode | P1 |
| W11 | Either player can summon the gateway and use ARC energy (D13, D22); guest route planning is P1 | P0 |
| W10 | A guest without the DLC can play the base-game zones with a DLC-owning host. Whether DLC content is installed for non-owners is unknown; until checked, the host is warned before travelling into DLC content | P1 |

### Garage, story, progression

| Id | Requirement | P |
|---|---|---|
| G1 | Guest can walk the garage and hand items to the host or the locker | P0 |
| G2 | Fabrication, Tinker, Detailing stations: host-only in v1.0; guest use with the host performing each action on the shared resources is v1.1 (D21, D24) | P0 (guest use P1) |
| G3 | Story missions, radio transmissions, cutscenes play on the host; guest is a bystander and nothing breaks | P0 |
| G4 | Story audio and cutscenes for the guest | P1 |
| G5 | Co-op forces "Pause Game While in Menus" off and disables the Chrono Dilator | P0 |
| G6 | Saving, Suspend and manual saves: host only | P0 |

### Quality, install, ops

| Id | Requirement | P |
|---|---|---|
| Q1 | Every P0 feature has an automated two-instance test scenario that passes, plus a mutation check showing the test can fail | P0 |
| Q2 | Lag and loss runs (`PktLag=150`, `PktLoss=2`) pass the core scenarios | P0 |
| Q3 | 2-hour soak (host + guest bots doing runs) without crash or desync | P0 |
| Q4 | One human playtest of a full run before each minor release (the owner and a friend) | P0 |
| Q5 | Install: one zip into the game folder, pinned UE4SS included or linked by hash; uninstall = delete the folder | P0 |
| Q6 | The mod logs to its own file; a "copy logs" step for bug reports | P0 |
| Q7 | The mod is inert unless a session is active (single-player stays vanilla with the mod installed) | P0 |
| Q8 | Nexus Mods release | P2 |
| Q9 | Game crash upload (Sentry, CrashReportClient) off while the mod is installed; the mod writes its own crash log (D16) | P0 |

### Won't do

Dedicated servers, cross-platform, other game builds, anti-cheat or online services, shipping game assets,
split screen, achievements sync.

## 5. Milestones

Each milestone ends when its tests pass and `NOTES.md` records the results. Sizes are guesses for part-time work with
agents doing most of the coding: S = days, M = 1-2 weeks, L = 3-4 weeks.

### M0 Foundations (S)

- Script that makes the test copies (`client1` full copy, `client2` hardlinks + own Binaries), `-NotInstalled`, `steam_appid.txt`.
- Pin UE4SS: choose the build (likely the experimental build the prototype used), record SHA-256, install into test copies.
- Mod skeleton: `PacificTogether` Lua mod + C++ DLL that builds in CLion (MSVC, CMake) and loads.
- Test harness v2: our own runner, ideas from the prototype's (status lines, crash folders, log archive), plus: exit code,
  kills only test-copy processes, scenario per file, test bots kept out of the shipping mod.
- UE4SS dumps (UHT headers, Lua types, USMAP) into `local/` for reading.

### M1 Spikes: retire the big risks (M)

Timeboxed experiments. Each writes Observations / Derived / Unknowns to `NOTES.md` and ends in keep / change the design.

| Spike | Question | Pass criterion |
|---|---|---|
| X1 | Does a `RegisterLoadMapPreHook` that adds `listen` keep the session through the game's own travel? | Host still listening after a native map change, no second load |
| X2 | Can the host make a loot actor replicate (`SetReplicates`), and do level-placed actors have the same full name on both sides (free stable ids)? | Actor appears on guest, disappears on pickup; name diff empty |
| X3 | Do the game's client-side spawners and managers create duplicates or overwrite state on the guest? Survey all client-local actors | List of actors and Blueprints that need authority gating |
| X4 | Can the guest use the game's own interaction and inventory with single-reference managers (`CharacterActor`, `NewCarActor`)? | Guest opens a container through the game's code path |
| X5 | Tunnel UE packets through a `sendto/recvfrom` hook over localhost UDP | Session suite passes through the tunnel |
| X6 | Steam lobby + P2P messages under appid 1458140 between two real accounts (**needs the owner and a friend**) | Echo works, lobby invite opens the game and joins |
| X7 | Car on the guest at 100-150 ms lag: error and feel | Position error logged; interpolation plan |
| X8 | Passenger seat: where does the guest sit given the ARC device? | Guest seated, ARC still usable by host |
| X9 | UE4SS C++ ABI: link UE4SS vs zero-import DLL; 10 launches each | Choice made, no crash |
| X10 | Block the guest's autosave and settings writes | Guest SaveGames folder unchanged after a session |
| X11 | Connect timeout on long loads (20 s threshold) | Threshold raised or join made robust |
| X12 | Can the guest's backpack be read from and written into the host's inventory system for a second character (D7)? | Items round-trip: guest leaves, host saves and reloads, guest rejoins with the same items |

| X13 | Does `PDP_MainCharacter_C` have a third-person body other players can see, or do remote players need our own mesh (Djecka's placeholder in `assets/player_model`)? | Host sees the guest's body animate while walking, crouching, sprinting |

#### M1 results so far (details in `NOTES.md`)

| Spike | Verdict |
|---|---|
| X1 | Lua LoadMap hooks fire for every map change, but the FURL is opaque to Lua, so `listen` cannot be added there. Native travel drops the listen server and the guest. **Change:** the C++ layer detours `UEngine::LoadMap` and appends `listen` (M2). Until then, re-host via `servertravel <map>?listen` (~10 s) plus guest auto-rejoin. The guest drops on every non-seamless map change either way, so auto-rejoin is required |
| X1b | **Solved in C++:** the native layer swaps the engine's `LoadMap` vtable entry and appends `listen` when the host was listening (`PTNative_SetKeepListen`). `travel` 23/23, no second load. The guest still drops on native travel (ClientTravel cannot make it follow) and rejoins in ~8 s |
| X13 | **The body exists:** remote players have a full replicated, animated ALS Mannequin body, drawn with the invisible material `M_PlayerCharacter_Invist`. A visible material on the other player's `CharacterMesh0` (each side, never your own) shows it walking, crouching, sprinting. Djecka's model is optional polish; find a good-looking cooked material |
| X9 | Our C++ mod built against RE-UE4SS 8333063 loads in the official release of that commit. Ship the official UE4SS zip |
| X10 | Real risk: the game's autosave wrote the host's world into the guest's own save. A Lua pre-hook on `BaseSaveGameManager:SaveGame` setting the slot to -1 blocks it. M2 adds that plus guards for the other writers; a native write guard under `Saved/SaveGames` for a hard guarantee. Never change guest settings in place (`GameUserSettings.ini` is rewritten on every map load) |
| X11 | Solved: the 20 s limit is `IpNetDriver.ResolutionConnectionTimeout`. Set it on the CDO from Lua before `open` |
| X3 | Duplicates are wider than the car: every car part, garage stations and storage, quest actors and zone lootables exist separately on the guest. Gate them in M3/M4; stable ids (X2) must cover lootables and storage. Redo the zone survey once the guest has a character (relevancy hid the host's actors) |
| X2 | **Partly free ids.** Loaded actors keep the same path on both sides (skip pending-kill ones); spawned actors, garage storage and zone loot do not (zone loot is a separate random pick per side), so M4 ids = path for loaded, class + spot + ordinal for spawned. Host replication shows and removes host actors on the guest but does not sync state. Only "open container" was seen on the game's own path; take and pickup were host calls, the loot-UI take path is unknown. `docs/spikes/X2.md` |
| X4 | **Guest interaction works locally only**: highlight, container menu and pickup run through the game's code on the guest's own copies; nothing reaches the host. Running an interaction on the host "as the guest" lands the result on the host player, so M4 = guest-local interaction, hooked effect points send intents. Zone loot blocked by X2 duplicates. `docs/spikes/X4.md` |
| X5 | **Passes.** A ws2_32 `sendto`/`recvfrom` import-table hook moves UE's traffic onto our link; listen, travel, zonejoin pass through a loopback tunnel, listen and travel also at 150 ms + 2 % loss (tunnel emulation; shipping UE has no NetEmulation). Keep the transport plan. `docs/spikes/X5.md` |
| X6 | **Groundwork, one account**: the game's own Steam session (appid 1458140) gives lobby, rich presence, relay and Messages with no init of our own. The first unreliable send after a reliable one can stall the game thread 1-6 s, so M6 sends off the `sendto` path. Two-account test not run yet (`docs/spikes/X6.md`) |
| X7 | **Plan ready**: kinematic car on the guest with motion-time Hermite interpolation, adaptive delay 100-250 ms; same-time error about 43-55 / 80 / 103 uu at 0 / 100 / 150 ms lag. The guest destroys its own car copy on arrival. `docs/spikes/X7.md` |
| X8 | **Seat found, the guest must hold it**: the guest sits on the mirrored driver seat; the host's attach replicates but the pawn is sometimes thrown kilometres away, so a guest-side seat guard re-places it (cause unknown). ARC (Gobbler + screen) moved between the seats, both seats clear; overlap with the gear shifter and car computer unchecked. `docs/spikes/X8.md` |
| X12 | **Yes**: the guest's backpack round-trips as a one-line record (items, counts, grid, rotation, durability, hand, quick slots) through leave/rejoin and a host reload from a side file; the game's `.sav` is untouched. Destroy guest characters before a host LoadGame (else crash 0x20). `docs/spikes/X12.md` |
| Lane E | Research for D13/D16/D17/D19/D21: Tourist freeze via a `CreepCheck` hook works; Fabrication = host `Craft Recipe Asset`, guest craft blockable; gateway summon = host `Select Exit Portal Actor`; ARC map marker registers (not seen drawn); Sentry dormant, CrashReportClient is the uploader. `docs/spikes/E.md`, `docs/research/` |

### M2 Session core (M)

S1, S3-S7, P1, P7, Q9: event-driven join (game mode login hooks, no polling), spawn and possess, travel keeps the session,
rejoin, handshake, guest saves blocked, name tags, game crash upload off, mod inert outside sessions. **Release 0.1.0** (direct IP, internal).

Progress (2026-10-20, lanes F1 and F2 merged; details in `docs/spikes/M2-session.md`, `docs/spikes/M2-safety.md`):

| Id | State |
|---|---|
| S1 | Implemented, tested: auto-listen on every gameplay map (`session`). The Steam lobby part is M6 |
| S3 | Implemented, tested via `PT_JOIN` (`session`, `sessionrejoin`); `join.txt`: its path rule checked against the live source path (`@C:/.../ue4ss/Mods/<mod>/Scripts/x.lua`) and the installer dry run, no two-client run |
| S4 | Implemented, tested: accept, mismatch refusal, no-hello refusal (`session`, `sessionmismatch`, mutations `match`, `hello2`). DLC report not done |
| S5 | Implemented, tested: polite drop 6 cycles (`sessionrejoin`); killed guest process in the garage (`sessionabrupt` 25/25) and in a zone (`sessionabruptzone` 26/26): host stays up, guest's controller and character gone, relaunched guest rejoins; mutation `nokill` fails. Moving car untested |
| S6 | Implemented, tested: run start (`TravelToNextLeg`), gateway return, death return, run failure, save and quit mid-run + resume, each with the guest back by itself (`sessiontravel` 55/55, mutation `nokeep` fails); `UserNewGame`/`QuitToMenu` (`session`) |
| S7 | Implemented, tested: `safety`, `guestsave`, plus `safetysaves` 28/28 (DbgActEvt save graph events, checkpoint, bookmark, `Rinse`, run-failure and save-and-quit branches of `TravelToGarage` as a guest), mutation `nosession` fails. Story and station saves not exercised |
| P1 | Implemented, tested (`session`, `body`, `sessionlook`) |
| P7 | Implemented, tested (`nametag`); shows the PlayerState name until Steam (M6); fade checks have no failing mutation |
| Q7 | Implemented, tested (`sessionsolo`, `safety_solo`) |
| Q9 | Implemented: own crash marker, no CrashReportClient start, Sentry DSN cleared, `sentry_init` refused (`safety_crash`, `safety_solo`). The D23 firewall crash run is ready (`tools/q9-firewall.ps1`, scenario `crashfw`, dry run checked) and needs the owner's elevated run |
| G5 | Implemented, tested with a guest (`safety`); not isolated from the game's own multiplayer behaviour, real menu path untested |

### Prototype day (2026-10-21): first pass of M3-M5 for playtesters

Lanes merged into main and checked together there: `carsync` 35/36 and 36/36 (C1-C4, C7), `lootsync` 34/34 (W1, W2, C6, G1),
`worldsync` 27/27 (W3, W4, W6 partly, G3), `playerhealth` 26/26 (P4, D6 without the bag), `carenter` 21/21, smoke set and
`sessiontravel` all pass. Dev zip `PacificTogether-0.0.4-dev-965154f`. Gaps are in the lanes' spike docs and `NOTES.md`; not done:
P5, C5, C9, W7, W8, W11, item durability, wreck scrap, the guest's death bag.

### M3 Car (M-L)

C1-C7: door interaction for both, passenger seat, interpolated car on the guest, visible state, shared health and
resources, repairs and refuel by intents, shared trunk. **Release 0.2.0.**

### M4 World and loot (L)

W1-W2, P2-P5, G1: stable ids, intent channel, container/pickup/scrap/anchor intents, duplicate suppression, guest
backpack and its persistence in the host's save, guest damage and death. **Release 0.3.0.**

### M5 Run lifecycle and anomalies (L)

W3-W6, W11, G3, G5, G6: routes, gateway summon and ARC energy for both players, conditions, storm and gateway, exit warp, run failure, the listed anomalies, story bystander
safety, co-op settings. **Release 0.4.0.**

### M6 Steam (M)

S2: tunnel over Steam messages, lobby, invite, join from friends list, rich presence, keep-alive and disconnect
detection. **Release 0.5.0.**

### M7 Hardening and 1.0 (M)

Q2-Q6: lag/loss runs, soak test, crash triage, install docs, playtests with the owner and friends. **Release 1.0.0.**

Rough total to 1.0: 3-4 months part-time. Guess, revisit after M1.

### After 1.0

P1 items: guest driving (C8), guest garage stations (G2), ARC map marker (P8), Tourists watched by any player (W7), guest route planning (D22), story audio for the guest, all anomalies, Whispers in the Woods,
DLC-less guests (W10), Expeditions, in-game host/join menu.

## 6. How we work

- Two developers, each with Claude. One milestone at a time; inside a milestone, parallel lanes per subsystem
  (see `coop-anything/playbook/multi-agent-workflows.md`), each lane owning its own files.
- Branches: `main` always passes the test suite. Work on `feat/<area>-<topic>`, `spike/<id>`, `research/<topic>`,
  `test/<topic>` or `fix/<topic>`, merge via PR reviewed by the other developer. Open work for contributors, by cost:
  `docs/TASKS.md`.
- Commits: imperative summary, optional scope prefix (`car: interpolate client transform`).
- Every PR touching gameplay names the test scenario that covers it and pastes its summary.
- `NOTES.md`: observations / derived / guesses / unknowns, with sources, written as you go.
- Releases: see `docs/RELEASING.md`.

## 7. Open questions

None open. Owner answers from 2026-10-19 are recorded as D6-D10.
