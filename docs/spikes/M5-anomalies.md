# M5 anomalies lane: hazards act on both players (W6, W7, D19)

2026-10-21. Mod: `mod/PacificTogether/Scripts/anomalies.lua`. Scenario: `anomalies` (fixture `zone`, mutation `noanom`); Tourists: `tourist` with `PT_MUTATE=mod` (garage).

## Observations

- Hazards hurt through the message system: `MessageSystem:DispatchMessageInSphere(MSG_Damage_*, ...)` (Landmine, Tesla, BombRock, bollards ...). The
  receiver is `AC_PlayerHealthReceiverHelper` on every `PDP_MainCharacter`; its handler adjusts the process's single `PlayerHealth`.
- The guest's pawn exists on the host with the same component: **a hit on the guest's pawn hurt the HOST's health and the guest felt nothing**
  (direct `DispatchMessage(MSG_Damage_Electrical 10, guestPawn)`: host 100 -> 90, guest unchanged, before the mod).
- One message calls two binds of the receiver (`MessageBind_MSG_Base_Damage_C` and the message's own class). The handler cannot be cancelled: a nulled
  payload, `Damage = 0` and `playerProtected = true` all still hurt the host; `GameResource:Adjust` is called from Blueprint (no hook sees it).
- A hook given as a single callback (as `RegisterHook(path, fn)`) runs AFTER the Blueprint body here: the host's health was already reduced when it ran.
  A post callback passed as second argument never fired.
- Zone fixture: the 10 Landmines are 30000+ uu from the host's spawn; a spawned Landmine near the host works (but throws the car/host about when it
  explodes: `MSG_Damage_Physical_Impact` 19.8 on the host). In the zone the guest's `PlayerCameraManager` on the host stayed at yaw 0 and the host's
  `ClientSetRotation` was not kept; in the garage the camera reaches the host (docs/research/tourists.md).
- Creep logic: a Tourist walks toward camera manager 0's ACTOR location (0,0,0 headless), so in tests it jumps to the origin.

## Derived (what is built)

- Damage on the guest's pawn (host): the receiver hook notes the host's health every frame; on a bind of a guest-pawn receiver the damage message
  (class path, Damage, Spillover, DoT, feedback, distribute mode) goes to the guest as `g.anom.msg` and 40 ms later the host gets back what it
  lost (capped at 1.5x the message). The guest builds the same message class and dispatches it to its own pawn: its own health, magic HP,
  feedback and death handling (health.lua) run as for any hit. Heals take the same route.
- Tourists: `ShouldCreep` (the game's 0.2 s timer) returns at once while `CreepedToCamera` is set and only the host's camera clears it. A hook on
  it sets the flag while a guest's camera sees the Tourist (the game's own test: within 2000 uu, dot > 0.3) and clears it when it was ours.
  Proven in the garage (`tourist` scenario, mode `mod`): `seen=true flag=true forced=true`, moved 0.

## Gaps (not done)

- Grab/steal anomalies (PhysicsGrabber, Pickpocket/PartStealer, Abductor, Can Opener) and the car's own health receivers (`AC_CarHealthReceiver`) were
  not changed: the host's car takes them (the car is the host's). The guest being grabbed/pickpocketed is not handled.
- Leech and BombRock (`BP_Base_Hazard_WorldItem`) are still not replicated; their damage reaches the guest only if the host runs them.
- A Tourist near the guest but far from the host never arms (`PlayerRange` uses camera 0); it still creeps toward the host.
- Tourist freeze not proven in the zone (guest camera on the host did not follow); the damage scenario uses a direct message dispatch, not a
  spawned Landmine, because a Landmine's explosion also hurts/moves the host.
- A legitimate host hit in the same 40 ms window as a guest hit is partly undone only if the sums exceed the 1.5x cap (rare).
