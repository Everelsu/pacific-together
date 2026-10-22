# PT2 Steam join (M6, S1, S2, D14), lane pt2-steam

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

## Observations / Derived / Guesses / Unknowns

Filled from the runs below.
