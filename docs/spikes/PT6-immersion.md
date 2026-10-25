# PT6 immersion: map transitions and awareness of the other player

Lane `immersion`, 2026-10-25. Branch `lane/immersion` off main 2fe120d, pair `C:\PTLanes\immersion`, port 7851.
Owner's problem: when the host reaches a junction, picks a route or loads, the guest sees nothing of it: its car drives on past
the host's fade-out, then "Paused by host" over a driving car, then the new map from under its textures until the host places it.

## Observations (headless MCP session, coop-zone fixture, probe hooks with timestamps)

Host travel (`BFL_ProgressionHelpers:TravelToNextLeg`, the junction's own path after its fade):
- `TravelToNextLeg` -> `UEngine::LoadMap` in the same frame (0.8 s after the call, the save manager's work); the connection to the guest
  closes there (guest: `PT|native rejoin browse` 0.06 s later).
- `LoadingScreen_C:K2_OnBeginLoad(<next map>)` inside LoadMap; `DrivingGameInstance:HoldLoadingScreen` ~7-9 s later (the spawning manager
  starts), LoadMap post, `K2_OnLevelLoaded`, then 28-32 s of spawning (Sasquatch_82), then `FinishLoadingScreen` ->
  `K2_OnLevelReady` (sets `FadeGoal` 0) -> `FinishAndSpawnPlayer` 0.1 s later -> the widget's own tick fades `StatusBox` 1 -> 0 in
  0.9 s and fires `BP_SpawningManager.LoadScreenFinishedFadingOut`.
- `DrivingGameInstance.LoadingScreenUserWidget` lives on the game instance across maps. `IsInViewport()` is always false for the
  engine's own display: it adds and removes the Slate widget directly. `IsVisible()` stays true, visibility `SelfHitTestInvisible`.
- The world is NOT paused while the loading screen is up after `FinishLoadingScreen` (`IsGamePaused` false during a 21 s hold).

Guest side of the same travel:
- Connection drop -> `rejoin browse` at once; then 15-25 s on the old map with no pawn (the host loads) and no loading screen; then its
  own LoadMap (`K2_OnBeginLoad` fires on the guest too, after the UE4SS LoadMap pre-hook), 3-4 s load, hello sent, then 20-30 s with
  the world visible and no pawn until the host's `FinishAndSpawnPlayer` lets session.lua spawn its character. `K2_OnLevelLoaded`,
  `K2_OnLevelReady` never fire on a client: the engine takes the widget down at its own post-load.
- `ls:K2_OnBeginLoad(map); ls:AddToViewport(20000)` shows the game's loading screen on the guest (TRAVELING..., throbber); the
  `CurrentStateText` can be set; `RemoveFromParent()` takes it down. No error, no crash (3 s shown, headless).

Hold experiment on the host (hook after `K2_OnLevelReady`: `FadeGoal = 1`, `FadeDirection = true`, `StatusBox` opacity 1):
- The screen stayed at opacity 1.00 for the 21 s of the hold (the tick interpolates towards `FadeGoal`; with `FadeDirection` true
  the finished-fading-out event is not fired). `FadeGoal = 0; FadeDirection = false` then faded it out in 0.9 s as the game does.

## Derived

- Host: `K2_OnLevelReady` is the one place to hold; releasing is the game's own fade. No native change needed.
- Guest: show the engine's widget ourselves from the connection drop until the host says "go"; take ours out in the LoadMap pre-hook
  (the engine adds its own in LoadMap) and put it back at post-load (the engine takes its own down there).
- The host's fade start is the first update of the transition actors' timelines (`BP_LevelTransition_EnterExit:Fadeout`, junction
  and garage gate; `BP_LevelTransition_ExitPortal:Final Transition Fade In Timeline`, zone exit and return to garage), ~1 s before
  the travel. The junction menu is `BP_ProgressionManager:Open Map UI`.

## Rendered check (2026-10-25 11:45, two windowed clients on one GPU, PrintWindow captures every 3 s: local/immersion/)

- The host's load and spawn took 107 s with both windows rendered (10-45 s headless). The guest's window showed the game's loading
  screen with "WAITING FOR HOST..." 1.5 s after the host's LoadMap and for the whole 107 s; the host held its own screen 4.5 s
  after its spawn until the guest's character was there; both went to the world on "go". The owner watched this pair: the shared
  load worked, the guest showed "waiting for host" on the loading screen.
- The guest's first reconnect attempt to the still-loading host timed out after 60 s and the native rejoin browsed again (the
  existing flow); our screen stayed up through it.
- `HighResShot` captures no UMG: window captures (PrintWindow) are the way to show UI state.

## Unknowns

- Whether a message sent in the host's LoadMap pre-hook reaches the guest before the close (the guest's own drop detection covers it).
- The host's held screen was not captured (the hold began 9 s after the capture loop ended; headless state: FadeGoal 1, text set,
  status page 0). The "fade" and "route" notices were only exercised by hook registration (the direct TravelToNextLeg call skips
  the junction's own fade and menu): hand play at a real junction is the proof.
- The guest's own death/respawn does not touch this: the drop test is the world's NetDriver, which death leaves alone (not tested).
