# Networking: design and research sources

Current local design reviewed for 0.0.7 (2026-10-24). External comparisons below are the October 19 research snapshot,
not a fresh upstream audit.

## Implemented design

- Stock UE 4.27 replication carries players and actor movement. The host owns world state, car simulation and saves.
- Lua gameplay modules send guest intents and host state through `net.lua` / native `msg.cpp`, using reliable
  ServerExecRPC and ClientMessage on the game connection. No runtime property/RPC-flag surgery is required.
- Protocol 3 paces host messages by reliable-bunch acknowledgements and holds bulky state until the guest pawn is ready.
- Native `transport.cpp` tunnels game UDP through Steam Networking Messages under the game's own appid **1458140**.
  Direct IP remains available. Do not initialize a second Steam session or switch the process to Spacewar/ManualDispatch.
- `steam.lua` creates a friends-only lobby and handles connect strings/invite callbacks. The October 23 playtest verified
  UE traffic between two real accounts; cold-launch and host-disappearance paths remain separate validation work.
- Native LoadMap patch keeps `listen` across travel. Non-seamless travel still drops the guest, which automatically rejoins.
  Lua's copied, opaque FURL cannot implement this patch. ResolutionConnectionTimeout controls the initial 20 s limit.
- The native mod links against pinned UE4SS 8333063. Setup is maintained in [../DEVELOPING.md](../DEVELOPING.md).

## Evidence and unresolved checks

| Question | Evidence |
|---|---|
| Actor replication vs gameplay state | [X2](../spikes/X2.md): copies appear/remove, but roll their own loot |
| Socket tunnel and lag/loss | [X5](../spikes/X5.md): listen/travel at 150 ms and 2% loss; not a current full gameplay suite |
| Steam API and first-send stall | [X6](../spikes/X6.md), [PT2-steam](../spikes/PT2-steam.md) |
| Two-account traffic, ready gate and overflow | [../../NOTES.md](../../NOTES.md) |
| Save/travel/rejoin protection | [M2-session](../spikes/M2-session.md), [M2-safety](../spikes/M2-safety.md) |

The initial unreliable Steam send can stall; warm-up moves that stall ahead of UE connection establishment.
Current lag/loss coverage, counter/tunnel hook coexistence, vanished-host behavior and long sessions still need evidence.
A separate Steam reliable gameplay channel, custom NetDriver and seamless travel were alternatives, not implemented claims.

## External precedents (October 19 snapshot)

| Project | UE | Replication | Transport | Hook layer | Travel / spawning | Source |
|---|---|---|---|---|---|---|
| Multivoid (Voices of the Void) | 4.27 | own state sync | GameNetworkingSockets, Rust master server + TURN, direct IP | DLL loaded by UE4SS but imports nothing from it; own sig scan, MinHook on ProcessEvent, BP VM loop, `AActor::EndPlay` | puppet = real player class driven by interpolated pose stream; join = host serializes world, client loads it from a hidden save slot; clients never save | MIT, [repo](https://github.com/VOTV-MP/Multivoid), [architecture](https://raw.githubusercontent.com/VOTV-MP/Multivoid/HEAD/docs/architecture.md) |
| HSMMod (Half Sword) | 5 | own sync | ISteamNetworkingMessages v002 + lobbies through the game's own steam_api64.dll under the game's appid; ENet fallback | `dwmapi.dll` proxy, MinHook ProcessEvent, RVAs keyed by PE timestamp, startup self-test | hooks `OpenLevel`; host drives travel, clients send Ready (20 s); puppets via deferred spawn + brainless AIController; 60 Hz input / 30 Hz snapshots | no license (read only), [repo](https://github.com/Dudiebug/halfsword-multiplayer-mod) |
| SifuCoop | 4 | own sync | raw UDP, STUN + hole punch, HMAC packets, retransmitted one-shot events | `dsound.dll` proxy, MinHook, PDB addresses | host sends `LevelSync`; puppet = clone of player class, eased to snapshots | license ambiguous, [repo](https://github.com/Zanci19/SifuCoop) |
| CrabSync (Crab Champions) | 5 | game's own replication (game already online) | none; hello rides stock `ClientMessage` RPC | `xinput1_3.dll` proxy, MinHook, Dumper-7 SDK | host "team ledger" diffs inventories ~10 Hz, writes back through the game's own functions | MIT, [README](https://github.com/Dudiebug/CrabMods/blob/main/crabsync/README.md) |
| WukongMP | 5 | custom client + relay server | unknown | .NET injected | unknown | [sdk](https://github.com/readycodeio/wukongmp-sdk) |
| HogWarp | 4 | custom dedicated server (inferred) | unknown | unknown | unknown | [HogWarp.Core](https://github.com/HogWarpMP/HogWarp.Core) |
| Ember Wave (Lies of P) | 4 | unknown | Steam networking, invites | own loader | shared progression, save sync | closed source |

These projects informed the host-intent/state pattern and use of the game's own Steam DLL. Their architecture does not
prove behavior in Pacific Drive; local experiments above are the implementation evidence. Unknown fields remain unknown.
