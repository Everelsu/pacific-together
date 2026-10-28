# M5 story lane: the guest experiences the host's story (G3, G4)

> Historical research; see the [index](README.md) for current implementation and later evidence.

2026-10-21. Mod: `mod/PacificTogether/Scripts/story.lua`. Scenario: `storysync` (fixture `garage`, mutation `nostory`).
Results (`local/test-results/`): `20261021-140644-story-storysync` 24/24; mutation `20261021-141128-story-storysync-nostory` 21/24
(quest match, follow step, voice line fail); regressions `20261021-141614-story-worldsync` 27/27, `20261021-141916-story-session` 40/40.

## Observations (game code, atlas + live)

- Quest manager `BP_QuestManager_C` < `BaseMissionManager`: `ActiveObjectives` (`MissionObjectiveState`: `Objective`, `ActiveMissionState`,
  `CurrentMissionIndex`), `ActiveMissionState` (`MissionState`: `Data`, `Tasks`, `TaskStates[i].bCompleted`). The HUD (`PDP_PlayerHUD_Main >
  UMG_Missions_Main > UMG_Objective_Info`, task widgets) and the player menu mission tab are built from the manager's delegates, so a
  guest quest manager that holds the same objective shows the same HUD objective and journal text with no widget code.
- Garage fixture: host has `QD_Q00_Intro_Objective` / `QD_Q00_Intro_Mission_A` active, 2 tasks (`BPMT_TagIsSet`), `TaskMode` 2 (parallel:
  `ActiveTaskIndex` stays 0, the completed flags in `TaskStates` are what change). `AdvanceAllObjectives()` did nothing there;
  `MissionState:ForceCompleteTask(task)` flips `bCompleted`.
- Guest: `StartObjective(obj, true, false)` leaves `ActiveMissionState` nil; `MissionObjectiveState:StartNextMission(mission)` sets it.
- Dialogue: `BP_DialogueManager_C` (< `BaseDialogueManager`) `PlaySequence(DialogueSequence, priority, actor)`, `CurrentlyPlayingSequence`;
  1004 `DialogueSequence` assets (`/Game/Gameplay/VO/...`) carry text, segments (subtitles, Wwise events) and priority; the manager's
  `CaptionWidget` (closed captions) shows the subtitles. Mission configs (`MissionDialogueConfig`) dispatch dialogue events from the mission
  state. Radio transmissions and voice lines go through the same manager.
- Cutscenes: level sequences, `ALevelSequenceActor` tracked in `DrivingGameInstance.LevelSequences`; the player controller has
  `IsPlayingCutscene/GetCurrentCutscene/SkipCutscene`. None placed in the garage after Q00 wake-up.
- Story world drivers: level-placed `NarrativeBeatActor`s (`BP_Fig_Mission_Chapter*`, `BP_ExpeditionBeat_*`), `Garage_Mission` level
  script, `BP_Garage_NarrativeStation`, spawned `BP_Resource_Narrative_Q01_RadioBitsGrabbable`.

## What is built

- Quest mirror: host sends (change, plus every 3 s) one row per active objective: objective path, active mission path, completed-task
  mask (`g.story.quest`). Guest starts missing objectives, moves to the host's mission, force-completes the tasks the host completed, stops
  objectives the host no longer has. Only story.lua sets `applying`; the pre-hooks that null `StartMission/StartObjective/AdvanceObjective`
  on a guest (moved here from world.lua) stay in force for everything else, so the guest cannot start or advance a story itself.
- Dialogue: host polls `CurrentlyPlayingSequence` (200 ms) and sends the asset path + priority (`g.story.say`); guest plays it through its own
  dialogue manager, so audio and subtitles are the game's own, local and 2D/radio as the game decides.
- Cutscenes: host reports a `LevelSequenceActor` that starts playing (`g.story.cut`); the guest plays the same-named placed actor's player.
  NOT tested (no cutscene reachable in the fixtures).
- Story props: host replicates `BP_Resource_Narrative_Q01_RadioBitsGrabbable` (SetReplicates, always relevant), guest drops its own copies.
  NOT tested.

## Gaps

- Completed objectives/missions (journal history) are not mirrored, only the active ones; a guest joining late sees the active ones at once.
- Guest's own game still dispatches its own dialogue events (ambient chatter, driving lines): can double a host line. Not blocked.
- Mission rewards, tags and whiteboard changes of a story step are host-side only; the guest's `ForceCompleteTask` may run the task's local completion effects.
- Cutscene mirror assumes the same actor exists in the guest's level; no input/camera handling (the game's own sequence end restores it); untested.
- Story world changes beyond narrative resources (beat-driven prop spawns, doors, garage changes) not identified; beat actors on the guest stay destroyed.
- `NarrativeBeatActor`s on the host start from mission events; the guest sees only what the host's actors replicate.

## Unknowns

- Whether the guest's tasks (`BPMT_TagIsSet` etc.) complete on their own from guest-local tags in a long play.
- Which story steps spawn actors; needs a play through Q00-Q03 on the host with an actor diff.
