-- Saturation (net.lua SPEED). Rendered lane 2026-10-24: a burst of our messages saturated the guest's connection, the host sent
-- no actor updates and no move acks for as long as the backlog took to drain (the host stood still on the guest's screen).
-- Here the host sends 1.5 MB of messages and changes its PlayerState score in the same frame: the guest must see the new score
-- within 6 s (at the game's own 100000 the backlog alone is 15 s).
-- Run: tools/run-test.ps1 -Scenario netspeed -Fixture garage -Headless      Mutation oldspeed: the game's own speed (check FAILS).
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local got = {}
    local function g(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind]
    end
    local SCORE = 4242

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "guest_reports_score", timeout = 120, cond = function() return g("t.score") == "0" end })
        add({ run = function()
            local pc = L.remotePCs()[1]
            local blob = string.rep("x", 30000)
            for _ = 1, 50 do PTNative_MsgToGuest(pc:GetAddress(), "t.noise", blob) end
            local ps = T.localPC().PlayerState
            ps.Score = SCORE
            ps:ForceNetUpdate()
        end })
        add({ check = "guest_sees_score_in_6s", timeout = 6, cond = function() return g("t.score") == tostring(SCORE) end })
        add({ run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.done", "1") end })
        add({ wait = 3 })
        return steps
    end

    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end },
        { check = "guest_reports", timeout = 600, cond = function()
            local host = T.otherChar()
            local ps = host and host.PlayerState
            local score = (ps and ps:IsValid()) and string.format("%.0f", ps.Score) or "none"
            PTNative_MsgToHost(T.localPC():GetAddress(), "t.score", score)
            got["t.noise"] = nil
            return g("t.done") ~= nil
        end },
    }
end
