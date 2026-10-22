# PT1 anom3: Spark Tower, Pickpocket, Bunnies on the guest (W6)

2026-10-22, lane `pt1-anom3`. Module `mod/PacificTogether/Scripts/anomalies3.lua` (+ "anomalies3" in FEATURES), scenario `anomalies3` (fixture `zone`, mutation `noanom3`).

## Observations

- Not in this build (atlas class list `Gameplay/Hazards`, `Gameplay/Boons`; confirms `M5-anomalies2.md`): **Abductor**, **Can Opener**. The wiki names map to
  classes: Pickpocket = `BP_Hazard_PartStealer` (flying), Spark Tower = `BP_Hazard_Tesla` (`TeslaAnomaly`), Bunnies = `BP_Boon_LootCreature` (ChubbyBunny boon).
- Pickpocket in the game's code (atlas `BP_Hazard_PartStealer`): it takes car parts (`GrabCarPart` -> `CarManager:PopOffPartFromCar`, already mirrored by car.lua) AND
  reaches for the player: `CanReachForPlayer` needs the host's player on foot (`PlayerCarState == 0`) within 1500 uu of `MainTendrilConstraint` and in LOS of the host's
  camera (`GetPlayerCameraManager(0)`); it then hits (`HitPlayerDamage`: MSG_Damage_Physical_Impact 3 on `BP_MainCharacterManager.CharacterActor`) and takes a random item of
  `BP_InventoryManager:GetPlayerInventory` (`Spawn Item In World` at the reach spot, `GrabCarPart(item, true)`). Everything uses the host's character and inventory:
  a guest is never reached and never loses an item.
- Spark Tower: `FindTarget` uses an `ActorTagQuery` for `ActorTags.Character.MainPlayer` / car chassis in its AoE, the discharge is `DispatchMessageInSphere(MSG_Damage_Electrical, End, 300)`,
  which anomalies.lua already forwards when it hits a guest's pawn. A Tesla spawned at run time on the host was NOT replicated to the guest (run 20261022-014946: nearest Tesla on the
  guest 44171 uu away, `RemoteRole 0`, `bReplicates false` right after spawn): it is not handled by world.lua's list in practice for run-time spawns.
- Bunny: `PushFx` (called when a player touches the creature) fires a radial force (`PlayerPusher`, `Radius`, `ImpulseStrength` from tuning) and MSG_Damage_Physical_Impact `PushDamage`
  at the host's character only. The guest's copy exists (Role 1) and a push of the host's character did not reach the guest. With the hook a guest within the radius takes the
  damage (forwarded by anomalies.lua, host not hurt) and `g.anom3.push` (`20261022-014946`: guest_hurt_by_bunny, host_not_hurt pass).
- A Part Stealer spawned at the car went to State 5 (car slot) and did not take a part in 120 s (headless zone fixture): not guest related, not investigated.

## Derived (what is built)

- Replication loop for spawned Tesla / Part Stealer / Loot Creature (host, 1 s, same as anomalies2 for item hazards).
- Pickpocket for the guest: every 250 ms the host checks each Part Stealer (not reaching/holding: State not 1/3/4, 25 s... 8 s retry) for a guest pawn within 1200 uu; it sends
  `g.anom3.steal`; the guest declines when in the car or with an empty backpack, otherwise hurts itself 3, removes one random backpack item (`RemoveItemsOfType`) and answers
  `g.anom3.stolen <stealer>\t<archetype>`; the host spawns the item at the guest (`InventorySystem:SpawnItemActor`) and has the stealer take it (`GrabCarPart(item, true)`)
  unless it already holds something.
- Bunny: hook on `PushFx` (host): a guest pawn inside `PlayerPusher.Radius` takes `PushDamage` (tuning read through `TuningFloatLibrary:Conv_TuningFloatToFloat`) and gets `g.anom3.push`;
  the guest applies a velocity impulse away from the creature.

## Guesses

## Unknowns