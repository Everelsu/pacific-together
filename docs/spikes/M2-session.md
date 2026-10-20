# M2 session core (lane F1)

2026-10-20. Shipping code: `mod/PacificTogether/Scripts/session.lua`, native additions in
`native/PacificTogetherNative/dllmain.cpp` (`PTNative_SetAutoListen`, `PTNative_GameBuild`, native version 0.0.3).
Tests: `test/PacificTogetherTest/Scripts/scenarios/session*.lua`; they drive the real mod (the guest's mod joins by
itself through `PT_JOIN`, set by the runner for `session`, `sessionlook`, `sessionprobe`, `sessionrejoin`).
All runs headless (`-nullrhi`) on lane `C:\PTLanes\laneF1`, port 7861, unless noted. Result folders are under
`local/test-results/`.

## What the mod does

- **Host (S1, D14, X1b):** at start the mod calls `PTNative_SetAutoListen(true)`: the native `LoadMap` detour appends
  `?listen` to every non-menu map the host loads itself (also the first one from the menu; never a client join, never
  `RB_MainMenu`). No `servertravel` re-host.
- **Join (S3, X11):** guest address from `PT_JOIN=<ip:port>`, else the first line of `mod/PacificTogether/join.txt`
  (git-ignored). The guest sets `IpNetDriver.ResolutionConnectionTimeout=120` on the CDO, runs `open <addr>` from the
  menu, retries after 130 s if no map loaded.
- **Handshake (S4):** in its `ClientSetHUD` hook the guest calls the stock reliable RPC
  `ServerChangeName("PT|hello mod=.. protocol=.. game=<ProjectVersion> build=<Steam build id>")`. The host reads it in a
  pre-hook, compares all four, and refuses a mismatch with `ClientWasKicked` + `ClientReturnToMainMenuWithTextReason`
  ("Pacific Together: mod mismatch: host has 0.0.1, you have ..."). A guest that sends no hello within 20 s of
  `GameModeBase:HandleStartingNewPlayer` is refused ("no handshake received"). After an accepted hello the host puts
  the login name back with `GameModeBase:ChangeName`.
- **Player (P1):** 100 ms after an accepted hello (outside the RPC hook) the host spawns a `PDP_MainCharacter_C`
  150 uu to the right of what it controls (character or car), possesses it with the guest's controller and sets
  `BP_MainCharacterManager_C.CharacterActor` back to its own character.
- **Bodies (X13):** each side gives every character that is not its own the cooked cloth material
  `/Game/Env/Generic/Props/Cloth/MI_GenManMade_Cloth_01` (found or `LoadAsset`, so also in zones), else
  `/Engine/EngineMaterials/WorldGridMaterial` (host: after each spawn; guest: on `ClientRestart` and 3 s later).
- **Travel (S6, reference crash):** pre-hooks on `BaseSaveGameManager` `UserNewGame`, `UserLoadGame`, `LoadGame`,
  `LoadFromCheckpoint`, `Rinse`, `LoadGameCmd`, `LoadBookmarkCmd`, `QuitToMenu` unpossess and destroy remote
  players' characters before the travel is queued; the `LoadMap` pre-hook does the same as a fallback.
- **Rejoin (S5):** the guest's mod runs `open` again whenever it lands in the menu while its session is active
  ("Host closed the connection" on every native travel). The session ends on the guest's own `QuitToMenu` or a refusal.
- **Leave:** a guest that disconnects is handled by the engine (`PawnLeavingGame` destroys its character).
- **Single player (Q7):** no guest = no hello, no spawn, no material change. The only difference is that the host's
  gameplay maps listen (D14).

## Observations

