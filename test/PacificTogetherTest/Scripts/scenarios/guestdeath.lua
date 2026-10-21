-- PT1 bug A: the guest dies holding a crafted item and materials: the death crate has exactly those items (the crafted item
-- itself, not its ingredients), no ingredients drop in the world on either side, the guest's backpack is empty.
-- Run: tools/run-test.ps1 -Scenario guestdeath -Fixture zone -Headless
-- Mutation nodeathfix: the fix is off.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local mapName = "Rural_Forest_Radio_Scylla_02"
    local STEEL = "/Game/Gameplay/Inventory/Items/Resources/Basic/RawSteel/IA_Resource_Raw_Scrap_Steel.IA_Resource_Raw_Scrap_Steel"
    local RECIPE = "/Game/Gameplay/Inventory/Items/Tools/FixStatusEffect/FixElectronic/CR_Tool_Target_FixElectronics.CR_Tool_Target_FixElectronics"
    local function alive(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
    local function im() return T.first("BP_InventoryManager_C") end
    local function lib() return StaticFindObject("/Script/PenDriverInventory.Default__InventoryBlueprintLibrary") end
    local function counts(containers) -- "name=n;name=n" sorted
        local t = {}
        for _, c in ipairs(containers) do
            for i = 0, c:GetNumSlots() - 1 do
                local s = c:GetSlot(i)
                if s:IsValid() and s:GetNumItems() > 0 then
                    local k = s:GetCurrentArchetype():GetFName():ToString()
                    t[k] = (t[k] or 0) + s:GetNumItems()
                end
            end
        end
        local r = {}
        for k, v in pairs(t) do r[#r + 1] = k .. "=" .. v end
        table.sort(r)
        return table.concat(r, ";")
    end
    local function carried() local m = im(); return counts({ m.Inventory_Player, m.Inventory_PlayerHand }) end
    local function worldItems()
        local n = 0
        for _, a in ipairs(FindAllOf("ItemWorldManifestation") or {}) do if alive(a) then n = n + 1 end end
        return n
    end
    local last
    local function bagCounts(want) -- contents of the crate that matches want, else of the last non-empty crate
        for _, a in ipairs(FindAllOf("BP_Lootable_Base_C") or {}) do
            if alive(a) and a:GetClass():GetFName():ToString():find("Crate_Large", 1, true) and a.InventoryContainer:GetNumItems() > 0 then
                local c = counts({ a.InventoryContainer })
                last = c
                if c == want then return c end
            end
        end
        return last
    end

    local got = {}
    local function has(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind]
    end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local base
        for _, s in ipairs(T.loadFixture("zone")) do add(s) end
        add({ check = "host_listen", timeout = 120, cond = function() return T.netMode() == "listen" and T.listening() and T.map() == mapName end })
        add({ check = "host_guest_in", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "host_got_snapshot", timeout = 200, cond = function() return has("t.snap") ~= nil end })
        add({ wait = 3 })
        add({ run = function() base = worldItems(); T.log("PT|info host world items %d, guest holds %s", base, got["t.snap"]) end })
        add({ check = "host_death_crate_has_exactly_the_guest_items", timeout = 90, cond = function()
            local b = bagCounts(got["t.snap"])
            if b then T.log("PT|info crate %s", b) end
            return b == got["t.snap"]
        end })
        add({ wait = 12 })
        add({ check = "host_no_dropped_materials", timeout = 5, cond = function() return worldItems() == base end })
        add({ check = "host_crate_still_exact", timeout = 5, cond = function() return bagCounts(got["t.snap"]) == got["t.snap"] end })
        add({ check = "host_got_snapshot2", timeout = 200, cond = function() return has("t.snap2") ~= nil end })
        add({ check = "host_kill_crate_has_exactly_the_guest_items", timeout = 90, cond = function() return bagCounts(got["t.snap2"]) == got["t.snap2"] end })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    local snap, base
    add({ check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == mapName and T.cls(T.myPawn()) == T.CHAR end })
    add({ wait = 12 })
    add({ run = function()
        local m = im()
        m:SetActiveTier(3, true, true)
        local r = StaticFindObject(RECIPE)
        local comps = r:GetRecipeRaw().Components
        for i = 1, #comps do -- the materials the craft eats, in the backpack
            local it = comps[i]:get().Item
            if it.Archetype:IsValid() then for _ = 1, it.Quantity do m.Inventory_Player:AddItem(lib():CreateItemInstance(T.world(), it.Archetype, 0), true) end end
        end
        local o = {}
        m["Craft Recipe Asset"](m, r, true, true, o)
        T.log("PT|info guest craft success=%s", tostring(o.Success))
        local a = StaticFindObject(STEEL)
        for _ = 1, 7 do m.Inventory_Player:AddItem(lib():CreateItemInstance(T.world(), a, 0), true) end
    end })
    add({ check = "guest_holds_crafted_item_and_steel", timeout = 5, cond = function()
        local c = carried()
        return c:find("FixElectronics=1", 1, true) ~= nil and c:find("Scrap_Steel=7", 1, true) ~= nil
    end })
    add({ wait = 15 }) -- the host stores it
    add({ run = function()
        snap = carried(); base = worldItems()
        T.log("PT|info guest holds %s world items %d", snap, base)
        PTNative_MsgToHost(T.localPC():GetAddress(), "t.snap", snap)
    end })
    add({ wait = 8 })
    add({ run = function()
        local h = T.first("BP_ResourceManager_C").PlayerHealth
        h:Adjust(T.first("BP_ResourceManager_C"), -h.Maximum) -- the game's own sink for every damage message
    end })
    add({ check = "guest_backpack_emptied", timeout = 30, cond = function() return carried() == "" end })
    add({ wait = 15 })
    add({ check = "guest_backpack_still_empty", timeout = 5, cond = function() return carried() == "" end })
    add({ check = "guest_no_dropped_materials", timeout = 5, cond = function() return worldItems() == base end })
    -- second death: the game's own, BP_MainCharacterManager:KillPlayer (what a crushing door or CheckForGameOver calls)
    add({ check = "guest_alive_again", timeout = 30, cond = function() return T.first("BP_MainCharacterManager_C"):IsPlayerAlive() end })
    add({ run = function()
        local m = im()
        local r = StaticFindObject(RECIPE)
        local comps = r:GetRecipeRaw().Components
        for i = 1, #comps do
            local it = comps[i]:get().Item
            if it.Archetype:IsValid() then for _ = 1, it.Quantity do m.Inventory_Player:AddItem(lib():CreateItemInstance(T.world(), it.Archetype, 0), true) end end
        end
        local o = {}
        m["Craft Recipe Asset"](m, r, true, true, o)
        local a = StaticFindObject(STEEL)
        for _ = 1, 5 do m.Inventory_Player:AddItem(lib():CreateItemInstance(T.world(), a, 0), true) end
    end })
    add({ check = "guest_holds_again", timeout = 5, cond = function() local c = carried(); return c:find("FixElectronics=1", 1, true) ~= nil and c:find("Scrap_Steel=5", 1, true) ~= nil end })
    add({ wait = 15 })
    add({ run = function()
        snap = carried(); base = worldItems()
        PTNative_MsgToHost(T.localPC():GetAddress(), "t.snap2", snap)
    end })
    add({ wait = 8 })
    add({ run = function() T.first("BP_MainCharacterManager_C"):KillPlayer() end })
    add({ wait = 20 })
    add({ check = "kill_guest_backpack_emptied", timeout = 10, cond = function() return carried() == "" end })
    add({ check = "kill_guest_alive_again", timeout = 30, cond = function() return T.first("BP_MainCharacterManager_C"):IsPlayerAlive() end })
    add({ check = "kill_guest_still_in_zone", timeout = 20, cond = L.holds(10, function() return T.netMode() == "client" and T.map() == mapName end) })
    return steps
end
