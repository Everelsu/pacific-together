# M4 player health (P4, D6)

> Historical research; see the [index](README.md) for current implementation and later evidence.

Runs: `20261021-112325-player-playerhealth` 26/26, `-nohealth` `20261021-112120` 20/26 (fails as it must), `20261021-111217-player-nametag` 22/22, `20261021-111549-player-session` 40/40.

## Observations
- Player health = `BP_ResourceManager_C.PlayerHealth` (UGameResource, Current/Maximum/Minimum), one per process (game instance subobject). Damage messages go to `AC_PlayerHealthReceiverHelper`, which finds the manager with K2FindManager, not the hit actor.
- Death: `BP_ResourceDirector.CheckForGameOver` (Current <= 0, alive, `bEnablePlayerDeath`) -> `BP_MainCharacterManager.KillPlayer` (HUD hidden, item penalty, 4 s timer -> `OnPlayerDeathReturnTimer` -> TravelToGarage).
- Fall damage: `PDP_MainCharacter.ReceiveHit` -> debounce -> `ApplyFallDamage` on the local manager.

## Derived
- The guest's own sim already does its damage, radiation, healing and HUD; only death and the other player's character need care.
- A landing of the other player's character would hurt the local player: `ReceiveHit` is muted on remote characters (session.lua LOCAL_ONLY).
- `bEnablePlayerDeath=false` would be persisted (settings are rewritten on map load), so the guest instead gets `PlayerHealth.Minimum = 1` at runtime (reset when the session ends); at 1 health.lua runs the guest's death: black screen 3 s, host teleports the guest's character next to the car, full health.

## Guesses
- Host radiation hazards overlapping the guest's character on the host do not hurt the host (damage is not per actor); not tested.

## Unknowns / gaps
- Guest backpack is NOT dropped as a bag and nothing is lost (the game's KillPlayer item penalty never runs). Needs a drop-item path (BFL_InventorySlotUtils Spawn Item Player Drop) plus loot lane.
- Damage in the test is applied with `PlayerHealth:Adjust` (the sink of every damage message), not a real hazard.
- Guest hazards are the guest's own copies of the world (X3).
