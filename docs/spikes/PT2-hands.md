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
