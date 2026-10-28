# M5 anomalies 2: Leech, BombRock, grabbers, stolen car parts, Tourist check (W6, W7, D19)

> Historical research; see the [index](README.md) for current implementation and later evidence.

2026-10-21, lane `anom2`. Mod: `mod/PacificTogether/Scripts/anomalies2.lua`. Scenario: `anomalies2` (fixture `zone`, mutation `noanom2`).
Follows `M5-anomalies.md` (damage forwarding, Tourist freeze) and `M5-world.md` (hazard replication).

## Observations

- Leech and BombRock (`BP_Base_Hazard_WorldItem`) **usually replicate on their own** when spawned at runtime on the host: with the module off
  (`noanom2`) the guest still got a Role 1 copy at the same spot (run `20261021-163808-anom2-anomalies2-noanom2`), but once not at all (run
  `20261021-173243-anom2-anomalies2`, "none" for 30 s). So the host loop in `anomalies2.lua` sets replicates/always-relevant on any that have
  `RemoteRole 0` (the same as `world.lua` does for other hazards; it never logged here, 3 clean runs after). The guest's own spawn points (it
  may add Leeches of its own) are not cleaned up: unknown.
- The guest's copy of a BombRock does not blow up on its own: a blast next to the guest costs the guest 25 once (MSG_Damage_Physical_Explosive,
  forwarded by anomalies.lua), not twice.
- A Leech's leap hurts only the host's character: `CheckForHitPlayer(HitActor)` compares with `BP_MainCharacterManager.CharacterActor`; the hit
  is 15 `MSG_Damage_Physical_Impact`, then a 10 s wait.
- The Physics Grabber likewise: its target (`Target`, `PhysicsCMPToGrab`), the pull (`CharacterMovement:AddForce` on the manager's character, force
  `MapRangeClamped(distance to core - 250 z, 0..500, 6000..8500)` + 150 up), its hit on the grabbed player (MSG_Damage_Physical_Impact, tuning tag
  `WB.Tuning.Anomaly.PhysicsGrabber.Damage.Player`, value not read) and its cone overlap all use the host's character. A guest in its cone is ignored.
- Not in this build (atlas `find`): Abductor, Pickpocket, Can Opener. The only grab/steal hazards are `BP_Hazard_PhysicsGrabber` and
  `BP_Hazard_PartStealer`. The Part Stealer takes car parts with `BP_CarManager:PopOffPartFromCar(Slot tag, force, out Success, out WorldActor)`
  (the same call as crash damage), nothing from the backpack (`BP_InventoryManager_C` is only used to find the car's part).
- `PopOffPartFromCar` on the host's car (door `Body.DoorsRR`): success, and `car.lua` removes it from the guest's car within a second (`PT|car part removed`).
  So stolen or ripped car parts already disappear for the guest (car lane); no new code.
- Tourist: the earlier `ShouldCreep` flag hook ran AFTER the game's body, so the first step after a reset (the host's own view clears `CreepedToCamera`)
  was never held back by a guest's view; the old check passed only because the Tourist had already reached its spot (it creeps in jumps, 407 and 4087 uu
  seen). Runs `20261021-171232-anom2-tourist-mod` (23/25, freeze fails with the flag hook once the test re-arms the Tourist) and
  `20261021-172536-anom2-tourist-mod` (25/25 with the new hook).

## Derived (what is built)

- Leech: pre-hook on `BP_Hazard_Leech_C:CheckForHitPlayer`; when the hit actor is a guest's pawn and `LeechState == 3` (leaping, the game's own test)
  and 10 s have passed, the host dispatches MSG_Damage_Physical_Impact 15 to that pawn; anomalies.lua forwards it to the guest and gives the host
  its health back.
- Grabber: every 100 ms the host asks each grabber whether a guest pawn overlaps its `Cone` (or is within 700 uu of the core when the cone's
  overlap events are off). On first contact the guest takes a hit of 10; while inside (3 s, then a 6 s rest per grabber) the host sends
  `g.anom.pull x y z` (core location) and the guest applies the game's pull force to its own pawn every frame for 0.35 s after each message.
- Tourist (changed in `anomalies.lua`): the `ShouldCreep` hook is replaced by a single-callback hook on `CreepCheck` (runs after the body, may set the
  out value): "could creep" becomes false while a guest's camera sees the Tourist. Scenario `tourist` (modes `mod`, `noanom`, no test hook): after the
  first step the Tourist is put back at its spot with the flag cleared (what the host looking at it would do), so the only thing holding it still is
  the guest's view; mutation `noanom` fails `tourist_frozen_while_guest_looks` (`20261021-172856-anom2-tourist-noanom`).

## Checks (scenario `anomalies2`)

`guest_sees_leech`, `guest_sees_bombrock` (Role 1, near), `guest_hurt_by_leech`, `host_not_hurt_by_leech_on_guest`, `guest_car_has_parts`,
`guest_car_lost_part` (PopOffPartFromCar on the host), `guest_hurt_by_bombrock`, `bombrock_hit_once`, `guest_hurt_by_grabber`,
`guest_pulled_by_grabber` (guest speed > 30 uu/s), `host_not_hurt_by_grabber_on_guest`. Mutation `noanom2` fails the Leech and grabber checks.

## Unknowns / gaps

- The pull is the game's own force and is weak for a 100 kg character (~85 uu/s^2): the guest drifts toward the grabber, it is not dragged.
  The grabber's own grab (attaching, carrying the player to the car) is not mirrored.
- Grabber damage is a fixed 10 (tuning tag not read). A grabber that never sees the host (host far away) still runs its patrol on the host.
- A blast that hits both players: the host gets back up to 1.5x the message from its health (anomalies.lua put-back), so its own share can be
  undone (run `20261021-163226-anom2-anomalies2`: host 88 after a blast that should cost both).
- Leech latching onto the guest (not only the car) and a Leech leap that the game itself starts at the guest are not driven: only the hit is.
- Part Stealer was not spawned live (the PopOff call stands in for its steal); the stolen part's world actor on the ground is not checked on the guest.
