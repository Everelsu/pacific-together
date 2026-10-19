# Networking research: how others did it, what to build

Research run 2026-10-19 (web + playbook + read-only look at the game's `steam_api64.dll`).
**(unverified)** = claim from summaries, engine knowledge or a single weak source. "Unknown" = searched, found nothing.

## 0. Local finding: Steam is already in the game process

- `<game dir>/PenDriverPro/Binaries/Win64/steam_api64.dll` (298,856 bytes) exports the flat API:
  `SteamAPI_SteamNetworkingMessages_SteamAPI_v002`, `SteamNetworkingSockets_SteamAPI_v012`,
  `SteamNetworkingUtils_SteamAPI_v004`, `SteamMatchmaking_v009`, `SteamFriends_v017`, `SteamUser_v022`, `SteamUtils_v010`,
  `ISteamNetworkingMessages_SendMessageToUser/ReceiveMessagesOnChannel/AcceptSessionWithUser`,
  `ISteamMatchmaking_CreateLobby/GetNumLobbyMembers`, `ISteamFriends_SetRichPresence/ActivateGameOverlayInviteDialog`,
  `ISteamUtils_IsAPICallCompleted/GetAPICallResult`, `SteamAPI_ManualDispatch_*`. No `SteamAPI_InitFlat` (older SDK).
- The shipping exe imports `SteamAPI_Init`, `RestartAppIfNecessary`, `RunCallbacks`, `RegisterCallback`, `Shutdown`, `SteamUser022`.
- Derived: the game inits Steam itself under appid 1458140 and dispatches callbacks with `RunCallbacks`. A mod DLL in
  the process can call the interface getters directly. It must NOT call `ManualDispatch_Init` (changes the
  process-wide callback mode). Use the game's appid, not Spacewar 480.

## 1. How existing UE co-op mods did it

| Project | UE | Replication | Transport | Hook layer | Travel / spawning | Source |
|---|---|---|---|---|---|---|
| Multivoid (Voices of the Void) | 4.27 | own state sync | GameNetworkingSockets, Rust master server + TURN, direct IP | DLL loaded by UE4SS but imports nothing from it; own sig scan, MinHook on ProcessEvent, BP VM loop, `AActor::EndPlay` | puppet = real player class driven by interpolated pose stream; join = host serializes world, client loads it from a hidden save slot; clients never save | MIT, [repo](https://github.com/VOTV-MP/Multivoid), [architecture](https://raw.githubusercontent.com/VOTV-MP/Multivoid/HEAD/docs/architecture.md) |
| HSMMod (Half Sword) | 5 | own sync | ISteamNetworkingMessages v002 + lobbies through the game's own steam_api64.dll under the game's appid; ENet fallback | `dwmapi.dll` proxy, MinHook ProcessEvent, RVAs keyed by PE timestamp, startup self-test | hooks `OpenLevel`; host drives travel, clients send Ready (20 s); puppets via deferred spawn + brainless AIController; 60 Hz input / 30 Hz snapshots | no license (read only), [repo](https://github.com/Dudiebug/halfsword-multiplayer-mod) |
| SifuCoop | 4 | own sync | raw UDP, STUN + hole punch, HMAC packets, retransmitted one-shot events | `dsound.dll` proxy, MinHook, PDB addresses | host sends `LevelSync`; puppet = clone of player class, eased to snapshots | license ambiguous, [repo](https://github.com/Zanci19/SifuCoop) |
| CrabSync (Crab Champions) | 5 | game's own replication (game already online) | none; hello rides stock `ClientMessage` RPC | `xinput1_3.dll` proxy, MinHook, Dumper-7 SDK | host "team ledger" diffs inventories ~10 Hz, writes back through the game's own functions | MIT, [README](https://github.com/Dudiebug/CrabMods/blob/main/crabsync/README.md) |
| WukongMP | 5 | custom client + relay server | unknown | .NET injected | unknown | [sdk](https://github.com/readycodeio/wukongmp-sdk) |
| HogWarp | 4 | custom dedicated server (inferred) | unknown | unknown | unknown | [HogWarp.Core](https://github.com/HogWarpMP/HogWarp.Core) |
| Ember Wave (Lies of P) | 4 | unknown | Steam networking, invites | own loader | shared progression, save sync | closed source |

Lessons:
1. Every mature project for a game without netcode built its own state sync and transport.
2. Only CrabSync used UE replication, because that game already replicated.
3. No project found injects a NetDriver or adds replication to a cooked game at runtime.
4. HSMMod is the precedent for "flat Steam API from the game's own DLL under the game's own appid".
5. Multivoid is the closest sibling (UE 4.27, UE4SS-loaded DLL with no UE4SS ABI dependency). Copy its intent
   pattern (client names an intent, host performs it and broadcasts state) and its "load the host's world into a
   hidden save slot" join path.

## 2. UE4SS C++ mods

- Build (RE-UE4SS README): MSVC C++23 (toolset >= 14.43, VS >= 17.13), Rust >= 1.73, CMake >= 3.22, Ninja or VS
  generator, a GitHub account linked to Epic for the `deps/first/Unreal` submodule. CMake was added next to xmake
  (PR #1067); xmake may be deprecated. [README](https://raw.githubusercontent.com/UE4SS-RE/RE-UE4SS/main/README.md)
- Mod: `MyMods/` CMake root with `add_subdirectory(RE-UE4SS)`, SHARED lib linked to `UE4SS`, config
  `Game__Shipping__Win64`, exports `start_mod()`/`uninstall_mod()`, installs to `Mods/<Name>/dlls/main.dll`.
  [guide](https://docs.ue4ss.com/dev/guides/creating-a-c++-mod.html), [template](https://github.com/UE4SS-RE/UE4SSCPPTemplate).
- ABI: C++ mods must be rebuilt per UE4SS version. Pin the exact UE4SS commit, or go Multivoid-style with zero UE4SS imports.
- API: `CppUserModBase` (`on_update`, `on_unreal_init`, `on_lua_start`). Hook API names in the Epic-gated headers: unverified.
  Lua has `RegisterHook`, `RegisterLoadMapPreHook/PostHook` (with FURL), deferred spawn. [Lua API](https://docs.ue4ss.com/dev/lua-api.html)
- Stability on 4.27: Astroneer `UnregisterHook` crash fixed Dec 2025 ([#1123](https://github.com/UE4SS-RE/RE-UE4SS/issues/1123));
  workarounds `bUseUObjectArrayCache=false`, `GraphicsAPI=dx11`. Engine calls only on the game thread.
- Runtime property/RPC replication (flipping `CPF_Net`, adding `FUNC_Net`): no precedent, unproven. Do not depend on it.
- Actor-level replication is cheap: `SetReplicates(true)` / `SetReplicateMovement(true)` are BlueprintCallable; on the
  host they should make a spawned cooked-BP actor appear on clients (engine knowledge, unverified on this build).

## 3. UE netcode over Steam

| Option | How | Pros | Cons |
|---|---|---|---|
| a1 custom UNetDriver | port SteamSocketsNetDriver | cleanest in theory | needs engine class layouts, vtables, runtime UClass registration; no precedent; highest risk |
| **a2 in-process socket hook** | MinHook `ws2_32!sendto/recvfrom` for the game's UDP socket, fake IPv4 per peer (`10.77.x.y`) mapped to a SteamID, UE packets as unreliable `SendMessageToUser`, drain `ReceiveMessagesOnChannel` inside hooked `recvfrom`; client `open 10.77.0.1:7777` | keeps the proven listen server; a few hundred lines; uses the game's Steam session | hot-path hook; must not break UE's stateless handshake; packet size vs relay MTU unverified; Messages API has no close notification, needs keep-alive |
| a3 local UDP proxy | separate process relays 127.0.0.1 over Steam (HXCoop pattern) | zero game hooks | second process running SteamAPI under 1458140 (unverified clean), extra hop |
| b own state sync only | Multivoid/HSMMod style | full control | throws away working CharacterMovement prediction, possession, attachment; largest scope |
| c VPN | Tailscale/ZeroTier/Radmin + `open <ip>` | zero code | every friend configures it; fine as first internet test and fallback |
| d Spacewar 480 | separate init under 480 | samples exist | conflicts with the game already initialised as 1458140; crowded lobbies |

Steam facts:
- Messaging a host implicitly accepts its incoming session; otherwise `AcceptSessionWithUser` on SessionRequest (1251).
  No close notification. ([ISteamNetworkingMessages](https://partner.steamgames.com/doc/api/ISteamNetworkingMessages))
- SDR relay for P2P needs no listed setup ([SDR docs](https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay)).
  Whether relay + lobbies work for an appid whose developer set nothing up: unknown. HSMMod relies on it (unverified).
- Callbacks: the game uses `RunCallbacks`; hook it or poll `IsAPICallCompleted/GetAPICallResult` for async results.
  Broadcast callbacks need `RegisterCallback` with a hand-built `CCallbackBase` vtable: `GameLobbyJoinRequested` 333,
  `GameRichPresenceJoinRequested` 337, `LobbyChatUpdate` 506, SessionRequest 1251.
- Invites: rich presence `connect`, overlay invite dialog, `+connect_lobby <id>` on cold launch. A cold launch starts
  the real install through Steam, so the mod must be installed there (not only in test copies).

## 4. Keeping the listen server across native travel

The game travels via `UBaseRouteState::TravelTo` -> native `Browse` without `?listen`; no UFunction hook fires.
Options, cheapest first:
1. `RegisterLoadMapPreHook` on the host: add `listen` to `FURL` before LoadMap. **Tried in spike X1: the hook fires,
   but UE4SS passes the FURL to Lua as an opaque userdata with no fields, so Lua cannot change it.** The same idea
   from C++ (detour `UEngine::LoadMap`, append `listen` to the FURL's Op) is the M2 plan.
2. Turn native travel into `ServerTravel` (cancel in a pre-hook, issue `servertravel <map>?listen`); clients follow
   (exp13 showed it). Needs a recursion guard and a check that `UBaseLevelManager` run state survives.
3. Seamless travel (`bUseSeamlessTravel` + TransitionMap): keeps connections, most invasive. Defer.

20 s pending-connect threshold: **solved in spike X11**: it is `IpNetDriver.ResolutionConnectionTimeout` (default 20),
not `InitialConnectTimeout`/`ConnectionTimeout`. Set it on `Default__IpNetDriver` from Lua before `open`, or in
`Saved\Config\WindowsNoEditor\Engine.ini`.

## 5. Tooling

| Tool | Use |
|---|---|
| UE4SS Live View, dumpers | UHT headers, CXX SDK (`KeepMemoryLayout=1`), USMAP, Lua types ([docs](https://docs.ue4ss.com/feature-overview/dumpers.html)) |
| Dumper-7 | compilable SDK with offsets, for a UE4SS-independent DLL ([repo](https://github.com/encryqed/dumper-7)) |
| FModel / CUE4Parse | browse paks and BP assets (needs our USMAP) |
| UAssetAPI / UAssetGUI | raw Kismet bytecode of BP functions ([repo](https://github.com/atenfyr/UAssetAPI)) |
| KismetKompiler, kismet-analyzer | BP decompile / CFG; 4.27 support unconfirmed |
| Ghidra headless | find `UEngine::Browse/LoadMap`, `UWorld::Listen`, FSocketBSD via log strings |
| UEFind | locate GNames/GUObjectArray live ([repo](https://github.com/Fyyre/UEFind)) |

## 6. Recommendation (from this research)

Hybrid: UE replication carries bodies, our own channel carries game state.
- Hook layer: UE4SS Lua for fast iteration + one C++ DLL for what Lua cannot reach (socket hook, Steam, native travel).
- Players/pawns: stock UE replication. Car: host simulates, clients follow `ReplicatedMovement`; client driving later
  via inputs sent to the host. Host-spawned world actors: `SetReplicates`, clients suppress local duplicates.
- Game state with zero replication (inventory, parts, damage, run/route, quest flags): intent messages with stable ids;
  host performs via the game's own UFunctions and broadcasts state. Saves host only.
- Channel: stock-RPC hack first, then a dedicated reliable Steam messages channel next to tunnelled UE traffic.
- Transport: option a2, direct IP kept for tests and VPN users.
- Connect: friends-only lobby + rich presence + overlay invite; join via callback 333/337 or `+connect_lobby`.

### Risks ranked, with the cheapest experiment

1. Zero-replication game systems (where the 2024 attempt stalled): host `SetReplicates(true)` on one loot actor, assert
   it appears on the client and vanishes on pickup; diff full names of level-placed actors on both sides for free stable ids.
2. Native travel kills the session: `RegisterLoadMapPreHook` adds `listen`, assert listening after load with no second load.
3. Steam relay under 1458140 without dev setup: ~100-line DLL, friends-only lobby + `SendMessageToUser` echo between two
   real accounts (human step; mock DLL until then).
4. Socket-hook tunnel correctness: tunnel over localhost UDP first, rerun the suite, then with `PktLag=150 PktLoss=2`.
5. Car feel and client driving: `car` scenario with `PktLag=100`, log client position error per frame.
6. UE4SS C++ ABI/threading: hello-world mod against the pinned commit and a zero-import variant, 10 launches each.
7. 20 s connect timeout on long zone loads: Engine.ini setting, check `Threshold:` in the log.
