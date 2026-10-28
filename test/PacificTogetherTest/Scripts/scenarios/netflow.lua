-- Local hand play 2026-10-24: joining with the owner's big save, the host's lists for the guest filled the guest controller's
-- reliable buffer and the engine closed the connection ("Reliable buffer overflow", guest back in the menu). The main mod's
-- host bursts 400 messages of 1 KB at once (net.lua, PT_SCENARIO=netflow); its flow control must deliver all of them and keep
-- the guest connected. The guest's main mod reports its count to the host's test mod (t.netflow).
-- Run: tools/run-test.ps1 -Scenario netflow -Fixture garage -Headless      Mutation: noflow (no flow control)
return function(T)
    local L = require("scenarios.sessionlib")(T)
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
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "guest_got_all_400", timeout = 120, cond = function() return has("t.netflow") end })
        add({ check = "host_guest_still_connected", timeout = 30, cond = L.holds(10, function() return #L.remotePCs() == 1 end) })
        return steps
    end
    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    add({ check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end })
    add({ check = "guest_still_connected", timeout = 90, cond = L.holds(45, function() return T.netMode() == "client" and T.map() == "RB_Garage" end) })
    return steps
end
