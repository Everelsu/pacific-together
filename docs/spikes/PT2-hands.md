# PT2 hands: the other player's item, tool use, light and carry

Module `mod/PacificTogether/Scripts/hands.lua`, messages `g.hands.s` (hand state, both ways, on change and every 3 s) and `g.hands.use` (a use press, both ways). Scenario `hands` (fixture `garage`), mutation `nohands`.
Status: see the end of this file (Results). Lane pt2-hands, test pair `C:\PTLanes\pt2-hands`, port 7931.

## Observations
- The game is first person. A held item is a hand manifestation actor (`BP_BaseHandManifestation_C` and subclasses, local to each process, drawn on `SK_Firstperson`); the character's own body has no item. `PDP_MainCharacter:GetActiveHandItem(false, out)` returns it (key "Hand Item").
- Items (`BP_HandItem_Manifestation`) show `CurrentItemMesh` (a StaticMeshComponent made in `SpawnItemMesh` from the item's HandMeshOverride or WorldMesh, attached to socket "Hand", or "LargeSlot" when `Archetype.Size` is 1). Tools are their own Blueprint classes with their own components.
- The character mesh is the ALS Mannequin skeleton (`Mannequin_AnimBP`, bones `hand_r`, `hand_l`, `spine_03`, `head`; no "Hand"/"LargeSlot" sockets).
- The game has NO third-person tool or carry animation: asset registry lists only 14 AnimMontages, all ALS turn-in-place and get-up, and 127 AnimSequences (ALS locomotion, aim offsets, Gobbler). The first-person arm animations are on another skeleton (`SK_Firstperson_Skeleton`).
- Toggle tools (`BP_BaseToolToggle_Manifestation`): `IsOn`, `DoOn`/`DoOff`, flashlight has a SpotLightComponent on the tool; press goes through `InpActEvt_ToolPrimaryUse_K2Node_InputActionEvent_2/_3` of `BP_BaseHandManifestation` (sets `Desire Tool Primary Use`), which calls the class's own `PrimaryUsePress`.
- `PDP_MainCharacter.PointLight` exists on the character (not the flashlight).
- A `GetItemProperties(nil, ...)` call from Lua crashed the host (AV 0x18, twice): never pass a nil class.

## Derived
- Each side reports its own hand (archetype, mesh path, size, IsOn, light kind) and the other side mirrors it with local actors on its copy of that character: a StaticMeshActor on `hand_r` (size 1: on `spine_03` in front of the chest as the carry pose), a SpotLight/PointLight actor following the head and `GetBaseAimRotation` when the tool is on, a procedural swing (item pitch, 0.45 s) when a use press arrives.
- Tool use sound is not played (the tools' sounds are Wwise events on the first-person actor; would need per-tool event lookup).

## Guesses
- Item orientation in the hand and the chest offset are eyeballed (no screenshot headless): a human has to look.

## Unknowns / gaps
- See Results.

## Findings from the build (add to the lists above)
- Post hooks of Blueprint events never fire (again, see PT1-feel): the use-press hook is a PRE hook on `BP_BaseHandManifestation_C:InpActEvt_ToolPrimaryUse_K2Node_InputActionEvent_2` (_2 press, _3 release). Calling that event on the hand item from Lua runs the real press (a flashlight toggles, `IsOn` flips).
- Tools are not in the hand slot: `Inventory_PlayerHand` stays empty for a tool; the equipped tool's `Instance:GetOuterSlot()` is a pack tile slot. Only two-handed car parts (Archetype.Size 1) sit in `Inventory_PlayerHand`. `GetActiveHandItem(false, out)` is the truth for "what is in hand"; it returns nil when the equipped item leaves its pack slot (`GetOuterSlot():RemoveAllItems`). Emptying the hand slot while a tool is equipped brings the tool back into hand.
- Tool meshes: StaticMeshComponents on the hand actor (flashlight `SM_Tool_Flashlight_01`; fuel can body + handle + base; patch kit bucket + spatula + a VFX `SM_bboxTube`). A StaticMeshComponent's mesh is the property `.StaticMesh` (`GetStaticMesh()` is not callable from Lua). The mod sends every visible mesh (minus bboxTube) with its transform relative to the biggest one (`KismetMathLibrary:MakeRelativeTransform` of the component world transforms).
- Flashlight light values to copy: intensity 80824 (unitless), attenuation 1350, outer cone 36, colour 255/196/191. The level's own lamps are 2..160.
- Attach rules: spawn at the character's location then `K2_AttachToComponent(..., 2, 2, 2)` (SnapToTarget); KeepRelative (0) left the mirror 4000 uu away.
- Large (Size 1) items sit at relative (45, 0, 0) of the character root, attached without a socket.
- Calling `GetItemProperties` with a nil class from the repl crashed the host twice (AV 0x18): the probe script, not the mod.
- A game pair cannot be had on demand: other lanes hold the two slots, runs and the repl waited 10 to 30 minutes each.

## Results
- Scenario `hands` (fixture garage, both directions, 7 phases each, 29 checks per side): PASS 58/58, `20261022-112212-pt2-hands-hands`.
- Mutation `nohands`: see the report / next section.
- Earlier runs of the same scenario failed for scenario bugs and one mod bug each (listed above): `20261022-101127` (alive() on a boolean), `-103807` (the guest never acted: ROLE is "client"), `-105017` (use swing not seen: post hook; empty phase: lingering tool).

## What a human should look at (headless cannot see it)
- Item orientation and position in the right hand: the mesh is snapped to bone `hand_r` with no extra rotation, so a flashlight or can may point sideways or sit in the palm wrongly. Tune `build()` in hands.lua (relative rotation after the attach).
- The carry pose: the item floats 45 uu in front of the character's centre, no arm pose (the mannequin has no carry animation).
- The use swing: a 0.45 s item pitch of 70 degrees, not a real arm animation.
- The flashlight cone: spot light at the head, following the character's aim; brightness copied from the tool.
- No tool sounds are replayed.
