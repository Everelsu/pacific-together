-- PT1 bug B: the guest crafts at the workbench (the game's own "Craft Recipe Asset" on the guest's side, garage materials
-- synced from the host). Exactly one result, kept through every sync cycle: 60 s in the garage, across the host's travel to
-- the zone (the backpack is written back from the host's record), and 60 s more in the zone.
-- Run: tools/run-test.ps1 -Scenario guestcraft -Fixture garage -Headless
-- Mutation nocraftfix: the fix is off.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local RECIPE = "/Game/Gameplay/Inventory/Items/Tools/FixStatusEffect/FixElectronic/CR_Tool_Target_FixElectronics.CR_Tool_Target_FixElectronics"
    local function im() return T.first("BP_InventoryManager_C") end
    local function crafted() -- every FixElectronics tool the player owns (backpack, hand, garage, car)
        local o, n = {}, 0
        im():GetOwnedItems(true, true, true, o)
        for _, e in ipairs(o) do
            local a = e:get().Archetype
            if a:IsValid() and a:GetFName():ToString():find("IA_Tool_Target_FixElectronics", 1, true) then n = n + 1 end
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
    local function inZone() return L.gameplay(T.map()) and T.map() ~= "RB_Garage" end
    local function sceneReady() return T.myPawn() ~= nil and T.first("BP_PlayerCarNew_C") ~= nil end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "host_guest_crafted", timeout = 200, cond = function() return has("t.crafted") end })
        add({ check = "host_never_gets_the_product", timeout = 70, cond = L.holds(65, function() return crafted() == 0 end) })
        add({ run = function() StaticFindObject("/Game/Systems/ScriptingLibraries/BFL_ProgressionHelpers.Default__BFL_ProgressionHelpers_C"):TravelToNextLeg(T.world()) end })
        add({ check = "host_in_zone", timeout = 240, cond = function() return inZone() and sceneReady() end })
        add({ check = "host_guest_back_zone", timeout = 300, cond = function() return L.guestChar() ~= nil end })
        add({ check = "host_waits_for_guest", timeout = 200, cond = function() return has("t.done") end })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    local mark
    add({ check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end })
    add({ wait = 15 }) -- the host's garage arrives
    add({ run = function()
        local m = im()
        m:SetActiveTier(3, true, true) -- what the workbench sets
        local o = {}
        m["Craft Recipe Asset"](m, StaticFindObject(RECIPE), true, true, o)
        T.log("PT|info guest craft success=%s", tostring(o.Success))
    end })
    add({ check = "guest_has_one", timeout = 5, cond = function() return crafted() == 1 end })
    add({ run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.crafted", "") end })
    add({ check = "guest_still_one_after_60s_in_garage", timeout = 80, cond = L.holds(60, function() return crafted() == 1 end) })
    add({ run = function() mark = L.mark() end })
    add({ check = "guest_reloaded_by_host_travel", timeout = 240, cond = function() return L.reloadedNoMenu(mark) end })
    add({ check = "client_in_zone", timeout = 300, cond = function() return T.netMode() == "client" and inZone() and T.cls(T.myPawn()) == T.CHAR end })
    add({ check = "guest_one_after_travel_and_60s", timeout = 120, cond = L.holds(60, function() return crafted() == 1 end) })
    add({ run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.done", "") end })
    return steps
end
