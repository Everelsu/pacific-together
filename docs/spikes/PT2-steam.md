# PT2 Steam join (M6, S1, S2, D14), lane pt2-steam

> Historical research; see the [index](README.md) for current implementation and later evidence.

October 23 follow-up: UE traffic and the running-game invite/join callback succeeded between two real accounts; see [../../NOTES.md](../../NOTES.md). Cold-start invites and vanished-host handling remain separate checks.

Goal: players join through Steam instead of typing an IP. Groundwork: `docs/spikes/X6.md`.

## What is built

- `mod/PacificTogether/Scripts/steam.lua` (new, loaded before `session`):
  - Host: when the world listens (`netMode()=="listen"`, which auto-listen gives every save), a friends-only lobby (2 members) is
    created. Lobby data `pt_version`, `pt_protocol`, `pt_port` (from `-port=` or 7777), `pt_host`; rich presence `status` and
    `connect` = `+connect_lobby <id>`. The tunnel link goes to Steam (`PTNative_TunnelSteam(0)`). Channel 1 answers the guests'
    warm-up pings (reliable ping gets reliable echo, `ping-u` gets an unreliable echo). The host's own player is named after the
    Steam persona (`ChangeName`). The lobby is dropped after 30 s without listening (menu), not on every map load.
  - Guest: a join request is a lobby id from (a) the process command line (`+connect_lobby N`, Steam starts the game with it),
    (b) the callbacks `GameLobbyJoinRequested_t` (333, invite accepted while running) / `GameRichPresenceJoinRequested_t` (337,
    Join game while running), registered by the native layer on the game's own Steam, (c) tests: a file named by `PT_STEAM_INBOX`.
    It joins the lobby, checks `pt_version`, maps the lobby owner as `10.77.0.1` in the tunnel, warms the Steam session
    (reliable and unreliable ping, so the 1-6 s first-send stall of X6 happens here and not in UE's `sendto`), then calls
    `session.setJoin("10.77.0.1:<pt_port>")`: from there an ordinary guest (hello, rejoin after host map loads, ...).
  - Off when `PT_MUTATE=nosteamjoin`, `PT_STEAM=0`, and in every test run (`PT_SCENARIO` set) unless `PT_STEAM=1`.
- `session.lua`: exports a table (`join`, `wanted`, `setJoin`, `guestInfo`); a game started by Steam is a guest (no auto-listen)
  while the lobby is entered; the hello carries `sid=<SteamID> name=<percent-encoded persona>`; the host names the guest by the
  persona and remembers `{login, sid}`. Direct IP (`PT_JOIN`, `join.txt`) is untouched: with an IP set steam.lua never hosts or joins.
- `backpack.lua`: the guest key is the SteamID when the hello had one, else the login name as before. The old key (login name)
  is read as a fallback the first time (`PT|bp host adopts the old backpack of X for Y`), the old file stays.
- Native (`steam.cpp`, `dllmain.cpp`): `PTNative_CommandLine`, `PTNative_SteamPersona`, `PTNative_SteamEvent` (queue filled by
  callbacks 333/337/504 through `SteamAPI_RegisterCallback`, registered on `PTNative_SteamEnable(true)`),
  `PTNative_SteamEventStats`, `PTNative_SteamRichPresence(key)` reads our own value without setting.
- Tests: scenario `steamsession` (-Clients 2), runner list `$SteamMod` in `tools/run-test.ps1`.

## Observations (local	est-results)

- `20261022-100403-pt2-steam-steamsession`: 31/31 (host and guest processes, one account, tunnel over loopback UDP).
- Mutation `20261022-094331-pt2-steam-steamsession-nosteamjoin`: 12/31 (steam.lua does nothing: no lobby, no join).
- `20261022-083618-...steamsession` (real Steam link, no UDP): lobby on load, lobby data, rich presence, callback, lobby join from the
  connect string and the tunnel peer mapping all PASS (22/31); everything after the warm-up fails: **two processes of one account
  cannot message each other** (guest pings on channel 1 got no echo in 20 s, UE never connected). A second process of the same
  account can join the first one's lobby and sees it as owner.
- `SteamAPI_RegisterCallback` on the game's Steam works: the host's own `LobbyEnter_t` (504) arrives in the queue
  (`steam_callback_delivered`), so 333/337 (invite, Join game while running) are registered the same way; no crash.
- Earlier run 27/31 and 28/31 found two bugs: `steam and steam.identity()` truncated the persona (multi-value `and`), and the test mod
  sent its own hello without `sid` before the mod's (main.lua skips its hello for `steamsession`).
- The default guest login name is `<PCNAME>-<4 hex>` and changes every launch, so the pre-Steam backpack key was never stable;
  the SteamID key is.

## Derived

- Steam join mechanics (lobby on listen, connect string parse, lobby join, tunnel peer, hello with sid/persona, names, SteamID key)
  are proven with one account; the only swapped part in the test is the tunnel's link (loopback UDP, `PT_STEAM_UDP`).
- Unproven on this PC: Steam messages carrying UE traffic between two accounts, the friends-list lookup, Steam delivering Join game /
  invite (command line, callbacks 333/337), warm-up pings and echoes between real peers, the old-key backpack adoption
  (`PT|bp host adopts ...`; the login name is random per launch, so the test cannot pre-seed it), the 1-6 s first-send stall.
  Steps: `docs/spikes/X6.md` "Human two-account test".

## Guesses / Unknowns

- Callback struct layouts (`GameLobbyJoinRequested_t` 16 bytes, `GameRichPresenceJoinRequested_t` 264 bytes) and the vtable order of
  the hand-written `CCallbackBase` are right for 504 (delivered); 333/337 share the same code path.
- Steam may start the real install, not the test copy, on "Join game" (X6); then only the callback/command line path of the
  real mod counts.
- The mod does not detect a vanished host over Steam (X6 unknown stays); a join to a lobby whose host is in a very different
  state just times out through the normal guest retry.
- Not done: sending off the game thread (the warm-up pings take the first-send stall in Lua instead), a friendly overlay line for a
  version mismatch (it is only logged), `docs/PLAN.md` M6 status rows (for the lead).
