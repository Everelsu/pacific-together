-- Map doors (leveldoors.lua): hand playtest 2026-10-24, the guest's garage doors still had the padlocks the host had broken in its save
-- and stood shut where the host's were open (the guest walked through a door it saw closed).
--   at start     every map door of the guest (state, padlock) is the host's: the guest's fresh game has the padlocks, the host's
--                save has them broken
--   guest press  the guest presses E on the basement door: the host's door moves, the guest's follows
--   host press   the host presses it back: the guest's follows
-- Run: tools/run-test.ps1 -Scenario leveldoors -Fixture garage -Headless      Mutation noleveldoors: the module is inert (checks FAIL).
-- Needs a garage save with broken padlocks (the guest's fresh game has 5 locked doors). The guest breaking a lock the host still has
-- (g.ldoor.unlock) is not covered: such a save had none.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local RF_WasLoaded = 0x00080000
    local BASEMENT = "Garage_Mission:BP_Door_Single_Basement"
    local function locked(d) local r = {}; d.BP_LockedComponent:IsLocked(r); return r.Locked and 1 or 0 end
    -- the doors live in sublevels (Garage_Art, Garage_Mission), not in the persistent world T.inWorld checks
    local function doors()
        local r = {}
        for _, c in ipairs({ "BP_Door_Single_C", "BP_Door_Sliding_Single_C" }) do
            for _, d in ipairs(FindAllOf(c) or {}) do
                if d:IsValid() and d:HasAnyFlags(RF_WasLoaded) and not d:GetFullName():find("/Engine/Transient", 1, true) then
                    r[d:GetOuter():GetOuter():GetFName():ToString() .. ":" .. d:GetFName():ToString()] = d
                end
            end
        end
        return r
    end
    local function door(k) return doors()[k] end
    local function list()
        local l = {}
        for k, d in pairs(doors()) do l[#l + 1] = string.format("%s %d %d", k, d.CurrentState, locked(d)) end
        table.sort(l)
        return table.concat(l, ";")
    end
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
        local function toGuest(k, v) PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), k, v or "") end
        local before
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "host_basement_unlocked", timeout = 10, cond = function() T.log("PT|info doors host %s", list()); return door(BASEMENT) ~= nil and locked(door(BASEMENT)) == 0 end })
        add({ check = "guest_doors_match_host_at_start", timeout = 40, cond = function() return g("t.doors") == list() end })
        add({ run = function() before = door(BASEMENT).CurrentState; toGuest("t.press", BASEMENT) end })
        add({ check = "guest_press_moves_host_basement", timeout = 20, cond = function() return door(BASEMENT).CurrentState ~= before end })
        add({ check = "guest_basement_follows_its_press", timeout = 20, cond = function() return g("t.doors") == list() end })
        add({ wait = 3 })
        add({ run = function() before = door(BASEMENT).CurrentState; local d = door(BASEMENT); d.Highlight:InteractPressed(nil); d.Highlight:InteractReleased(nil) end })
        add({ check = "host_press_moves_host_basement", timeout = 10, cond = function() return door(BASEMENT).CurrentState ~= before end })
        add({ check = "guest_basement_follows_host_press", timeout = 20, cond = function() T.log("PT|info doors end host %s guest %s", list(), tostring(g("t.doors"))); return g("t.doors") == list() end })
        add({ run = function() toGuest("t.done") end })
        add({ wait = 3 })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    local pressed
    add({ check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end })
    add({ check = "guest_reports", timeout = 600, cond = function()
        PTNative_MsgToHost(T.localPC():GetAddress(), "t.doors", list())
        local p = g("t.press")
        if p and p ~= pressed then
            pressed = p
            local d = door(p)
            if d then d.Highlight:InteractPressed(T.myPawn()); d.Highlight:InteractReleased(T.myPawn()) end
        end
        return g("t.done") ~= nil
    end })
    return steps
end
