# Garage stations for the guest (D21, G2)

2026-10-19, lane E. How the Fabrication, Tinker and Detailing stations work for one player, and what the guest needs
so the host performs each action with the shared resources. Sources: UE4SS dumps (`local/dumps`), station and UI
Blueprints extracted from `pakchunk0` and listed with `tools/kdis/` (`local/research-extract/laneE/dis/`, git-ignored), scenario
`stations` (`test/PacificTogetherTest/Scripts/scenarios/stations.lua`).

## Observations

### Which actor is which

| Station (in game) | Actor class | UI | Opened by |
|---|---|---|---|
| Fabrication | `BP_Garage_CraftingTable_01_New_C` (parent `BP_BaseGarageUpgrade_AttachmentManifestation_C`) | player menu page `recipe`: `UMG_CraftingUI_Main` / `_RecipeList` / `_Recipe` / `_CraftButton` | `Highlight.OnHighlightInteract` -> `BP_InventoryManager_C.OpenCraftUI(GetCraftingBenchTier(), true, true)` -> `OpenPlayerMenu(name:recipe, ST_PlayerMenuParams{CraftingTier, IncludeGarageForCrafting, IncludeCarForCrafting, ...})` |
| Tinker | `BP_Garage_QuirkFixer_C` (asset folder `CarGarage/Stations/QuirkFixer`, icons `Tinker-Station-0x`) | world-space screen on the station: `UMG_Garage_QuirkFixer`, `UMG_QuirkDetective_*`, `UMG_QuirkFixer_*` | `BP_InteractCameraComponent` focus (`OnFocusBegin/End`) |
| Detailing | `BP_Garage_CosmeticsStation_C` (folder `CosmeticsStation`, icon `Detailing-Station`) | world-space screen: `UMG_Cosmetics_Standalone` / `_Main` / `_SwapWindow_*` | `BP_InteractCameraComponent` focus; `SetContainer(BP_InventoryContainerComponent)` |

All three plus `BP_Garage_InventingBench_C`, `BP_StatusEffectManager_C`, `BP_Carpart_Internal_GobblerScreen_C` and
`BP_RunPlanner_MapTable_2_C` exist once in a fresh garage with no save (`stations` run, `PT|info stations`).
X3: garage stations and storage are separate, non-replicated actors on each side.

### The actions (bytecode)

- **Fabrication craft.** `UMG_CraftingUI_RecipeList` (craft-button-finished event) calls
  `BP_InventoryManager_C."Craft Recipe Asset"(UInventoryRecipe* Recipe, IncludeGarage, IncludeCar, out Success)`
  with `IncludeGarage/IncludeCar` from `GetActiveTier()`. That calls `Recipe.GetRecipe(self)` ->
  `CraftRecipe(FRecipe, IncludeGarage, IncludeCar)` -> native `GetDefaultRecipeContainers(...)` (backpack, garage,
  car) -> static native `UInventoryRecipe::ExecuteRecipe(World, Recipe, Inputs, Outputs, ProductsContext=2)` ->
  `ERecipeCraftResult`; on success `OnRecipeExecuted` and the shopping list drops the recipe. Craftability in the UI:
  `"Can Craft Recipe Asset"(Recipe, HandOnly, AllowLocked, bCheckTier, UseActiveTier, out CanCraft, out Result)`.
- **Tinker (quirks).** Cure: `UMG_QuirkDetective_Solutions` -> `BP_StatusEffectManager_C.CureCarQuirk(QuirkToCure,
  out Removed)`: for `SE_Quirk_MixAndMatch_C` it crafts the quirk's cure recipe through `"Craft Recipe Asset"`
  (same path as Fabrication), then `SendQuirkToGraveyard`, `RemoveStatusEffect`, `CurrencyAdjust(CA_MechXP, bounty)`,
  `WB.Statistics.Quirks.QuirksCured += 1`, `BP_QuestManager_C.OnCuredQuirk()`. Hints:
  `UMG_QuirkDetective_Diagnose` calls `InventoryManager.CurrencyAdjust(CA_AnchorJuice_Stable, -GetHintCost())`
  directly from the widget (and `CurrencyHasEnough` first). Quirks are status effects on the car the host owns.
- **Detailing (cosmetics).** `UMG_Cosmetics_Main.EquipSlot` -> `ItemSlot.SwapSlotContents(SelectedSlot)` between the
  station's cosmetic container slot and the car's equipped container (`GetCarEquippedContainer`); the station fills its
  container from `FreeCosmetics`/`StockCosmetics` and `GiveOwnedCosmetics`. `DepositItem` moves a unique cosmetic in.
  So detailing is plain item-slot moves, native `UItemSlot::SwapSlotContents` / `TransferSwapIntoSlot`.

