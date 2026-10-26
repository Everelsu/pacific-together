-- A guest joins a big save and stays (msg.cpp pacing). Hand playtest 2026-10-24 on the owner's save (a storage of 4165 items, a full
-- trunk, a long progression): at the guest's hello every module sent its full state in one frame, the host's channel to the guest
-- passed UE's 256 outstanding reliable bunches ("Reliable buffer overflow ... ClientMessage") and the host closed the connection;
-- the guest rejoined every ~70 s, without a body in between.
--   the guest joins, the host spawns its character once, and for 150 s the same controller and character stay
-- Run: tools/run-test.ps1 -Scenario bigjoin -Fixture garage -Headless      Mutation nopace: every chunk at once again (checks FAIL).
-- Needs a big garage save (the owner's); a small one never overflowed.
local UEHelpers = require("UEHelpers")

return function(T)
    local L = require("scenarios.sessionlib")(T)
    local HOLD = 150

    if T.ROLE == "host" then
        local pc, since, lost = nil, nil, false
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        -- before the guest arrives: the host faces +X with the pneumatic storage (BP_Garage_AutoStoreVacuum) 150 uu to its right,
        -- the old spawn spot; only behind it is free (garage map, traced live 2026-10-24)
        add({ run = function() T.myPawn():K2_SetActorLocationAndRotation({ X = -489, Y = 185, Z = 112 }, { Pitch = 0, Yaw = 0, Roll = 0 }, false, {}, true) end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function()
            local c = L.guestChar()
            if c then pc, since = L.remotePCs()[1]:GetAddress(), os.clock() end
            return c ~= nil
        end })
        -- the spawn spot (session.lua): in sight of the host, not inside a station (playtest 2026-10-24: in the pneumatic storage)
        add({ check = "guest_spawned_in_sight", timeout = 5, cond = function()
            local me, g = T.myPawn(), L.guestChar()
            local a, b, hit = me:K2_GetActorLocation(), g:K2_GetActorLocation(), {}
            a.Z, b.Z = a.Z + 50, b.Z + 50
            local blocked = UEHelpers.GetKismetSystemLibrary():LineTraceSingle(me, a, b, 0, false, { me, g }, 0, hit, true,
                { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
            T.log("PT|info bigjoin guest spawned %.0f uu from the host, line blocked=%s", math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2), tostring(blocked))
            return not blocked
        end })
        add({ check = "guest_stays_connected", timeout = HOLD + 30, cond = function()
            local now = L.remotePCs()[1]
            if not (now and now:GetAddress() == pc and L.guestChar()) then
                if not lost then T.log("PT|info bigjoin guest lost after %.0f s", os.clock() - since) end
                lost = true
            end
            return not lost and os.clock() - since >= HOLD
        end })
        add({ run = function() T.log("PT|info bigjoin host msg %s", PTNative_MsgStats()) end })
        return steps
    end

    local me, since, lost = nil, nil, false
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_garage", timeout = 400, cond = function()
            local ok = T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR
            if ok then me, since = T.myPawn():GetAddress(), os.clock() end
            return ok
        end },
        { check = "guest_keeps_its_body", timeout = HOLD + 30, cond = function()
            local p = T.myPawn()
            if not (T.netMode() == "client" and p and p:GetAddress() == me) then
                if not lost then T.log("PT|info bigjoin guest lost its body after %.0f s", os.clock() - since) end
                lost = true
            end
            return not lost and os.clock() - since >= HOLD
        end },
        { run = function() T.log("PT|info bigjoin guest msg %s", PTNative_MsgStats()) end },
    }
end
