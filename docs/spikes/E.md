# Lane E: research for D13, D16, D17, D19, D21

2026-10-19. Details, sources and the Observations / Derived / Guesses / Unknowns lists are in the topic docs:
`docs/research/tourists.md`, `garage-stations.md`, `arc-device.md`, `arc-marker.md`, `crash-reports.md`.
Results: `local/test-results/<stamp>-laneE-<scenario>[-<mutation>]` (lane `C:\PTLanes\laneE`, port 7851, headless,
`main.dll` copied from the main checkout). Blueprint listings: `tools/kdis/` over files extracted with
`tools/pak/pak.py` into `local/research-extract/laneE/` (git-ignored).

## Checks that ran

| Scenario | Run | Result | Mutation run | Result |
|---|---|---|---|---|
| `tourist` (2 players, garage) | `20261019-200157-laneE-tourist` | 25/25 | `-noguestview` `20261019-200639` | 23/25, guest-view and frozen checks FAIL |
| | | | `-nohook` `20261019-201343` | 24/25, frozen check FAILs (moved 407 uu) |
| | | | `-nomarker` `20261019-201843` | 23/25, both marker checks FAIL |
| `stations` (1 game, garage) | `20261019-195300-laneE-stations` | 11/11 | `-noblock` `20261019-195504` | 10/11, block check FAILs |
| | | | `-noresources` `20261019-195638` | 8/11, craft checks FAIL |
| `arc` (1 game, Forest zone) | `20261019-202305-laneE-arc` | 9/9 | `-noselect` `20261019-202638` | 8/9, gateway check FAILs |
| `crashcfg` (1 game, menu) | `20261019-202841` (no override) 7/7; `20261019-203554` (user `Engine.ini` override) 7/7 | | `20261019-204153` (expect override, none present) | 6/7, settings check FAILs |

Earlier runs of the same scenarios that failed on probe bugs (call shapes, class loading): `20261019-193321`,
`-193938` (tourist), `-194245`, `-194747`, `-195056` (stations); described in the topic docs.

## Verdicts

- **D19 Tourists:** keep. "Observed" is `CreepCheck`: camera 0 within 2000 uu and dot > 0.3, no occlusion test. A
  host post-hook on `BP_Hazard_Landmine_C:CreepCheck` using the guest's PlayerCameraManager on the host freezes a
  Tourist while only the guest looks (tested). Activation range and creep target stay host-only unless
  `BP_HazardProperty_PlayerRange_C:DistanceToPlayer` is hooked too; guests cannot see Tourists until W6 replicates them.
- **D21 garage stations:** keep, after container sync. Fabrication = `"Craft Recipe Asset"` on the host (tested),
  Tinker = `CureCarQuirk` + `CurrencyAdjust`, Detailing = `UItemSlot::SwapSlotContents`; the guest's local craft is
  stopped by a pre-hook on native `ExecuteRecipe` (tested). Needs mirrored garage/car containers (M4).
- **D13 ARC:** keep for in-run actions. Gateway summon = `BP_StormManager_C."Select Exit Portal Actor"` on the host
  (tested); energy is the Gobbler item's `IP_Gobbler.CurrentCharge`; guest route planning touches native route state,
  suggest host-only planning for v1.0.
- **D17 ARC marker:** keep. A runtime `UMapIconComponent` on the other player's character registers with the game's
  map tracker on both sides (tested); not yet seen drawn on the screen.
- **D16 crash reports:** change the plan's wording. Sentry is dormant (`InitAutomatically=false`, no crashpad); the
  uploader is the CrashReportClient (to Sentry's Unreal endpoint). The game forwards a user-config
  `[CrashReportClient]` override into the CRC's per-crash config (tested); that the CRC obeys it needs one crash with
  Sentry's hosts blocked.

## Shared files

None edited. New files only: four scenarios under `test/PacificTogetherTest/Scripts/scenarios/`, `tools/kdis/`, the
topic docs and this file. `crashcfg` reads two optional env vars (`PT_SENTRY_EXPECT`, `PT_SENTRY_CLOSE`) set by the
caller, not by the runner.