### In game (scenario `stations`, one game, garage, no save, headless)

Runs: `20261019-194245-laneE-stations` (8/11, out-param call shape), `20261019-194747` (10/11, picked an empty test
recipe), `20261019-195056` (8/11, no active tier, 0 craftable), `20261019-195300-laneE-stations` (11/11).
Mutations: `20261019-195504-laneE-stations-noblock` (10/11, `guest_block_keeps_items` FAIL),
`20261019-195638-laneE-stations-noresources` (8/11, nothing craftable, the three craft checks FAIL).

- `SetActiveTier(3, true, true)` (what the station UI sets) and the debug event
  `DbgActEvt_GiveResourcePile_Execute`: 191 loaded Fabrication recipes with inputs and products, 14 craftable.
  Without the pile: 0 craftable.
- Host craft from Lua, the call the UI makes: `"Craft Recipe Asset"(CR_Tool_Target_FixElectronics, true, true)` ->
  `Success=true`, owned items `IA_Resource_Raw_Battery-1 IA_Resource_Raw_Copper-2 IA_Resource_Raw_Electronics-1
  IA_Tool_Target_FixElectronics+1` (`host_craft_changes_items`).
- Guest-side block: a pre-hook on `/Script/PenDriverInventory.InventoryRecipe:ExecuteRecipe` that empties its
  `Inputs` and `Outputs` arrays makes the same call return `Success=false` with no item change; the hook fired once
  (`guest_block_keeps_items`). Without the hook (`noblock`) the second craft changes items and the check fails.
- UE4SS call shapes that worked: one table per out param; a bool/struct out param arrives as `t.<ParamName>`, an
  array out param as the table's own elements (each a RemoteUnrealParam, `:get()`). BP function hooks are post-only.

## Derived

- **One host action per station, all reachable by an intent:**
  - Fabrication: `craft <recipe asset path>` -> host `SetActiveTier(tier, true, true)` + `"Craft Recipe Asset"(recipe, true, true)`.
    Tested on one game. Inputs come from the host's backpack, garage and car; the product goes to the host's
    containers (`GetDefaultRecipeContainers` outputs). For "shared resources" that is right; a product meant for the
    guest's backpack needs a follow-up item move.
  - Tinker: `cure <quirk id>` -> host `StatusEffectManager.CureCarQuirk(quirk)`; `hint <quirk id>` -> host
    `CurrencyAdjust(CA_AnchorJuice_Stable, -cost)` plus the reveal state. Quirk id = status-effect class + the car
    part slot it sits on (the car exists on both sides with different object names, X3).
  - Detailing: generic `slot swap <container id> <index> <container id> <index>` -> host `UItemSlot::SwapSlotContents`.
    This is the same item-slot intent G1/P3/C6 need anyway.
- **Guest side:** the guest can keep the game's own UIs (they are local widgets reading local containers), if the
  guest's local garage, car and station containers mirror the host's. The intercept points are native, so pre-hooks
  can neutralise them: `UInventoryRecipe::ExecuteRecipe` (tested), `UItemSlot::SwapSlotContents/TransferSwapIntoSlot`,
  `UBaseInventoryManager::CurrencyAdjust`, `RemoveStatusEffect`-family natives. BP functions such as `CureCarQuirk`
  cannot be stopped from Lua (post-hook only), so intercept the natives they call, or read the intent from a post-hook
  and roll the local effect back from the host's state.
- The real dependency is container mirroring (M4): without it the guest's station UIs show the guest's own empty
  garage. D21 should be built after the item-slot intent and container sync, not before.

## Guesses

- Every crafting entry point (player menu crafting, Fabrication, Tinker cures, player equipment station) funnels
  into `CraftRecipe` -> `ExecuteRecipe`, so one guest-side hook covers all of them.
- `ProductsContext=2` and the outputs list decide where products land; not checked which container got the tool.

## Unknowns

- How `InteractCameraComponent` focus behaves for a second player (camera, input stack, two players on one screen).
- The guest's local garage after M4 sync: whether `GiveOwnedCosmetics` / `FreeCosmetics` on the guest's station add
  duplicates that must be suppressed.
- Tinker diagnosis state (`Diagnosed`, revealed hints) storage: on the status effect object, so it rides with the car.
- Inventing bench (`BP_Garage_InventingBench_C`, research nodes) not covered by D21; not studied.

Verdict: D21 is feasible with three small host intents (craft, cure/hint, slot swap) on the game's own manager
functions; the host half of craft and the guest-side block are tested; it depends on mirrored containers (M4).
