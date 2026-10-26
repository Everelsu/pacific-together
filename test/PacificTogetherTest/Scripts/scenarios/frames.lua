-- Picture frames (loot.lua shares the garage containers Stations.Install.Mount.NN): playtest 2026-10-24, the host's frames held neon
-- signs, posters and trophies, the guest's stood empty.
--   at start     every frame of the guest holds what the host's holds
--   guest puts   the guest puts a neon sign into an empty frame: the host's frame gets it
-- Run: tools/run-test.ps1 -Scenario frames -Fixture garage -Headless      Mutation noframes: frames are left out (checks FAIL).
-- Needs a garage save with some frames filled and one empty (the contributor's save: 16 of 30 filled).
local UEHelpers = require("UEHelpers")

return function(T)
    local L = require("scenarios.sessionlib")(T)
    local SIGN = "/Game/Gameplay/Inventory/Items/Garage/Cosmetic/Signs/Neon/RadiusMotors/IA_Garage_Cosmetic_Signs_Neon_RadiusMotors_01.IA_Garage_Cosmetic_Signs_Neon_RadiusMotors_01"
    local function frames()
        local r = {}
        local m = T.first("BP_InventoryManager_C")
        if not m then return r end
        m.Inventories_Garage:ForEach(function(k, v)
            local tag = k:get().TagName:ToString()
            if tag:find("^Stations%.Install%.Mount%.") then r[tag] = v:get() end
        end)
        return r
    end
    local function list()
        local l = {}
        for tag, c in pairs(frames()) do
            local items, names = {}, {}
            if c:IsValid() then c:GetAllItems(items) end
            for _, it in ipairs(items) do names[#names + 1] = it:get().Archetype:GetFName():ToString() end
            table.sort(names)
            l[#l + 1] = tag .. "=" .. table.concat(names, ",")
        end
        table.sort(l)
        return table.concat(l, ";")
    end
    local function filled(s) local n = 0; for _ in s:gmatch("=[^;,]") do n = n + 1 end; return n end
    local got = {}
    local function g(kind)
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
        local empty
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "host_has_filled_and_empty_frames", timeout = 10, cond = function()
            local s = list()
            T.log("PT|info frames host %d filled: %s", filled(s), s)
            empty = s:match("(Stations%.Install%.Mount%.%d+)=;") or s:match("(Stations%.Install%.Mount%.%d+)=$")
            return filled(s) > 0 and empty ~= nil
        end })
        add({ check = "guest_frames_match_host", timeout = 150, cond = function() return g("t.frames") == list() end })
        add({ run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.put", empty) end })
        add({ check = "guest_put_reaches_host", timeout = 30, cond = function()
            local c = frames()[empty]
            return c and c:IsValid() and c:GetNumItems() > 0
        end })
        add({ check = "frames_match_in_the_end", timeout = 30, cond = function() return g("t.frames") == list() end })
        add({ run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.done", "") end })
        add({ wait = 3 })
        return steps
    end

    local put
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end },
        { check = "guest_reports", timeout = 600, cond = function()
            PTNative_MsgToHost(T.localPC():GetAddress(), "t.frames", list())
            local tag = g("t.put")
            if tag and tag ~= put then
                put = tag
                local c, a = frames()[tag], StaticFindObject(SIGN)
                if not a:IsValid() then pcall(LoadAsset, SIGN); a = StaticFindObject(SIGN) end
                if c and a:IsValid() then
                    c:AddItem(StaticFindObject("/Script/PenDriverInventory.Default__InventoryBlueprintLibrary"):CreateItemInstance(UEHelpers.GetWorld(), a, 0), true)
                end
            end
            return g("t.done") ~= nil
        end },
    }
end
