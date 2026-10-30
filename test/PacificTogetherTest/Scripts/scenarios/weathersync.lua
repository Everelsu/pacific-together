-- Weather and time of day: the guest's lighting and weather follow the host (owner hand play 2026-10-24: they differed).
--   guest_sim_linked            the guest's ToD manager has its simulation actor (it lost it: SetupToDSimulationActor ran before the level's actor existed)
--   guest_time_matches          time of day within 0.02 of the host's
--   guest_runs_host_preset      the guest's simulation (the sun, sky and fog) runs the preset the host's manager targets; the host switches it twice,
--                               to a rainy one and back (the guest's sim never heard of the change: its delegate was unbound)
--   guest_precipitation_matches the guest's precipitation follows the host's rain (host > 0.5)
--   guest_ambience_set_up       the guest's ambience manager has its falling-rain, splash and radiation effects (they were never made: the
--                               guest's character came after the manager's setup, so rain showed on the host only; 2026-10-30)
-- Run: tools/run-test.ps1 -Scenario weathersync -Fixture zone|garage (guest_ambience_set_up needs a rendered run; headless it skips) [-Root .. -Port ..]   Mutation nosimlink: the guest relink is off; noambience: no ambience setup.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local slow = (T.MUTATE == "nosimlink") and 0.2 or 1
    local function to(s) return math.max(15, math.floor(s * slow)) end
    local PRE = "/Game/Lighting/TimeOfDay/Blueprints/"
    local RAIN, BACK = PRE .. "ToD_Preset_AcidRain.ToD_Preset_AcidRain_C", PRE .. "ToD_Preset_ForestSullen.ToD_Preset_ForestSullen_C"
    local function tod() return T.first("BP_ToDManager_C") end
    local function simPreset()
        local s = T.first("ToD_Simulation_C")
        return (s and s.CurrentPresetObject:IsValid()) and s.CurrentPresetObject:GetClass():GetFName():ToString() or "none"
    end
    local function read()
        local m, o = tod(), {}
        m["Get Current Time Of Day"](m, o)
        return { tod = o["Returned Time Of Day"], target = m["Target TOD Preset"]:GetFName():ToString(), prec = m.Precipiation, sim = simPreset(),
            linked = m.ToDSimulationActor ~= nil and m.ToDSimulationActor:IsValid() }
    end
    local function ser(r) return string.format("%.5f|%s|%.3f|%s", r.tod, r.target, r.prec, r.sim) end
    local function de(s) local a, b, c, d = s:match("^([^|]*)|([^|]*)|([^|]*)|(.*)$"); return { tod = tonumber(a), target = b, prec = tonumber(c), sim = d } end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture(os.getenv("PT_FIXTURE") or "zone")) do add(s) end
        add({ check = "host_listen", timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ run = function()
            LoopInGameThreadWithDelay(1000, function()
                local g = L.remotePCs()[1]
                if g then pcall(PTNative_MsgToGuest, g:GetAddress(), "t.read", ser(read())) end
            end)
            local m = tod()
            m["Set Current Time Of Day"](m, 0.85)
            m["Set New TOD Target"](m, StaticFindObject(RAIN))
            T.log("PT|info host set time 0.85 and the rainy preset")
        end })
        add({ wait = 45 })
        add({ run = function() local m = tod(); m["Set New TOD Target"](m, StaticFindObject(BACK)); T.log("PT|info host back to the first preset") end })
        add({ check = "host_guest_finished", timeout = 400, cond = function()
            while true do
                local kind = PTNative_MsgPoll("t.")
                if not kind then return false end
                if kind == "t.done" then return true end
            end
        end })
        return steps
    end

    local host
    local function onRead()
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then return end
            if k == "t.read" then host = de(d) end
        end
    end
    local function cmp(f) return function() onRead(); if not host then return false end; local ok, why = f(host, read()); T.log("PT|info %s", tostring(why)); return ok end end
    local seenRain = false
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in", timeout = 400, cond = function() return T.netMode() == "client" and T.cls(T.myPawn()) == T.CHAR end },
        { check = "guest_got_host_readings", timeout = 120, cond = function() onRead(); return host ~= nil end },
        { check = "guest_ambience_set_up", timeout = 30, cond = function()
            if os.getenv("PT_HEADLESS") == "1" then T.log("PT|info guest_ambience_set_up skipped: headless"); return true end
            local am = T.first("BP_AmbienceManager_C")
            return am ~= nil and am.EnvironmentComponent:IsValid() and am.RainSplashSystem:IsValid() and am.PlayerRadiationNiagaraSystem:IsValid()
        end },
        { check = "guest_sim_linked", timeout = to(30), cond = function() local r = read(); return r.linked end },
        { check = "guest_time_matches", timeout = to(60), cond = cmp(function(h, g)
            local d = math.abs(h.tod - g.tod); return math.min(d, 1 - d) < 0.02 and h.tod > 0.8, string.format("tod host=%.3f guest=%.3f", h.tod, g.tod)
        end) },
        { check = "guest_runs_host_preset", timeout = to(60), cond = cmp(function(h, g)
            return h.target:find("AcidRain", 1, true) ~= nil and g.sim:find("AcidRain", 1, true) ~= nil, string.format("preset host=%s guest sim=%s", h.target, g.sim)
        end) },
        { check = "guest_precipitation_matches", timeout = to(90), cond = cmp(function(h, g)
            seenRain = seenRain or h.prec > 0.5
            return h.prec > 0.5 and math.abs(h.prec - g.prec) < 0.15, string.format("precipitation host=%.2f guest=%.2f", h.prec, g.prec)
        end) },
        { check = "guest_follows_preset_back", timeout = to(90), cond = cmp(function(h, g)
            return h.target:find("Sullen", 1, true) ~= nil and g.sim:find("Sullen", 1, true) ~= nil, string.format("preset host=%s guest sim=%s", h.target, g.sim)
        end) },
        { run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.done", "1") end },
        { wait = 3 },
    }
end
