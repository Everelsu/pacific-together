# PT1 parts: the guest repairs and breaks car parts

Code: `mod/PacificTogether/Scripts/guestparts.lua` (new), small edits in `guestact.lua` (paste heal, `M.slotOf`), `loot.lua` (`M.idOf`, `M.actorOf`),
`main.lua` (FEATURES). Scenario `guestparts` (`-Fixture gateway`), mutation `noguestparts`. Results (local/test-results): `20261021-231040-pt1-parts-guestparts` 33/33,
mutation `20261021-231404-pt1-parts-guestparts-noguestparts` 26/33 (7 fail). First run on the code before the lane's fixes was not kept; the mutation shows the playtest behaviour.

## Observations
- Real repair putty does not call `PatchPart`: it spawns `BP_ToolSpawn_PatchKitPaste` (`ActorToHeal`, `HealerData`) that calls `HealthComp.HealDamage` over time. The old intent was only sent from `PatchPart`, so nothing reached the host.
- Scrapper: `OnTickInUse` dispatches `MSG_Damage_Physical_Piercing_Scrapper` (3/50 ms scale) through the message system to the hit actor. `PrimaryUsePress` with the pawn near and aimed (`SetControlRotation`) really ticks it headless (TimeToMax rises, HP falls) but was flaky.
- A part with `MaxBreakHealth > 0` dies in two steps: HealthZero then StartBreaking, then Broken -> `DoSmash` -> `TryDropHarvestablesOnDeath` -> `SpawnItems`. On the host this runs; on the guest's copy of a wreck part HealthZero fires but StartBreaking never does (copy is not the same actor state), so it stays at 0 HP and never drops.
- A hook registered while the main menu is up did not survive the map load: register after a `BP_HealthComponent_C` exists.
- A single-callback RegisterHook behaves as post; to run before the function pass a second (empty) callback. A post callback next to a pre did not fire here.
- A spawned hidden `BP_Tool_Target_ItemHarvest_Scrapper_C` (no item) is a good message source: the host breaks parts and drops items.
- `LoadAsset` the paste class on the guest before spawning (not loaded until a patch kit is held).
- Hot reload 3 times in a row crashed the client (access violation 0x90); every verified run is a fresh start.

## Derived
- Guest: pre-hook on `BP_HealthComponent:Process Damage Message` for scrapper messages on a car part (`C slot`) or wreck part (`P id`): raise the copy to full health, the loop (200 ms) puts the health back and sends `g.parts.dmg kind id damage` (summed). No local break, so no ghost drops.
- Host: dispatches the same message (source = hidden scrapper) at its part; the game's own flow breaks it, drops the items, car.lua state removes the door on the guest, loot.lua `D` removes the wreck copy and `A` shows the drops.
- Repair: `HealDamage` on a part while a paste actor targets that component is sent at once as `g.act.heal` (host heals, state message keeps it).

## Guesses / gaps
- Scenario does not press the tool (headless aim is flaky): it dispatches the scrapper's message from the guest's real held scrapper and emulates the paste's tick (spawns the real paste actor, sets `HealthComp`, calls `HealDamage`).
- Only the scrapper's message is forwarded. Hammer, cutter (explosive shot), prybar carry settings structs: not forwarded.
- Car-part drops spawn where the game's `SpawnItems` puts them on the host (near the host's player or the part), both players can pick them up; guest's own HP display of a damaged part does not move until the host's state arrives.
- The guest's damaged HP of a wreck copy is not shown (copy stays at its HP; the host's break removes it).