- Host crashes in every earlier run of this lane that had a guest (`20261019-193317`..`205800-laneF1-session`) and
  in the first runs today (`20261020-112113`, `112453`, `112730`, `113038` (windowed, so not `-nullrhi`), `113848`,
  `114234`, `114533-laneF1-sessionrejoin`): access violations in different places, all inside the engine:
  `FAnimUpdateRateManager::CleanupUpdateRateParametesRef` (game exe RVA `0x2C37E20`, reading past an array),
  its `GetUpdateRateParameters` (`0x2C4A350`, write AV), `FMallocBinned2::Malloc` (`0x125E4B0`, free-list pointer
  `0x3010000`), a package lookup during `ServerUpdateMultipleLevelsVisibility`, and a 60 s game-thread hang after a
  map load. Function names come from matching the disassembly (`dumpbin /disasm` on the test copy's exe) to UE 4.27
  source; no symbols.
- A native audit of `FAnimUpdateRateManager`'s global owner->tracker map (temporary, removed again) showed, after a
  guest left, an entry whose owner was no longer a live UObject with one dead component (`20261020-113848`), and a
  new guest character whose tracker listed 0 components right after its spawn (`20261020-114234`): the engine's own
  bookkeeping was overwritten.
- Solo diagnostic `sessionchurn` (no network: 15x spawn a second character, make it visible, destroy it):
  9/9, no crash (`20261020-111756-laneF1-sessionchurn-mat`).
- The same `sessionrejoin` run with only one line changed, the host no longer writing the hooked RPC's string
  parameter (`s:set(name)` in the `ServerChangeName` pre-hook): 36/36, six leave/rejoin cycles, audit clean every
  time (`20261020-114955-laneF1-sessionrejoin`). No run since crashed, except the nocleanup mutation, which is meant to.
- The previous agent's native `APlayerController::Destroyed` vtable patch (unpossess the leaving guest's character
  before the engine destroys it) crashed the host 0.1 s after the second leave (`20261020-112453`); removed.
- `RegisterHook("/Script/Engine.GameModeBase:K2_PostLogin")` never fired in any run (no Blueprint implements it);
  `HandleStartingNewPlayer` is used instead.
- UE4SS `UObject:IsValid()` is true for destroyed (PendingKill) actors until garbage collection; both mods now treat
  PendingKill as gone (`20261020-112113` crashed while the test called into a destroyed character).
- `ServerChangeName` from the guest before its `PlayerState` replicated: `PlayerState` was not valid in the
  `ClientSetHUD` hook, so a guest-side "send my name after the hello" left the hello as the name
  (`20261020-115907-laneF1-session`, `host_guest_named` FAIL); the host-side restore passes.
- Material: the character mesh's own default materials (`SkeletalMesh.Materials`) are `M_PlayerCharacter_Invist` as
  well. `sessionmats` (`20261020-133630-laneF1-sessionmats`) listed the loaded materials with person-like names: none
  for a body; cloth candidates `MI_GenManMade_Cloth_01/02`, `MI_PlayerCar_Fabric_*`, `MI_Vehicle_InteriorCloth_01`.
  Windowed `sessionlook` with `MI_GenManMade_Cloth_01` (`20261020-133829-laneF1-sessionlook`, both screenshots): a
  dark grey cloth mannequin on each side, standing and lit like the scene; it fits the game better than the grid.
  `LoadAsset` finds it in the forest map too (`20261020-134212-laneF1-session`, 6 `session body` lines with it).
