# PT2 story lane: story progression for the guest (G3)

2026-10-22, branch `worktree-agent-a207cf90d99e25d2d`. Mods: `story.lua`, `progression.lua` (one helper). Scenario `storyprog` (fixture `garage`,
mutation `nostoryprog`). No cutscenes and no story props (owner: the story has none).
Results (`local/test-results/`): `20261022-082957-pt2-story-storyprog` 26/26; mutation `20261022-082716-pt2-story-storyprog-nostoryprog` 22/26
(journal history, unlocks, guest task, plus the alive hold that the shortened mutation timeout cuts); `20261022-083223-pt2-story-storysync` 24/24.

## Observations

- Journal history: `UMG_PlayerMenu_Missions` lists `GetCompletedObjectives` (the quest manager's `CompletedObjectives`), each objective's missions
  are shown by `HasMissionBeenCompleted` (`CompletedMissions`). Both arrays are plain TArrays; `arr[n+1] = obj` from Lua appends (verified live).
- Before this lane the guest's `CompletedObjectives` filled only through `StopObjective(o, true)` on objectives it had seen active; `CompletedMissions`
  only through local cascades. Probe (garage, host finishes Q00 intro mission A + FixCar chain): host had `QD_Q00_Intro_Mission_A` and `QD_Q00_Mission_C3`
  in `CompletedMissions`, the guest did not.
- The story is a Blueprint graph (`BP_QuestDirector`, ~110 KB bytecode) reacting to mission events (`AdvanceObjective`, `StartObjective` ...).
  `MissionState:ForceComplete(true)` on the host starts the cascade; in the garage fixture the cascade runs on to `QD_Q00_ZonePrep_Objective`
  and `QD_Q00_ToolRegift_Objective` because the fixture's garage already satisfies the tasks.
- A mission completion's grants, as a snapshot diff on the host: logbook entry (`IA_Garage_ParkingLight`), `WB.Scanning.Garage.ParkingLight`,
  `WB.Missions.<m>.Completed` / `<m>.<task>.Completed` tags (value 0, existence is the flag), `WB.Quests.Objectives.<o>.Completed`. Garage upgrade
  flags, recipe graph nodes, route legs and logbook were already sent by `progression.lua`; only the `.Completed` tags were skipped on purpose
  (`WB.Quests/Missions` belonged to story.lua, which never sent them). The guest's own cascade made most of them locally, late joiners lacked them.
- Task classes (`BPMT_*`) all read the LOCAL managers in `K2_CheckCompletion`. The guest's mirrored mission runs its tasks locally, so a guest that
  holds the item flips `TaskStates[i].bCompleted` by itself (verified: `QD_Generic_InstallDoctorGobbler`, `GotDocGob`, `HasItem_PlayerInventory`).
  The host's task reads the host's bag, so the guest's pick-up never counted.
- Side effect found: the guest's own story script reacted while `applying` was true (ForceCompleteTask inside the mirror) and started its own next
  objective (`ZonePrep`) before the host had it.
- Host dialogue replays the same sequence every 200 ms in headless runs (`DS_Q00_GT_S06_OneLastThing` after the cascade); the guest replayed it
  each time.

## What was built

- `g.story.done` (host to guest, every 5 s and on change, chunked under 28 KB): the host's `CompletedObjectives` and `CompletedMissions` as
  asset paths without the `.Name` suffix. The guest appends the missing ones (max 25 asset loads per message). Add-only. Objectives the host no
  longer has active are stopped with `success = host finished it`, so a guest-local objective is not recorded as finished.
- `applying` now covers only the mirror's own `StartObjective` / `StartNextMission`; what the guest's story script does in answer stays nulled.
- `g.story.task` (guest to host): a task the guest completed locally that the host's mask does not have, only for `BPMT_HasItem_PlayerInventory`,
  `BPMT_HasItem_HandSlot`, `BPMT_InRangeOfTag` (and not with `CheckCar`/`CheckZETI`, which read the shared trunk). The host checks that the
  objective and mission are active and the task open, then `ForceCompleteTask`.
- `progression.lua`: `WB.Quests.*.Completed` and `WB.Missions.*.Completed` tags travel (helper `skipTag`).
- Dialogue: the guest plays the same line at most once per 6 s.
- Mutation `nostoryprog` switches the three additions off (everything of `nostory`/`noprog` stays on).

## Which story objectives can the guest do

- Pick up / hold an item (`HasItem_PlayerInventory`, `HasItem_HandSlot`): yes, counts on the host (proved with the Doctor Gobbler task).
- Reach a place (`InRangeOfTag`, camera near a tagged actor): routed the same way, NOT proved in a scenario (the one mission using it is a field
  guide mission).
- Interact with a story object: the guest's interact reaches the host through `guestact.lua`; tasks that read a whiteboard tag
  (`BPMT_TagIsSet`) follow from the host's own tag.
- Everything about the shared car, trunk, garage stations and route planner (`CarPartInstalled`, `AllItemsInTrunk`, `RouteSelected` ...) is the host's
  state already and counts on the host without routing. Tasks that read the guest's own state but are not whitelisted (`HasItem_AnyInventory`,
  `CraftedItem`, `PlayerHealth`, `PlayerInCar`) are NOT routed: they would read the guest's local car copy and could complete wrongly.

## Gaps / unknowns

- `HasMultiItem_AnyInventory`, `HasItem_AnyInventory`, `CraftedItem` by the guest are not counted (see above).
- The guest's completed lists are never trimmed if the host removes an entry (`RemoveCompletedMission`): rare story rewind.
- Which later missions (Q01+) need other task classes was not played; only Q00 and one generic mission were driven.
- Quest-driven world changes (doors, spawned actors) were not identified; no story props by owner decision.
- The host's headless dialogue loop (same line every 200 ms) was not root-caused; probably a headless audio artefact.

## Follow-up after the merge (progsync regression)

- `progsync` (zone fixture) failed 21/30 and 14/30 on main with `g.story.done` as first built: the zone host has a long finished list, and the
  guest was dropped about 3 s after joining (`remotePCs()[1]` nil at progsync.lua:56). `-Mutate nostoryprog` gave 30/30 (`20261022-093113-pt2-story-progsync-nostoryprog`).
  Cause (derived, not isolated further): a burst of big message chunks plus a burst of synchronous asset loads on the guest in one frame.
- Fix: the host sends new entries at once and the whole list in 3 KB chunks, one per 500 ms tick, again every 10 s; the guest queues the
  entries and loads two assets per 250 ms. Done list goes out before the quest row, so the guest knows an objective is finished before the
  quest row removes it from the active list (the review finding: `StopObjective(o, hostDone)` otherwise abandons it; the done handler would add it
  to the completed list anyway, so the end state was the same, only the stop event differed).
- Results: `progsync` 30/30 `20261022-100536-pt2-story-progsync`; `storyprog` 26/26 `20261022-100816-pt2-story-storyprog`.
  The existing `co:` check in `guest_journal_history_matches_host` covers "the FixCar objective ends in the guest's completed list"; "abandoned vs
  completed" is not observable in the arrays, so no separate check.
