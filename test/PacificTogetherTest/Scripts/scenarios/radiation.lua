-- pt3 #8: radiation hurts the guest. The zone's radiated areas (BP_VolCascade_Radiation_C) are spawned at runtime on the host only, so the
-- guest's game saw no radiation anywhere. The host puts the guest inside one of its radiating volumes; the guest's own game (hazard manager
-- "is radiation greater at point") must see it there and its health must fall.
-- Run: tools/run-test.ps1 -Scenario radiation -Fixture zone -Headless
-- Then the host's volume goes (Hot Dust gone, pt8 2026-10-25): the guest's copy must stop radiating too.
-- Mutation norad: radiation.lua is off (the bug): the guest sees no radiation, its health stays.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local mapName = "Rural_Forest_Radio_Scylla_02"
    local got = {}
    local function drain()
        while true do
            local kind, data = PTNative_MsgPoll("t.")
            if not kind then return end
            got[kind] = data
        end
    end
    local function radiating(x, y, z) -- the game's own question for the player's spot
        local hm, o = T.first("BP_HazardManager_C"), {}
        hm["Is Radiation Greater at Point"](hm, { X = x, Y = y, Z = z }, 0.0, o)
        return o.TRUE == true
    end
    local function hp() local rm = T.first("BP_ResourceManager_C"); return rm.PlayerHealth.Current end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local pt
        for _, s in ipairs(T.loadFixture("zone")) do add(s) end
        add({ check = "host_listen", timeout = 120, cond = function() return T.netMode() == "listen" and T.listening() and T.map() == mapName end })
        add({ check = "host_guest_in", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 10 })
        add({ run = function()
            local best
            for _, o in ipairs(FindAllOf("BP_VolCascade_Radiation_C") or {}) do
                if o:IsValid() and o["Max Local Radiation"] > 0.2 and (not best or o["Max Local Radiation"] > best["Max Local Radiation"]) then best = o end
            end
            assert(best, "no radiating volume on the host")
            local l = best:K2_GetActorLocation()
            pt = { x = l.X, y = l.Y, z = l.Z }
            T.log("PT|info radiation point %.0f %.0f %.0f max=%.2f", l.X, l.Y, l.Z, best["Max Local Radiation"])
            PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.radpt", string.format("%f %f %f", l.X, l.Y, l.Z))
        end })
        add({ check = "guest_sees_radiation", timeout = 60, cond = function() drain(); return got["t.rad"] == "1" end })
        add({ run = function()
            L.guestChar():K2_HandleSetCharacterLocation({ Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = pt.x, Y = pt.y, Z = pt.z + 150 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false, false)
        end })
        add({ check = "guest_health_falls", timeout = 90, cond = function() drain(); return got["t.hurt"] == "1" end })
        add({ run = function()
            for _, o in ipairs(FindAllOf("BP_VolCascade_Radiation_C") or {}) do
                local l = o:IsValid() and o:K2_GetActorLocation()
                if l and math.abs(l.X - pt.x) < 1 and math.abs(l.Y - pt.y) < 1 then o:K2_DestroyActor() end
            end
        end })
        add({ check = "guest_radiation_gone_with_host", timeout = 30, cond = function() drain(); return got["t.radoff"] == "1" end })
        add({ wait = 3 })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    local pt, hp0
    add({ check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == mapName and T.cls(T.myPawn()) == T.CHAR end })
    add({ check = "guest_got_point", timeout = 120, cond = function()
        while true do
            local kind, data = PTNative_MsgPoll("t.")
            if not kind then break end
            if kind == "t.radpt" then pt = {}; for v in data:gmatch("%S+") do pt[#pt + 1] = tonumber(v) end end
        end
        return pt ~= nil
    end })
    add({ check = "guest_game_sees_radiation", timeout = 60, cond = function()
        local ok = radiating(pt[1], pt[2], pt[3])
        T.log("PT|info guest radiation at the point: %s", tostring(ok))
        if ok then PTNative_MsgToHost(T.localPC():GetAddress(), "t.rad", "1"); hp0 = hp() end
        return ok
    end })
    add({ check = "guest_health_fell", timeout = 90, cond = function()
        local h = hp()
        T.log("PT|info guest health %.2f (was %.2f)", h, hp0)
        local ok = h < hp0 - 1.5
        if ok then PTNative_MsgToHost(T.localPC():GetAddress(), "t.hurt", "1") end
        return ok
    end })
    add({ check = "guest_radiation_off", timeout = 60, cond = function()
        local ok = not radiating(pt[1], pt[2], pt[3])
        if ok then PTNative_MsgToHost(T.localPC():GetAddress(), "t.radoff", "1") end
        return ok
    end })
    add({ wait = 5 })
    return steps
end
