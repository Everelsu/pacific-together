# Tourists (D19, W7)

2026-10-19, lane E. How the Tourist anomaly decides it is "not observed", and how to make "observed by any player"
work with the host authoritative. Sources: `BP_Hazard_Landmine` and `BP_HazardProperty_PlayerRange` extracted from
`pakchunk0` (`reference/pdcoopnet/tools/pakextract.py`) and listed with `tools/kdis/` (Kismet bytecode; listings in
`local/research-extract/laneE/dis*/`, git-ignored), plus scenario `tourist`
(`test/PacificTogetherTest/Scripts/scenarios/tourist.lua`).

## Observations

### Classes (pak listing, export tables)

- The Tourist is `BP_Hazard_Landmine_C` (`/Game/Gameplay/Hazards/Landmine/`), parent `BP_Base_Hazard_C`. VO and
  trophy names tie the two (`DS_ReturnRun_Landmine_Francis_001_TouristsTouristsEverywhere`,
  `IA_Garage_Cosmetic_Trophies_Anomalies_Tourist_*`). Run modifiers: `RM_CreepyTourists`, `RM_VeryCreepyTourists`,
  `RM_GuaranteeTourists*`.
- Subclasses `BP_Hazard_Landmine_Electric_C`, `BP_Hazard_Landmine_Spawn_NearCar_C` / `_NearBuilding_C` /
  `_TunnelMine_C` do not override `CreepCheck`. `BP_Hazard_BigBoyLandmine_C` is a separate `BP_Base_Hazard_C`
  child that does not creep (it spawns mines around itself, `SpawnMinesAround`).
- Not in our garage-time UHT/CXX dumps; `BP_HazardManager` has `DbgActEvt_SPAWN_LANDMINE_Execute` and
  `TotalLandminesSpawnedFromBigMines`.

### The view test (bytecode)

- `ReceiveBeginPlay` path calls `RollForCreep`: `Creep = RandomFloatInRange(1,100) <= WB.Modifiers.Anomalies.Mines.CreepChance`
  (map whiteboard tag), else `<= 15`. Only mines with `Creep` move. If `Creep`, `BP_HazardProperty_PlayerRange` is enabled.
- `BP_HazardProperty_PlayerRange` polls `DistanceToPlayer` on a timer: the 2D distance from the component to
  `GetPlayerCameraManager(self, 0).GetCameraLocation()`. In range -> `OnPlayerInRange` -> `StartCreepTimer`;
  out of range -> `EndCreepTimer`.
- `StartCreepTimer` (if `Creep`): after 0.2 s, `K2_SetTimerDelegate(ShouldCreep, 0.2, looping)`.
- `ShouldCreep` every 0.2 s: if `CreepedToCamera` and `ShouldResetCreep` (camera 0 looks at it: dot >= 0.65) then
  `CreepedToCamera = false`, else return. Then `CreepCheck(out CouldCreep)`; if true, `CreepedToCamera = true`,
  `IsNearbyMineMoving` (wait while a neighbour moves), `CreepTowardCamera`.
- `CreepCheck(out CouldCreep)` (2480 bytes, no line trace, no occlusion test), normal path:
  `cam = GetPlayerCameraManager(self, 0)`; `CouldCreep = |cam.Location - Body| <= 2000 and
  Dot(GetDirectionUnitVector(cam.Location, Body), cam.GetActorForwardVector()) <= 0.3`. A distraction path
  (`DistractionCreep` + `AC_HazardDistractions`) uses the distraction location (<= 15000) instead.
- `CreepTowardCamera` moves toward `GetPlayerCameraManager(self, 0).K2_GetActorLocation()` (or the distraction
  location), by `FMin(distance / CreepAmount, CreepDistance)` with a random yaw of `+-CreepAngle`, through
  `CheckForOpenCreepSpot` and `SetCreepLocationRoatation`, then `OnCreep`.
- So "observed" = camera of player 0 within 2000 uu and the mine within ~72.5 degrees of the view direction
  (acos 0.3). One creep step per look-away: after a step it must be looked at again (dot >= 0.65) to re-arm.
- All player queries in the Tourist and its range property use player index 0. Across all 225 hazard Blueprints
  under `/Game/Gameplay/Hazards/` the listing has 122 `GetPlayerCameraManager(self, 0)` and 8 `GetPlayerPawn(self, 0)`
  calls and no other index; most in `BP_Hazard_PhysicsGrabber` (22), `BP_Hazard_Leech` (16), `BP_Hazard_Spore_Tendril`
  (15), `BP_Hazard_Landmine` (15), `BP_HazardProperty_ImpulseHelper` (14), `BP_Hazard_Blackhole` (11),
  `BP_ZoneStormRoyale` (9) (counts include `BP_MainCharacterManager_C` references).
