-- PT1 bug B (playtest: "the crafted tool was duped"): the guest crafts a tool at the workbench (the game's own "Craft Recipe Asset"
-- on the guest's side, garage materials synced from the host) and drops it from the inventory menu (the call the menu's drop makes:
-- BFL_InventorySlotUtils."Spawn Item Player Drop"). After that the guest owns none, exactly one tool lies in the world on each side
-- (60 s, through the backpack sync), the host picks it up, and the guest still owns none and has no copy left on its ground.
-- Run: tools/run-test.ps1 -Scenario guestcraft -Fixture garage -Headless
-- Mutation nodropfix: loot.lua keeps the guest's own dropped actor next to the host's copy.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local RECIPE = "/Game/Gameplay/Inventory/Items/Tools/FixStatusEffect/FixElectronic/CR_Tool_Target_FixElectronics.CR_Tool_Target_FixElectronics"
    local function im() return T.first("BP_InventoryManager_C") end
    local function owned() -- every FixElectronics tool the player owns (backpack, hand, garage, car)
        local o, n = {}, 0
        im():GetOwnedItems(true, true, true, o)
        for _, e in ipairs(o) do
            local a = e:get().Archetype
            if a:IsValid() and a:GetFName():ToString():find("IA_Tool_Target_FixElectronics", 1, true) then n = n + 1 end
        end
        return n
    end
    local function worldTools() -- tools lying in this side's world
        local n = 0
        for _, w in ipairs(FindAllOf("BP_WorldItem_C") or {}) do
            if w:IsValid() and not w:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) then
                local ok, a = pcall(function() return w.Instance.Archetype:GetFName():ToString() end)
                if ok and a:find("IA_Tool_Target_FixElectronics", 1, true) then n = n + 1 end
            end
        end
        return n
    end
    local got = {}
    local function has(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind] ~= nil
    end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "host_guest_dropped", timeout = 200, cond = function() return has("t.dropped") end })
        add({ check = "host_one_world_tool_for_60s", timeout = 90, cond = L.holds(60, function() return worldTools() == 1 end) })
        add({ check = "host_guest_stable_60s", timeout = 120, cond = function() return has("t.stable") end })
        add({ check = "host_owns_none", timeout = 2, cond = function() return owned() == 0 end })
        add({ run = function()
            for _, w in ipairs(FindAllOf("BP_WorldItem_C") or {}) do
                local ok, a = pcall(function() return w.Instance.Archetype:GetFName():ToString() end)
                if w:IsValid() and ok and a:find("IA_Tool_Target_FixElectronics", 1, true) then
                    T.log("PT|info host picks up %s ok=%s", T.name(w), tostring(pcall(function() local c = T.first("BP_MainCharacterManager_C").CharacterActor; c["Pickup Actor"](c, w, false) end)))
                    break
                end
            end
        end })
        add({ check = "host_owns_one_after_pickup", timeout = 10, cond = function() return owned() == 1 end })
        add({ run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.picked", "") end })
        add({ check = "host_still_one_owned_and_no_world_tool", timeout = 40, cond = L.holds(30, function() return owned() == 1 and worldTools() == 0 end) })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    add({ check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end })
    add({ wait = 15 }) -- the host's garage arrives
    add({ run = function()
        local m = im()
        m:SetActiveTier(3, true, true) -- what the workbench sets
        local o = {}
        m["Craft Recipe Asset"](m, StaticFindObject(RECIPE), true, true, o)
        T.log("PT|info guest craft success=%s", tostring(o.Success))
    end })
    add({ check = "guest_has_one", timeout = 5, cond = function() return owned() == 1 end })
    add({ wait = 10 }) -- a backpack sync with the tool in it
    add({ run = function()
        local m, it = im(), nil
        local c = m.Inventory_Player
        for i = 0, c:GetNumSlots() - 1 do
            local s = c:GetSlot(i)
            if s:IsValid() and s:GetNumItems() > 0 then it = s:GetItem(0) end
        end
        local u = FindObject("BFL_InventorySlotUtils_C", "Default__BFL_InventorySlotUtils_C")
        local s, w = {}, {}
        u["Spawn Item Player Drop"](u, it, true, m, s, w)
        T.log("PT|info guest dropped the tool")
        PTNative_MsgToHost(T.localPC():GetAddress(), "t.dropped", "")
    end })
    add({ check = "guest_owns_none_after_drop", timeout = 5, cond = function() return owned() == 0 end })
    add({ check = "guest_owns_none_and_one_world_tool_for_60s", timeout = 90, cond = L.holds(60, function()
        local o, w = owned(), worldTools()
        if o ~= 0 or w ~= 1 then T.log("PT|info guest owned=%d worldTools=%d", o, w) end
        return o == 0 and w == 1
    end) })
    add({ run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.stable", "") end })
    add({ check = "guest_host_picked", timeout = 120, cond = function() return has("t.picked") end })
    add({ check = "guest_still_owns_none_and_copy_gone", timeout = 40, cond = L.holds(30, function()
        local o, w = owned(), worldTools()
        if o ~= 0 or w ~= 0 then T.log("PT|info guest after host pickup owned=%d worldTools=%d", o, w) end
        return o == 0 and w == 0
    end) })
    return steps
end
