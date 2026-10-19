-- D21 probe (docs/research/garage-stations.md), one game in the garage. The host side of a "craft" intent is the
-- game's own BP_InventoryManager_C."Craft Recipe Asset" with shared containers; the guest side is a pre-hook on the
-- native ExecuteRecipe that empties its containers so the local craft does nothing.
-- Mutations: noresources (no debug resource pile, nothing to craft), noblock (the guest-side block is not installed).
local EXEC = "/Script/PenDriverInventory.InventoryRecipe:ExecuteRecipe"

return function(T)
    local M = T.MUTATE
    local mgr, recipe, before
    local blocked, rawErr = 0, nil

    local function owned()
        -- an array out param comes back as the table's own elements (RemoteUnrealParam each)
        local out, counts = {}, {}
        mgr:GetOwnedItems(true, true, true, out)
        for _, e in ipairs(out) do
            local a = e:get().Archetype
            local k = a:IsValid() and a:GetFName():ToString() or "?"
            counts[k] = (counts[k] or 0) + 1
        end
        return counts
    end
    local function diff(a, b)
        local d = {}
        for k, v in pairs(b) do if v ~= (a[k] or 0) then table.insert(d, string.format("%s%+d", k, v - (a[k] or 0))) end end
        for k, v in pairs(a) do if not b[k] then table.insert(d, string.format("%s%+d", k, -v)) end end
        table.sort(d)
        return d
    end
    local function craft()
        local out = {}
        mgr["Craft Recipe Asset"](mgr, recipe, true, true, out)
        return out.Success
    end

    return {
        T.onMap("RB_MainMenu", 90),
        { wait = 5 },
        { run = function() T.console("open " .. T.GARAGE) end },
        T.onMap("RB_Garage", 120),
        { wait = 15 },
        { check = "stations_present", timeout = 20, cond = function()
            mgr = T.first("BP_InventoryManager_C")
            local found = {}
            for _, c in ipairs({ "BP_Garage_CraftingTable_01_New_C", "BP_Garage_QuirkFixer_C", "BP_Garage_CosmeticsStation_C",
                "BP_Garage_InventingBench_C", "BP_StatusEffectManager_C", "BP_Carpart_Internal_GobblerScreen_C", "BP_RunPlanner_MapTable_2_C" }) do
                local n = 0
                for _, o in ipairs(FindAllOf(c) or {}) do if o:IsValid() then n = n + 1 end end
                table.insert(found, c .. "=" .. n)
            end
            T.log("PT|info stations %s", table.concat(found, " "))
            return mgr ~= nil and T.first("BP_Garage_CraftingTable_01_New_C") ~= nil
        end },
        -- what OpenCraftUI(tier, true, true) sets for the Fabrication station: craft from backpack, garage and car
        { run = function() mgr:SetActiveTier(3, true, true); if M ~= "noresources" then mgr:DbgActEvt_GiveResourcePile_Execute() end end },
        { wait = 3 },
        { check = "found_craftable_recipe", timeout = 10, cond = function()
            local total, ok = 0, 0
            for _, r in ipairs(FindAllOf("InventoryRecipe") or {}) do
                -- a real Fabrication recipe: something in, something out (cures and test recipes have neither)
                local okr, real = pcall(function() local raw = r:GetRecipeRaw(); return #raw.Components > 0 and #raw.Products > 0 end)
                if not okr and not rawErr then rawErr = tostring(real); T.log("PT|info GetRecipeRaw: %s", rawErr) end
                real = okr and real
                if r:IsValid() and real and r:GetFullName():find("/Inventory/") then
                    total = total + 1
                    local can, res = {}, {}
                    mgr["Can Craft Recipe Asset"](mgr, r, false, true, false, true, can, res)
                    if can.CanCraft then ok = ok + 1; recipe = recipe or r end
                end
            end
            T.log("PT|info recipes loaded=%d craftable=%d first=%s", total, ok, T.name(recipe))
            return recipe ~= nil
        end },
        -- host side of the intent: the same call the Fabrication UI makes (UMG_CraftingUI_RecipeList)
        { check = "host_craft_changes_items", timeout = 10, cond = function()
            before = owned()
            local ok = craft()
            local d = diff(before, owned())
            T.log("PT|info craft %s success=%s diff=%s", T.name(recipe), tostring(ok), table.concat(d, " "))
            return ok == true and #d > 0
        end },
        { run = function()
            if M == "noblock" then return end
            RegisterHook(EXEC, function(self, ctx, rec, inputs, outputs)
                blocked = blocked + 1
                inputs:get():Empty(); outputs:get():Empty()
            end)
        end },
        -- guest side: the same call with the block installed must leave every container unchanged
        { check = "guest_block_keeps_items", timeout = 10, cond = function()
            before = owned()
            local ok = craft()
            local d = diff(before, owned())
            T.log("PT|info blocked craft success=%s diff=%s hookCalls=%d", tostring(ok), table.concat(d, " "), blocked)
            return #d == 0 and blocked > 0
        end },
    }
end
