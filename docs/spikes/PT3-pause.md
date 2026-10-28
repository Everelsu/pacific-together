# PT3 pause: inventories must not pause the host's world, "Paused by host" label

> Historical research; see the [index](README.md) for current implementation and later evidence.

Module `mod/PacificTogether/Scripts/pause.lua` (new), label in `overlay.lua`; message `g.pause.s` (host to guest, "1" or "0", resent every second while paused). Scenario `pausehost`, mutation `nopause`.

## Observations
- The game pauses through one funnel: `BP_UIManager_C:PauseGame(Instigator FName, Paused bool, out Success)` keeps a map of instigators and calls `SetGamePaused(any)`. Instigators found in the bytecode (local/atlas/bp): `pausemenu` (Esc), `playermenu` (BP_InventoryManager.OpenPlayerMenu when PauseWhileInMenus == 2), `pauseforlogbook` (setting == 1), `abilityui` (BP_CarPart_Internal_LimBox), `mapui` (BP_ProgressionManager), `Photomode`.
- #16 (host uses an ARC anchor, guest freezes for good): host UE4SS.log 19:14-19:18 has no error and its mod loops kept running (car.lua perf lines every minute), so nothing hung on the host. The guest engine log of that session (backup-2026.10.23-16.17.31) has `CreateSavedMove: Hit limit of 96 saved moves` bursts from 16:14 (118 in all), i.e. the host stopped acknowledging the guest's moves for stretches; the last guest door and loot actions on the host are 19:15:26 and the last host trunk send 19:15:56.
- The ARC machine is BP_Carpart_Internal_GobblerScreen_C (screen, uses BP_InteractCameraComponent: SetViewTargetWithBlend on the focusing player) plus BP_Carpart_Internal_Gobbler_C (AddingAnchorCompleteLogic: item property update, AnchorDissovleTimeline, `BP_CarManager.OnAnchorGobbled`). Neither calls PauseGame, SetGlobalTimeDilation or cinematic mode.

## Derived
- Pausing only the instigator `pausemenu` is the Esc menu; everything else is an inventory-type menu and can be forced to false while a session is active.

## Guesses
- #16 cause not found. Candidates: the interact-camera view-target change on the host side while the guest's car copy is seated; the guest's own ARC copy running the dissolve timeline. Needs the guest's UE4SS log of that session (lost) or a live repro with `arckey`-style setup plus an anchor in the host's hand.

## Unknowns
- Whether the freeze in #16 is a guest-local pause (world paused by the game on the guest) or a hung game thread; sounds kept playing, which fits a paused world (audio runs) more than a hang.

## Results
- Reproduced on code without the fix: grid open with option 2 -> `paused=true`, guest travelled 0 uu (result 20261023-235101, hook not yet loaded).
- Fix: BP hook with ONE callback runs after the body (pre-hook rewriting Paused did nothing); it calls `PauseGame(instigator, false)` again for every instigator but "PauseMenu" (the game's name is `PauseMenu`, case matters). Overlay banner `PTBanner` is the box's last child.
- `pausehost` 27/27 `20261024-005815-pt3-pause-pausehost`; mutation `nopause` 22/27 (grid walk, label shown/cleared fail) `20261024-014327-pt3-pause-pausehost-nopause`.
- Guest movement in the garage is slow (about 2 uu/s with AddMovementInput), so the movement check threshold is 10 uu, not a distance test.
- Not verified: logbook/map/ability menus (same funnel, refused the same way), real container/trunk menus (same playermenu instigator).