- On the host, index 0 is the host's own camera manager, so today Tourists react to the host only.

### In game (scenario `tourist`, garage, host + guest, headless)

Runs: `20261019-193321-laneE-tourist` (16/25, Tourist class not loaded, fixed with `LoadAsset`),
`20261019-193938-laneE-tourist` (23/25, marker check bug), `20261019-200157-laneE-tourist` (25/25).
Mutation runs: see the end of this section.

- `LoadAsset(".../BP_Hazard_Landmine.BP_Hazard_Landmine_C")` + `BeginDeferredActorSpawnFromClass` spawns one in the
  garage 800 uu behind the host.
- `CreepCheck` called from Lua: `CouldCreep=true` with the host facing away (`dot=-0.98`, 815 uu), `false` after
  `SetControlRotation` turns the host to it (checks `creepcheck_true_when_host_looks_away`,
  `creepcheck_false_when_host_looks`).
- The guest's view on the host: the host calls `ClientSetRotation(yaw)` on the guest's PlayerController; within 1 s
  the guest's `PlayerCameraManager` on the host reports `GetCameraRotation().Yaw = 216.9` (= -143.1 wanted) and
  `GetCameraLocation() = 3045,4015,194`, the same as the guest's own camera log; `guest:GetBaseAimRotation().Yaw`
  agrees (`guest_camera_on_host`).
- A post-hook `RegisterHook(".../BP_Hazard_Landmine_C:CreepCheck")` that sets `CouldCreep` to false when a remote
  PlayerController's camera passes the same test: fires for a Lua call (that call then returns false) and for the
  game's own 0.2 s timer (5 calls/s). With the host facing away and the guest looking at it (`Creep=true`,
  `StartCreepTimer()`): 35 calls and 35 overrides by t=7 s, moved 0 uu in 8 s (`tourist_frozen_while_guest_looks`).
  Guest turned away: it moved within 1 s (`tourist_creeps_when_nobody_looks`).
- No crash, no `PT|error` in the passing run.

Mutations: `20261019-200639-laneE-tourist-noguestview` (23/25: the host never turns the guest, so
`guest_camera_on_host` and `tourist_frozen_while_guest_looks` FAIL); `20261019-201343-laneE-tourist-nohook` (24/25: the
hook counts but never overrides; the Tourist moved 407 uu in the first second, then `CreepCheck` stopped being called
(2 calls) because it waits to be looked at again; `tourist_frozen_while_guest_looks` FAILs).

## Derived

- D19 needs one host-side hook, no Blueprint edit: post-hook `BP_Hazard_Landmine_C:CreepCheck`, and when
  `CouldCreep` is true, set it false if any remote player's camera (their PlayerCameraManager on the host:
  `GetCameraLocation`/`GetCameraRotation`, fed by the stock `ServerUpdateCamera`) is within 2000 uu with dot > 0.3.
  The subclasses inherit it. Cost: a few vector ops per mine per 0.2 s.
- This only freezes. What stays host-only: activation range (`PlayerRange` uses camera 0, so a Tourist near the guest
  but far from the host never arms), the creep target (`CreepTowardCamera` walks toward the host), and the re-arm
  (`ShouldResetCreep` looks at camera 0 only). The same hook pattern fixes the first: post-hook
  `BP_HazardProperty_PlayerRange_C:DistanceToPlayer` and return the minimum over all players' cameras (benefits every
  hazard using that property). The other two need either a camera-0 swap during the call or accepting
  "Tourists hunt the host" for v1.0.
- The guest cannot see Tourists today: they are spawned by the host's run spawn pass (X3: host-only, not replicated).
  Showing them is W6 work (replicate the actor and its movement from the host, and keep the guest's copy from running
  `RollForCreep`/creep logic of its own).
- Other hazards hard-code player 0 the same way (list above); W6/W8 need the same per-hazard review.

## Guesses

- `ServerUpdateCamera` is only sent while the guest's camera changes; a still guest keeps its last view on the
  host, which is what we want.
- Electric Tourists (`_Electric`) behave the same because they only add explode/conductive events.

## Unknowns

- Behaviour in a real zone with run modifiers (`CreepChance`), distractions and many mines; only one garage-spawned
  mine was tested.
- Whether `ServerUpdateCamera` lags enough at 150 ms to let a Tourist step while the guest turns toward it.
- How the creep target should pick a player (nearest unobserving player?) if we change it.

Verdict: D19 is cheap: one post-hook on `CreepCheck` using the guest's camera manager on the host freezes Tourists
when any player looks (tested); activation range and creep target stay host-only unless we also hook `DistanceToPlayer`.
