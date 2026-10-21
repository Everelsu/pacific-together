-- W3, W4, W6, G3: the guest sees the host's run. Fixture `gateway` (a real run map, ARC charged), the guest joins by itself.
-- The host reads its world once a second and sends the readings (t.read); the guest compares them with its own world:
-- time of day and weather, hazards (none of its own, the host's within 100 uu), instability and storm manager state,
-- the host's gateway portal, the host's zone storm, and a guest that cannot start a story of its own.
-- Run: tools/run-test.ps1 -Scenario worldsync -Fixture gateway -Headless [-Root .. -Port ..]
-- Mutation noworldsync: the shipping mod's world module is switched off on both sides (every sync check must fail).
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local TAG = { TagName = FName("WB.WorldState.Instability.Current") }

    local function wb() return StaticFindObject("/Script/PenDriverPro.Default__BaseProgressionManager"):GetRouteWhiteboard(T.world()) end
    local function live(o) return o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) and not T.name(o):find("/Engine/Transient", 1, true) end
    local function lives(c) local r = {} for _, o in ipairs(FindAllOf(c) or {}) do if live(o) then r[#r + 1] = o end end return r end

    -- (the shipping mod reads PT_MUTATE itself: noworldsync switches its world module off in both processes)
    local slow = (T.MUTATE == "noworldsync") and 0.2 or 1 -- a mutation must fail, not wait out every timeout
    local function to(s) return math.max(15, math.floor(s * slow)) end

    -- what this world looks like, as plain numbers and strings
    local function read()
        local r = { hz = {}, portals = {} }
        local tod = T.first("BP_ToDManager_C")
        local o = {}
        tod["Get Current Time Of Day"](tod, o)
        r.tod = o["Returned Time Of Day"]
        r.fog, r.rain = tod.TOD_Override_Fog_Current, tod.TOD_Override_Rain_Current
        r.ov = tod.TargetWeatherOverrideArray:GetArrayNum()
        local w = wb()
        r.instab = (w:IsValid() and w:TagExists(TAG, true)) and w:GetTagFloat(TAG, true, -1) or -1
        local sm = T.first("BP_StormManager_C")
        r.tbis, r.gate = sm.TimeBeforeInstabilityStarts, T.name(sm.EvolvedGatewayExit):match("[^%.]+$") or "none"
        for _, h in ipairs(lives("BP_Base_Hazard_C")) do
            local l = h:K2_GetActorLocation()
            r.hz[#r.hz + 1] = { cls = T.cls(h), x = l.X, y = l.Y, z = l.Z, role = h.Role }
        end
        for _, p in ipairs(lives("BP_LevelTransition_ExitPortal_C")) do r.portals[#r.portals + 1] = T.name(p):match("[^%.]+$") end
        table.sort(r.portals)
        local st = lives("BP_ZoneStorm_Base_C")[1]
        if st then local l = st:K2_GetActorLocation(); r.storm = { x = l.X, y = l.Y, z = l.Z } end
        return r
    end
    local function ser(r)
        local t = { string.format("%.5f|%.5f|%.5f|%d|%.5f|%.1f|%s|%s", r.tod, r.fog, r.rain, r.ov, r.instab, r.tbis, r.gate, table.concat(r.portals, ",")) }
        t[2] = r.storm and string.format("%.1f|%.1f|%.1f", r.storm.x, r.storm.y, r.storm.z) or ""
        for _, h in ipairs(r.hz) do t[#t + 1] = string.format("%s|%.1f|%.1f|%.1f", h.cls, h.x, h.y, h.z) end
        return table.concat(t, "\n")
    end
    local function de(s)
        local lines, r = {}, { hz = {}, portals = {} }
        for line in (s .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
        local a = {}
        for x in (lines[1] .. "|"):gmatch("(.-)|") do a[#a + 1] = x end
        r.tod, r.fog, r.rain, r.ov, r.instab, r.tbis, r.gate = tonumber(a[1]), tonumber(a[2]), tonumber(a[3]), tonumber(a[4]), tonumber(a[5]), tonumber(a[6]), a[7]
        for p in (a[8] or ""):gmatch("[^,]+") do r.portals[#r.portals + 1] = p end
        local s2 = {}
        for x in ((lines[2] or "") .. "|"):gmatch("(.-)|") do s2[#s2 + 1] = x end
        if s2[1] and s2[1] ~= "" then r.storm = { x = tonumber(s2[1]), y = tonumber(s2[2]), z = tonumber(s2[3]) } end
        for i = 3, #lines do
            local c, x, y, z = lines[i]:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
            if c then r.hz[#r.hz + 1] = { cls = c, x = tonumber(x), y = tonumber(y), z = tonumber(z) } end
        end
        return r
    end

    if T.ROLE == "host" then
        local guestAddr
        local function send()
            local g = L.remotePCs()[1]
            if g then PTNative_MsgToGuest(g:GetAddress(), "t.read", ser(read())) end
        end
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("gateway")) do add(s) end
        add({ check = "host_listen_zone", timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_zone", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ run = function()
            LoopInGameThreadWithDelay(1000, function() pcall(send) end)
            local d = read()
            T.log("PT|info host world tod=%.3f fog=%.2f ov=%d instab=%.2f tbis=%.0f hazards=%d portals=%s", d.tod, d.fog, d.ov, d.instab, d.tbis, #d.hz, table.concat(d.portals, ","))
        end })
        -- the host's run moves on: instability rises, a gateway is summoned, the zone storm comes in, a story event fires
        add({ wait = 10 })
        add({ run = function() wb():SetTagFloat(TAG, 0.5) end })
        add({ wait = 8 })
        add({ run = function()
            local sm = T.first("BP_StormManager_C")
            for _, p in ipairs(lives("BP_LevelTransition_ExitPortal_C")) do
                sm["Select Exit Portal Actor"](sm, p)
                T.log("PT|info host gateway %s", T.name(p))
                break
            end
        end })
        add({ wait = 8 })
        add({ run = function()
            local sm, l = T.first("BP_StormManager_C"), T.myPawn():K2_GetActorLocation()
            sm:SpawnRoyaleStorm({ X = l.X - 8000, Y = l.Y, Z = l.Z }, true, nil)
        end })
        add({ wait = 12 })
        -- G3: a story event on the host; the guest must stay up and start nothing
        add({ run = function()
            local q = T.first("BP_QuestManager_C")
            T.log("PT|info host story: missions=%d", q:GetNumActiveMissions())
            q:AdvanceAllObjectives()
        end })
        add({ wait = 20 })
        add({ check = "host_guest_alive_after_story", timeout = 30, cond = L.holds(10, function() return T.netMode() == "listen" and T.pcs() == 2 end) })
        -- stay up until the guest has run all its checks
        add({ check = "host_guest_finished", timeout = 700 * slow, cond = function()
            while true do
                local kind = PTNative_MsgPoll("t.")
                if not kind then return false end
                if kind == "t.done" then return true end
            end
        end })
        return steps
    end

    -- guest
    local host
    local function onRead()
        while true do
            local kind, data = PTNative_MsgPoll("t.")
            if not kind then return end
            if kind == "t.read" then host = de(data) end
        end
    end
    local function near(a, b, d) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) <= d end
    local function circ(a, b) local d = math.abs(a - b); return math.min(d, 1 - d) end
    local function cmp(f) return function() onRead(); if not host then return false end; local ok, why = f(host, read()); T.log("PT|info %s", tostring(why)); return ok end end

    local mission
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "Rural_Forest_Radio_Scylla_02" and T.cls(T.myPawn()) == T.CHAR end },
        { check = "guest_got_host_readings", timeout = to(120), cond = function() onRead(); return host ~= nil end },
        { check = "guest_time_matches", timeout = to(60), cond = cmp(function(h, g) return circ(h.tod, g.tod) < 0.02, string.format("tod host=%.3f guest=%.3f", h.tod, g.tod) end) },
        { check = "guest_weather_matches", timeout = to(90), cond = cmp(function(h, g)
            return h.ov == g.ov and h.ov > 0 and math.abs(h.fog - g.fog) < 0.15, string.format("weather host ov=%d fog=%.2f guest ov=%d fog=%.2f", h.ov, h.fog, g.ov, g.fog)
        end) },
        { check = "guest_has_no_own_anomalies", timeout = to(60), cond = cmp(function(h, g)
            local own = 0
            for _, z in ipairs(g.hz) do if z.role ~= 1 then own = own + 1 end end
            return own == 0 and #g.hz > 0, string.format("guest hazards=%d own=%d host=%d", #g.hz, own, #h.hz)
        end) },
        { check = "guest_sees_host_anomalies", timeout = to(90), cond = cmp(function(h, g)
            local miss = 0
            for _, a in ipairs(h.hz) do
                local found = false
                for _, b in ipairs(g.hz) do if b.cls == a.cls and near(a, b, 100) then found = true break end end
                if not found then miss = miss + 1 end
            end
            return miss == 0 and #h.hz > 0, string.format("host hazards=%d missing on guest=%d", #h.hz, miss)
        end) },
        { check = "guest_instability_matches", timeout = to(90), cond = cmp(function(h, g)
            return h.instab >= 0.4 and math.abs(h.instab - g.instab) < 0.02 and math.abs(h.tbis - g.tbis) < 1, string.format("instab host=%.2f guest=%.2f tbis host=%.0f guest=%.0f", h.instab, g.instab, h.tbis, g.tbis)
        end) },
        { check = "guest_sees_host_gateway", timeout = to(90), cond = cmp(function(h, g)
            return h.gate ~= "none" and h.gate == g.gate and table.concat(h.portals, ",") == table.concat(g.portals, ","),
                string.format("gate host=%s guest=%s portals host=%s guest=%s", h.gate, g.gate, table.concat(h.portals, ","), table.concat(g.portals, ","))
        end) },
        { check = "guest_sees_host_storm", timeout = to(90), cond = cmp(function(h, g)
            return h.storm ~= nil and g.storm ~= nil and near(h.storm, g.storm, 100), string.format("storm host=%s guest=%s", h.storm and h.storm.x or "none", g.storm and g.storm.x or "none")
        end) },
        -- G3: the guest's own mission manager starts nothing, even when asked
        { run = function()
            local q = T.first("BP_QuestManager_C")
            mission = StaticFindObject("/Game/Gameplay/Quests/Q00_Intro/QD_Q00_Intro_Mission_A.QD_Q00_Intro_Mission_A")
            if not (mission and mission:IsValid()) then
                pcall(function() LoadAsset("/Game/Gameplay/Quests/Q00_Intro/QD_Q00_Intro_Mission_A.QD_Q00_Intro_Mission_A") end)
                mission = StaticFindObject("/Game/Gameplay/Quests/Q00_Intro/QD_Q00_Intro_Mission_A.QD_Q00_Intro_Mission_A")
            end
            T.log("PT|info guest story: mission=%s missions before=%d", T.name(mission), q:GetNumActiveMissions())
            -- unguarded, the real StartMission crashes the guest (seen in the noworldsync run): not asked under that mutation
            if mission and mission:IsValid() and T.MUTATE ~= "noworldsync" then q:StartMission(mission, true) end
        end },
        { wait = 3 },
        { check = "guest_story_bystander", timeout = to(10), cond = function()
            local q = T.first("BP_QuestManager_C")
            local n = q:GetNumActiveMissions()
            T.log("PT|info guest missions after=%d", n)
            -- the loaded MissionData is not rooted and may be collected by now; it was valid when StartMission ran
            return mission ~= nil and n == 0
        end },
        { check = "guest_alive_after_host_story", timeout = to(60), cond = L.holds(12, function() return T.netMode() == "client" and T.map() == "Rural_Forest_Radio_Scylla_02" and T.myPawn() ~= nil end) },
        { run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.done", "1") end },
        { wait = 3 },
    }
end
