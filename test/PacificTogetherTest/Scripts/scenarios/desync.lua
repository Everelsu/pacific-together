-- Position desync watch (desync.lua). Hand playtest 2026-10-24: the host saw the guest at a door, the guest was already in the room.
-- Here the host's copy of the guest gets no movement mode and the engine's correction off (the copy stands, nothing sends the guest
-- back; a movement tick off alone is no fault: the engine still runs the guest's moves), the guest walks for 3 s: the copy and the
-- guest must agree again within 15 s (the copy repaired, or the guest put back).
-- Run: tools/run-test.ps1 -Scenario desync -Fixture garage -Headless      Mutation nodesync: the watch is off (check FAILS).
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
    local function xyz(s) local x, y, z = (s or ""):match("^(-?[%d.]+),(-?[%d.]+),(-?[%d.]+)$"); return x and { X = tonumber(x), Y = tonumber(y), Z = tonumber(z) } end
    local function d(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2) end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local function toGuest(k, v) PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), k, v or "") end
        local function off()
            local gc, at = L.guestChar(), xyz(g("t.pos"))
            if not (gc and at) then return 1e9 end
            return d(gc:K2_GetActorLocation(), at)
        end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "agree_before", timeout = 30, cond = function() return off() < 50 end })
        add({ run = function()
            local cm = L.guestChar().CharacterMovement
            cm.bIgnoreClientMovementErrorChecksAndCorrection = true
            cm:DisableMovement()
            toGuest("t.walk", "1")
        end })
        add({ check = "copy_falls_behind", timeout = 10, cond = function() local o = off(); T.log("PT|info desync off %.0f", o); return o > 200 end })
        add({ wait = 4 })
        add({ check = "agree_again", timeout = 15, cond = function() local o = off(); T.log("PT|info desync off %.0f", o); return o < 100 end })
        add({ run = function() toGuest("t.done", "1") end })
        add({ wait = 3 })
        return steps
    end

    local walking = 0
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end },
        { check = "guest_reports", timeout = 600, cond = function()
            local me = T.myPawn()
            local l = me:K2_GetActorLocation()
            PTNative_MsgToHost(T.localPC():GetAddress(), "t.pos", string.format("%.0f,%.0f,%.0f", l.X, l.Y, l.Z))
            if g("t.walk") and walking == 0 then
                local frames = 0
                walking = LoopInGameThreadWithDelay(16, function()
                    frames = frames + 1
                    pcall(function() me:AddMovementInput({ X = 0, Y = 1, Z = 0 }, 1.0, true) end)
                    if frames > 180 then CancelDelayedAction(walking) end
                end)
            end
            return g("t.done") ~= nil
        end },
    }
end
