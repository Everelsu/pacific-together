-- Crash damage for a seated guest (anomalies.lua, from PDCoopNet). The guest gets in through the door press (real input); the host's
-- test then runs the car's damage controller's LimitDamageToPlayerOverTime with impact messages, as a crash does: the guest's own
-- health must drop. The garage deals no player damage, so the runner sets PT_CRASH_GARAGE for this scenario only.
-- Run: tools/run-test.ps1 -Scenario carcrash -Fixture garage -Headless      Mutation nocrash: nothing is forwarded (check FAILS).
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local KML = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local got = {}
    local function g(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind]
    end
    local function theCar()
        for _, c in ipairs(FindAllOf("BP_PlayerCarNew_C") or {}) do
            local l = c:IsValid() and c:K2_GetActorLocation()
            if l and not (l.X == 0 and l.Y == 0 and l.Z == 0) and (T.ROLE == "host" or c.Role ~= 3) then return c end
        end
    end
    local function attached(c) local p = c:GetAttachParentActor(); return p:IsValid() and T.cls(p) == "BP_PlayerCarNew_C" end
    local function hp() return T.first("BP_ResourceManager_C").PlayerHealth.Current end

    if T.ROLE == "host" then
        local steps, hp0, host0 = {}, nil, nil
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 10 })
        add({ run = function()
            local c = theCar()
            local w = KML:TransformLocation(c:GetTransform(), { X = 131, Y = -200, Z = 0 })
            L.guestChar():K2_HandleSetCharacterLocation({ Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = w.X, Y = w.Y, Z = c:K2_GetActorLocation().Z + 10 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false, false)
            PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.enter", "1")
        end })
        add({ check = "guest_seated", timeout = 120, cond = function() local x = L.guestChar(); return x ~= nil and attached(x) end })
        add({ wait = 3 })
        add({ check = "guest_reports_health", timeout = 20, cond = function() hp0 = tonumber(g("t.hp") or ""); return hp0 ~= nil and hp0 > 20 end })
        add({ run = function()
            host0 = hp()
            local MSG = "/Game/Systems/Messages/MSG_Damage_Physical_Impact.MSG_Damage_Physical_Impact_C"
            if not StaticFindObject(MSG):IsValid() then LoadAsset(MSG) end
            local ctl, ms = theCar().DamageDispatchController, T.first("MessageSystem")
            for i = 1, 10 do
                local m = StaticConstructObject(StaticFindObject(MSG), ms)
                m.Damage = 2
                local out = {}
                local ok, err = pcall(function() ctl:LimitDamageToPlayerOverTime(m, 2.0, out) end)
                if i == 1 then T.log("PT|info crash call ok=%s %s out=%s", tostring(ok), tostring(err or ""), tostring(out.UpdatedDamage)) end
            end
            T.log("PT|info crash sent: guest hp %.1f host hp %.1f", hp0, host0)
        end })
        add({ check = "guest_hurt_by_crash", timeout = 20, cond = function()
            local now = tonumber(g("t.hp") or "") or hp0
            return now < hp0 - 0.3
        end })
        add({ run = function() T.log("PT|info guest hp %s -> %s, host %.1f -> %.1f", tostring(hp0), tostring(g("t.hp")), host0, hp()) end })
        add({ run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.done", "1") end })
        add({ wait = 3 })
        return steps
    end

    local id
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end },
        { check = "guest_told_enter", timeout = 240, cond = function() return g("t.enter") ~= nil end },
        { wait = 2 },
        { run = function() id = T.act_begin("door_press", {}) end },
        { check = "guest_door_press", timeout = 90, cond = function() local d, _, ok = T.act_done(id); return d and ok end },
        { check = "guest_reports", timeout = 600, cond = function()
            PTNative_MsgToHost(T.localPC():GetAddress(), "t.hp", string.format("%.2f", hp()))
            return g("t.done") ~= nil
        end },
    }
end
