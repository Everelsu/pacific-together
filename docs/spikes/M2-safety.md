# M2 guest safety and name tags (lane F2): S7, G5, Q7, P7, Q9

Shipping code: `mod/PacificTogether/Scripts/safety.lua`, `mod/PacificTogether/Scripts/nametag.lua`,
`native/PacificTogetherNative/guard.cpp` (registered from `dllmain.cpp`, two lines).
Tests: `test/PacificTogetherTest/Scripts/scenarios/safety.lua`, `safety_solo.lua`, `safety_crash.lua`, `nametag.lua`
(helpers in `safety_lib.lua`; `safety_probe.lua` is the research probe for text materials).
Result folders are under `local/test-results/` (git-ignored), test pair `C:\PTLanes\laneF2`, port 7871, all `-Headless`
unless noted.

## Verdicts

| Question | Verdict |
|---|---|
| S7 guest saves | Works: every save writer run as a guest leaves `Saved\SaveGames`, `Saved\Config` and `Content\Bookmarks` unchanged (`20261020-112138-laneF2-safety`, 31/31); mutations fail it. |
| G5 pause, Chrono Dilator | Works: with a guest connected the game's UI pause does not pause and a Chrono Dilator leaves time dilation at 1.0 (same run); no setting is changed. |
| Q7 inert without a session | Works: a host listening alone saves, pauses, gets dilated and has no name tag (`20261019-204328-laneF2-safety_solo`, 13/13); `-Mutate join` fails it. |
| P7 name tag | Works: one tag with the other's PlayerState name on the other character only, alpha 255 near, 158 at 28 m, hidden at 60 m (`20261020-112320-laneF2-nametag`, 22/22). The name is the machine name until Steam is in (OnlineSubsystemNull). |
| Q9 crash upload | Works: a guest crash leaves our marker in its crash folder and starts no CrashReportClient (`20261020-111409-laneF2-safety_crash`, 17/17); `sentry_init` is refused. |

## Observations

- Lua writers (pre-hook sets the slot to -1, logs `PT|safety blocked`): `BaseSaveGameManager:SaveGame`,
  `WriteGameplaySettingsToSlot`, `DeleteGame`, `Rinse`. As a guest: the autosave director (`FlagAutosave` +
  `CheckFlagAndTrigger`) ends in `SaveGame slot=0`, blocked; `SaveGame(current)`, `SaveGame(6)`,
  `WriteGameplaySettingsToSlot(6)`, `DeleteGame(6)` all blocked and return false (`20261020-112138-laneF2-safety`, client log).
- `WriteUserSettings` writes `Saved\SaveGames\USERSETTINGS.sav` and `MakeBookmark` writes
  `<copy>\PenDriverPro\Content\Bookmarks\<name>.bmk`; neither takes a slot. Without the native guard both write
  (`20261019-195818-laneF2-safety`, 24/30: USERSETTINGS.sav rewritten). With it the guard logs
  `PT|safety guard refused CreateFileW ...USERSETTINGS.sav` and `...Content\Bookmarks\pt_test.bmk` and no file changes.
- `SaveCheckpoint` as a guest: no file changed and no write was attempted (guard counter unchanged, no `SaveGame` call
  logged), both with and without the file guard (`20261019-205321-laneF2-safety-nofileguard`).
- The game rewrites `Saved\Config\WindowsNoEditor\GameUserSettings.ini` on every map load with the same bytes; the runner
  lists it as "rewritten", content unchanged in every safety run.
- The guard patches the exe's import table: `PT|native guard imports patched=5/5` (CreateFileW, DeleteFileW, MoveFileW,
  CreateProcessW from KERNEL32, `sentry_init` from the delay-loaded sentry.dll). It is on while we are a guest: switched on
  in the LoadMap pre-hook when a pending net game exists (joining) and set to "net mode is client" after every LoadMap.
- Pause: `BP_UIManager_C:PauseGame(true)` -> `IsGamePaused` false during a session (pre-hook on
  `GameplayStatics:SetGamePaused` forces `false`); true without a guest (`safety_solo`).
- Chrono Dilator (`BP_Attach_Util_Ability_TimeWarper_C`, spawned and `OnAbilityStart`): global time dilation 1.000 after
  4 s in a session (pre-hook on `GameplayStatics:SetGlobalTimeDilation` from that class sets 1.0); below 0.9 alone.
