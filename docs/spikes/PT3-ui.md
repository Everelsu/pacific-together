# PT3-ui: guest immersion (guestui.lua)

Observations
- Guest Esc: the controller's PauseMenu input event runs, then `BP_UIManager "Set Pause Menu Opened"` -> `PauseGame` -> `SetGamePaused`; on a client `UGameplayStatics::SetGamePaused` returns false (checked live), and the game shows the menu widget only on success. So Esc was dead.
- Hook `/Game/Systems/Managers/BP_UIManager.BP_UIManager_C:Set Pause Menu Opened` fires for Lua calls and for the pause widget's own close call; the class is not loaded at mod start (hook from a loop).
- Scenario guestui 40/40 (local/test-results/20261023-233555-pt3-ui-guestui); mutation noguestui 31/40 (20261023-233425-pt3-ui-guestui-noguestui).

Derived
- guestui.lua calls `hud:SetPauseMenuWidgetVisible(opened)` after that event on the guest; the host's world is not paused (host time advanced 4.0 s with the guest menu open).

Guesses
- F8: the hook path works (console `ptunstick` runs it, overlay "Controls reset"); the owner's laptop likely needs Fn for F8. End is bound as a second key. Not verified with a real key press.

Unknowns
- Whether the pause menu takes mouse/keyboard focus on a rendered guest (headless only).
- The fade runs after the seat snap is noticed (100 ms poll), not before it.
- "Waiting for host" at the zone entry: triggers on no main character, or MOVE_None for 3 s while not seated; the real stall state of playtest #17 was not seen.