- `session -Mutate nocleanup` (the host test re-adds a possessed remote character after the mod's cleanup, right before
  `UserNewGame`'s map load): host crash `EXCEPTION_ACCESS_VIOLATION reading address 0x20`
  (`20261020-131051-laneF1-session-nocleanup`), the same address as the reference's teardown crash.

## Results

| Scenario | Result folder | Result |
|---|---|---|
| session (S1, S3, S4 accept, S5, S6, P1, X13, cleanup, name) | `20261020-134212-laneF1-session` (also `120740`, `132658`) | 40/40 |
| sessionrejoin (S5: 6 drops + auto-rejoins) | `20261020-133523-laneF1-sessionrejoin` (also `121117`) | 36/36 |
| sessionsolo (Q7) | `20261020-134344-laneF1-sessionsolo` (also `122807`) | 13/13 |
| sessionmismatch (S4 refusal: bad hello, no hello) | `20261020-133237-laneF1-sessionmismatch` | 21/21 |
| sessionlook (X13, windowed, screenshots) | `20261020-133829-laneF1-sessionlook` | 15/15 |

`20261020-123221-laneF1-sessionmismatch` failed the no-hello refusal (19/21): the `K2_PostLogin` hook never fired;
fixed with `HandleStartingNewPlayer`.

Mutations (each must fail):

| Mutation | Breaks | Result folder | Result |
|---|---|---|---|
| session rename | the guest's name stays a hello | `20261020-123948-laneF1-session-rename` | FAIL `host_guest_named` |
| session nolisten | host auto-listen off | `20261020-130159-laneF1-session-nolisten` | FAIL every listen and join check |
| session kill | host test destroys the guest's character | `20261020-133047-laneF1-session-kill` | FAIL `host_sees_guest`, `client_sees_host` |
| session invisible | test puts the invisible material back | `20261020-130939-laneF1-session-invisible` | FAIL `host_sees_guest`, `client_sees_host` |
| session nocleanup | a remote character is still there at the map load | `20261020-131051-laneF1-session-nocleanup` | host crash, unreported checks |
| session leave | guest quits to the menu after the first join | `20261020-132320-laneF1-session-leave` | FAIL rejoin checks (no auto-rejoin after a deliberate quit) |
| sessionrejoin kick | the drop is a refusal, the guest's mod must not rejoin | `20261020-122638-laneF1-sessionrejoin-kick` | FAIL `host_guest_in_2..4`, `client_in_2..4` |
| sessionsolo spawn | a second character appears | `20261020-122949-laneF1-sessionsolo-spawn` | FAIL `solo_vanilla_new_game` |
| sessionmismatch match | the bad hello carries the right versions | `20261020-123543-laneF1-sessionmismatch-match` | FAIL both refusal checks on both sides (ran before the login-hook fix; the accepted hello gave a character) |

Diagnostics (no pass/fail meaning): `sessionchurn` (solo spawn/destroy), `sessionprobe` (which objects point at the
guest's character: only its own movement component, `20261020-113304-laneF1-sessionprobe`; the scan sees only each
class's own properties), `sessionmats` (material names).

## Derived

- Rewriting a string parameter of a hooked network RPC from UE4SS Lua (`RemoteUnrealParam:set`) corrupts the game's
  heap; the damage shows up later and elsewhere (anim update-rate map, allocator free lists). Never `:set` an FString
  parameter in a hook; read it and act afterwards.
- The pre-travel cleanup is required: without it the host crashes at the next map load (nocleanup mutation).
- With that removed, the stock engine paths are enough: a leaving guest's character is destroyed by
  `PawnLeavingGame` without a crash, and the Lua pre-travel cleanup is enough for native travel and `QuitToMenu`.
- `GameModeBase:HandleStartingNewPlayer` is a working event-driven login hook for the host (BlueprintNativeEvent).

## Guesses

- The crashes in M1 (`0x178`, X10) and the reference's teardown crash may have had other causes; not retested.
- Spawning inside the RPC hook may be fine now that the parameter is not written; the 100 ms deferral stays because
  it costs nothing.

## Unknowns

- How the cloth body looks in other zones and lighting, in the car and while carrying (one garage screenshot pair).
- The guest's name when it has no login name (falls back to "Guest").
- Lag/loss behaviour of the join and rejoin (Q2) and a guest joining while the host drives (M3).

## Verdicts

- S1 auto-listen on every gameplay map, including the first load from the menu and native travel: **works** (session).
- S3 direct IP join from `PT_JOIN`: **works** (session, sessionrejoin). `join.txt`: implemented, not tested.
- S4 handshake: accept, mismatch refusal with a clear message, and no-hello refusal **work** (session, sessionmismatch).
- S5 leave and rejoin without a host crash: **works** (sessionrejoin 6 cycles; session guest leave). Key fix: never
  write a hooked RPC's string parameter.
- S6 session survives `UserNewGame` and `QuitToMenu` + new game, guest rejoins by itself: **works** (session).
- P1 guest character next to the host, possessed, manager stays the host's: **works** (session).
- X13 other player's body visible on both sides, own body untouched: **works**, cooked `MI_GenManMade_Cloth_01`
  (session, sessionlook screenshots).
- Q7 single player unchanged apart from listening: **works** (sessionsolo).
- Native `Destroyed` patch: **dropped** (crashed the host).

## Shared files touched

- `tools/run-test.ps1`: `$Defaults` for `session`, `sessionmismatch`, `sessionsolo`, `sessionrejoin`; `$AutoJoin` list;
  sets `PT_JOIN=127.0.0.1:<port>` for the client of those scenarios and clears it afterwards.
- `test/PacificTogetherTest/Scripts/main.lua`: `inWorld` and `pcs` skip PendingKill objects.
- `.gitignore`: `mod/PacificTogether/join.txt`.
- `native/PacificTogetherNative/dllmain.cpp`: `PTNative_SetAutoListen`, `PTNative_GameBuild`, version 0.0.3.