- Name tag: a local `TextRenderActor` attached to the other `PDP_MainCharacter_C` (115 uu above the capsule centre), text
  material `/Engine/EngineMaterials/AntiAliasedTextMaterialTranslucent` so the colour alpha fades it, yawed to face our
  camera every 50 ms, world size grows past 4 m. Measured: camd 303 -> alpha 255; 2827 -> 158; 6000 -> hidden. The
  guest sees one tag on the host's character, none on its own. Screenshots: `20261019-201934-laneF2-nametag-shot`
  (windowed): the name is readable at 3 m; at 28 m it is fainter and is hidden behind a rock (depth tested).
- Crash: the engine starts `"../../../Engine/Binaries/Win64/CrashReportClient.exe" "<Saved/Crashes/UE4CC-...>"
  -Unattended -nullrhi -AppName=UE4-PenDriverPro ...` (seen in the `-Mutate crc` run; `-Unattended` there because the
  game ran `-nullrhi`). With the guard the call fails, and the crash folder gets `PacificTogether-crash.txt`:
  `Pacific Together crash marker / CrashReportClient: not started ... / mod=0.0.1 guest=true`. UE still writes its
  minidump, `CrashContext.runtime-xml` and log there.
- Sentry: in a plain solo run `sentry_init` was refused once, from the test's own `SentrySubsystem:Initialize()`; the game
  had not called it by then (boot, menu, listen garage). With `-Mutate sentry` (DSN pointed at 127.0.0.1:9, init allowed)
  `crashpad_handler.exe` starts. `Default__SentrySettings.DsnUrl` is cleared in memory at mod load (never saved).
- Earlier crashes in this lane (`20261019-194625`, `-194919` safety, `20261019-200223` nametag): `PT|error nametag ...
  UObject instance is nullptr`, then an access violation on the guest; the tag code held objects across the join map
  load. Fixed by dropping all held objects in a LoadMap pre-hook and only scanning objects of the current world; no unexpected
  crash in any later run.

## Mutations (each shows a check can fail)

| Run | Mutation | Result |
|---|---|---|
| `20261019-205904-laneF2-safety-nosession` | the guest never joins | 15/28: pause and dilator checks FAIL, every writer rewrites saves |
| `20261019-205321-laneF2-safety-nofileguard` | native file guard off after joining | 25/31: USERSETTINGS.sav and the bookmark file get written |
| `20261019-204805-laneF2-safety_solo-join` | a guest joins first | 18/20: `solo_pause_works`, `solo_dilator_works` FAIL |
| `20261019-204503-laneF2-safety_solo-sentry` | `sentry_init` allowed (dead local DSN) | 12/13: `solo_sentry_not_started` FAIL (crashpad_handler=1) |
| `20261020-111105-laneF2-safety_crash-crc` | CrashReportClient allowed, started suspended | 15/17: marker and `host_no_crashreportclient` FAIL |
| `20261020-112622-laneF2-nametag-nosession` | the guest never joins | 13/14: `host_tag_near` FAIL (no tag alone) |

## Derived

- A pre-hook cannot cancel a UFunction, but changing its slot argument to -1 makes the save manager write nothing and
  return false; writers with no slot argument need the file-level guard.
- "Is a session active": net mode client, or listen with at least one client connection. A host listening alone counts as
  single player, so Q7 holds for it.
- G5 is done by refusing the effect (pause, dilation) during the session, not by flipping the player's settings, so nothing
  can be persisted by the game's settings writer.
- Q9: the shipping game uses CrashReportClient for crash upload; with `CreateProcessW` refused nothing leaves the PC by
  that route, whatever its ini says.

## Guesses

- Other save paths (story events, garage station autosaves, run end) end in `BaseSaveGameManager:SaveGame` like the
  autosave director does; if one does not, the file guard still refuses it under `Saved\SaveGames`.
- `SaveCheckpoint` probably needs an in-run state the garage does not have, so it did nothing here.
- Sentry would only start if the game's config enabled it; this build does not seem to (no init call seen).

## Unknowns

- The game's original Sentry DSN and whether any build path calls `sentry_init` later in a run (not seen; refused anyway).
- Whether a guest crash while the guard is on loses anything the player wants (the guard only refuses save writes).
- Name tag with Steam persona names (needs the Steam session from lane F1/A) and through walls (it is depth tested now).
- Pause: only the UI path (`BP_UIManager_C:PauseGame`) was tested; any path that pauses without
  `GameplayStatics:SetGamePaused` would get through.
