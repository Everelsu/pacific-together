# Crash reports (D16, Q9)

> Historical research; see the [index](README.md) for current implementation and later evidence.

2026-10-19, lane E. How the game sends crash reports and how the mod can turn uploads off without touching game
files. Sources: the copy's install files (read only), `DefaultEngine.ini` / `BaseEngine.ini` from `pakchunk0`, the
CrashReportClient's own pak, Sentry UHT headers, crash folders from earlier runs in `local/test-results`, scenario
`crashcfg` (`test/PacificTogetherTest/Scripts/scenarios/crashcfg.lua`). Endpoint keys and IDs are left out on purpose.

## Observations

### Two reporters are shipped

- **Unreal CrashReportClient (CRC).** `Engine/Binaries/Win64/CrashReportClient.exe` plus
  `Engine/Programs/CrashReportClient/Content/Paks/CrashReportClient.pak`; `DefaultGame.ini` has
  `IncludeCrashReporter=True`. The CRC's own `DefaultEngine.ini` (in its pak): `[CrashReportClient]
  DataRouterUrl="https://<host>/api/<project>/unreal/<key>/"` where `<host>` is an `ingest.sentry.io` host, i.e. the
  CRC uploads to Sentry's Unreal endpoint; also `bAllowToBeContacted=true`, `bSendLogFile=true`,
  `CanSendWhenUIFailedToInitialize=true`, `UIInitRetryCount=10`.
- **Sentry plugin** (`PenDriverPro/Plugins/Sentry`, `sentry.dll` contains `0.5.0` and `sentry.native.unreal`,
  `crashpad_handler.exe`). `USentrySubsystem : UGameInstanceSubsystem` with `Initialize`, `InitializeWithSettings`,
  `Close`, `Capture*`; `USentrySettings` (config `Engine`): `DsnUrl`, `Release`, `InitAutomatically`,
  `AutomaticBreadcrumbs`, `UploadSymbolsAutomatically`, `PropertiesFilePath`. The game's `DefaultEngine.ini` sets only
  `[/Script/Sentry.SentrySettings] DsnUrl=...` (an `ingest.sentry.io` DSN).
- Also present, not crash related: `[Analytics] ProviderModuleName=GameAnalytics`, `IWAnalytics` settings, user
  setting `bEnableAnalytics` in `DrivingGameUserSettings`.

### At runtime (scenario `crashcfg`, one game, main menu, headless)

- `20261019-202841-laneE-crashcfg` (7/7, no override): `Default__SentrySettings`: `InitAutomatically=false`,
  `DsnUrl` length 74, `Release=""`, `UploadSymbolsAutomatically=false`; one `SentrySubsystem` on the game instance.
  `SentrySubsystem:Close()` from Lua: no error, nothing visible changed.
- No `crashpad_handler.exe` process at any 5 s sample during that 85 s run, and none in a process listing taken while
  seven other lanes' test games were running (garage and zone runs). No `CrashReportClient.exe` process while games
  run; it only appears after a crash (the runner closes it, `docs/TESTING.md`).
- At every start the game writes `Saved/Config/CrashReportClient/UE4CC-Windows-<ExecutionGuid>/CrashReportClient.ini`
  holding its `[CrashReportClient]` config section (default: `bHideLogFilesOption=false`,
  `bIsAllowedToCloseWithoutSending=true`, `CrashConfigPurgeDays=2`, the `BaseEngine.ini` values). Crash folders from
  earlier runs (e.g. `20261019-172056-guestsave-noblock/crash-host-UE4CC-Windows-.../`) hold the same
  `CrashReportClient.ini` next to `CrashContext.runtime-xml` and the minidump.
- `20261019-203554-laneE-crashcfg` (7/7, `PT_SENTRY_EXPECT=off`): lines appended to the copy's user config
  `PenDriverPro/Saved/Config/WindowsNoEditor/Engine.ini`:
  `[/Script/Sentry.SentrySettings] InitAutomatically=False DsnUrl=` and `[CrashReportClient] DataRouterUrl=
  bAgreeToCrashUpload=false bSendUnattendedBugReports=false bImplicitSend=false PTMarker=laneE`. Result: Sentry
  `DsnUrl` length 0, and the new per-execution `CrashReportClient.ini` starts with all five of our keys followed by
  the defaults. File restored afterwards (byte size 2048 before and after).
- `20261019-204153-laneE-crashcfg` (6/7, same expectation, no override): `sentry_settings_loaded` FAILs (DSN length
  74), the per-execution file has only the three defaults.
- `CrashContext.runtime-xml` of a crash carries `UserName`, `LoginId`, `EpicAccountId`, `MachineId`, the command line
  and a call stack.

## Derived

- Sentry-native is not running: `InitAutomatically` is false and no crashpad handler starts, so the plugin captures
  nothing unless game code calls `Initialize` (not seen). Its upload path is dormant; a runtime `Close()` is harmless
  insurance.
- The live upload path is the CRC: on a crash the game starts `CrashReportClient.exe`, which posts to Sentry's Unreal
  endpoint, with the user's "Send" click, or on its own if its UI fails to start (`CanSendWhenUIFailedToInitialize`).
- The game forwards its own `[CrashReportClient]` section into the per-crash config the CRC reads. So a mod can set
  CRC keys without touching game files: either in the user `Engine.ini` (persistent, survives uninstall unless removed),
  or, better for "only while installed", by rewriting this run's
  `Saved/Config/CrashReportClient/UE4CC-Windows-<guid>/CrashReportClient.ini` after start-up (a file the game
  regenerates every run and purges after 2 days). Candidate content: `DataRouterUrl=` (no upload target) and
  `bAgreeToCrashUpload=false`.
- Own crash log for our issues: the crash folder the engine already writes (`Saved/Crashes/UE4CC-Windows-*`: minidump,
  `CrashContext.runtime-xml`, log) is enough raw material; the mod copies it next to its log on the next start, or the
  C++ layer adds a vectored exception handler that appends the mod state. Strip identity fields before sharing.
- For our own test runs the same risk applies today: a test crash shows the CRC with the official upload URL.

## Guesses

- The CRC applies the crash folder's `CrashReportClient.ini` over its built-in config (that is why the game writes it),
  so `DataRouterUrl=` there leaves it nothing to upload to. Not observed: proving it needs a real crash.
- If game code ever calls `USentrySubsystem::Initialize`, the empty `DsnUrl` override would disable it as well.

## Unknowns

- Whether the CRC honours `DataRouterUrl`/`bAgreeToCrashUpload` from the forwarded file, and which key wins over its
  pak config. Safe check: a deliberate crash in a test copy with outbound traffic to `*.sentry.io` blocked (needs the
  owner's OK for a firewall rule), then read the CRC log in its Saved folder.
- Whether the game copies the per-execution file into the crash folder at crash time (then rewriting it at runtime
  works) or regenerates it from GConfig (then only the user `Engine.ini` route works).
- Non-headless runs, loaded saves and gameplay maps were not checked for a late Sentry start (processes only sampled).

Verdict: Sentry is dormant (InitAutomatically=false, no crashpad); the real uploader is the CrashReportClient, and
the game forwards our `[CrashReportClient]` override from user config into the CRC's per-crash config (tested);
whether the CRC obeys it needs one crash with Sentry's hosts blocked.
