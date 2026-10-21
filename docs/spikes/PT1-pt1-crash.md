# PT1 lane pt1-crash: host crash on the pause menu with a guest

Playtest 1 (2026-10-21, build 0.0.5-dev-4628d2d): the host crashed as soon as it pressed Esc with a guest connected,
"Pause game while in menus" on or off. Minidumps: `local/playtest-20261021/UE4CC-*` (3, same PCallStackHash).

## Observations
- All three dumps: AV reading 0x178 at `+0x3160a56`, rcx = 0. Read with a hand-written minidump parser (exception
  context + stack scan) and `dumpbin /disasm` (VS Build Tools, already installed) on the test copy's exe (image base 0x140000000).
- Call chain (return addresses on the crashing stack, read from the code):
  `0x1410a5b60` (game code, ticks `World->GetPlayerControllerIterator()` and calls vtable `+0xAB0` on each PC)
  -> `0x142fbc4d0` `APlayerController::PlayerTick` (bShortConnectTimeOut at +0x3E0, then TickPlayerInput(dt, dt==0))
  -> `0x142fc4f50` `APlayerController::TickPlayerInput` (loads `this+0x348` = PlayerInput, `check()` compiled out)
  -> `0x143182040` `UPlayerInput::Tick` -> `0x143160a50` `ConditionalInitAxisProperties` reads `AxisProperties.Num()`
  at PlayerInput+0x178 with PlayerInput = null.
- `0x1410a5b60` is a timer callback set up by `0x1410a5a60`, whose only caller `0x14113d4d0` is an exec thunk with
  (UObject*, FLatentActionInfo) parameters: `UPenDriverViewportClient::ClearAllPressedInputs(WorldContext, LatentInfo)`.
  Its only Blueprint caller is `BP_UIManager` `SetPauseMenuOpened` (open and close), before `PauseGame`.
- Engine 4.27 never calls PlayerTick on a remote player's controller on the server and only creates PlayerInput for
  local players (`InitInputSystem`), so the guest's controller on the host has `PlayerInput == null`.
- The crash marker's "depth 0" (not inside ProcessEvent) fits: the timer runs from the world tick.

## Derived
- Root cause is the game's own ClearAllPressedInputs + a second (remote) PlayerController, not our mod's hooks; the old
  SetGamePaused rewrite and the pause option are unrelated (the timer runs whether the world pauses or not).
- Fix: the host gives each remote controller an empty `UPlayerInput` at login (session.lua `giveInput`). PlayerTick on it
  then only does UpdateRotation with zero input (only while that timer fires).

## Guesses
- The 2026-10-19 idle-host crash (NOTES.md, same address, last line a mouse lock change) was the game opening its pause
  menu on window focus loss. `0x1410a5b60` and `0x1410a5a60` each have exactly one caller in the exe (scanned for
  direct call/jmp), so the timer only starts from the Blueprint call.

## Unknowns
- Whether the game opens the pause menu on focus loss (not checked).
