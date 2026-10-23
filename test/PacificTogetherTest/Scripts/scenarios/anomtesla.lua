-- pt3-anom: the Spark Tower (Tesla) and the Grabber on the guest. Fixture `zone`, the guest joins by itself.
--   The guest stands next to a map Tesla while the host is far away: the Tesla picks the guest as its target, the guest takes the discharge
--   and sees its effects (CreateDischargeFX / targeting beam run on the guest's copy). A moving grabber is smooth on the guest.
-- Run: tools/run-test.ps1 -Scenario anomtesla -Fixture zone -Headless ; mutation noanomtesla switches the pt3-anom code off.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local mapName = "Rural_Forest_Radio_Scylla_02"
    local function health()
        local rm = T.first("BP_ResourceManager_C")
        local h = rm and rm.PlayerHealth
        return (h and h:IsValid()) and h.Current or -1
    end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local gpc, tesla = nil, nil
        local guestHp, fx, jump, grabSeen = -1, 0, 0, 0
        local function poll()
            while true do
                local kind, data = PTNative_MsgPoll("t.")
                if not kind then return end
                if kind == "t.hp" then guestHp = tonumber(data) or guestHp end
                if kind == "t.fx" then fx = tonumber(data) or fx end
                if kind == "t.jump" then local j, n = data:match("^([%d%.]+)\t(%d+)$"); jump, grabSeen = tonumber(j) or jump, tonumber(n) or grabSeen end
            end
        end
        for _, s in ipairs(T.loadFixture("zone")) do add(s) end
        add({ check = "host_listen", timeout = 120, cond = function() return T.netMode() == "listen" and T.listening() and T.map() == mapName end })
        add({ check = "host_guest_in", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 8 })
        add({ run = function() -- which hazards the zone fixture holds (spike doc list)
            local n = {}
            for _, o in ipairs(FindAllOf("BP_Base_Hazard_C") or {}) do
                if T.inWorld(o) then local c = o:GetClass():GetFName():ToString(); n[c] = (n[c] or 0) + 1 end
            end
            for c, k in pairs(n) do T.log("PT|info zone hazard %s x%d", c, k) end
        end })
        add({ run = function()
            gpc = L.remotePCs()[1]
            for _, o in ipairs(FindAllOf("BP_Hazard_Tesla_C") or {}) do
                if T.inWorld(o) and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) then tesla = tesla or o end
            end
            assert(tesla, "no map Tesla")
            local l = tesla:K2_GetActorLocation()
            T.log("PT|info Tesla %s at %.0f %.0f %.0f; guest goes next to it", T.name(tesla), l.X, l.Y, l.Z)
            PTNative_MsgToGuest(gpc:GetAddress(), "t.tp", string.format("%.0f\t%.0f\t%.0f", l.X + 400, l.Y, l.Z + 150))
            pcall(function() L.guestChar():K2_TeleportTo({ X = l.X + 400, Y = l.Y, Z = l.Z + 150 }, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
        end })
        add({ check = "guest_hurt_by_tesla", timeout = 150, cond = function()
            poll()
            local ok, st = pcall(function() return string.format("target=%.0f,%.0f fire=%s cd=%s deact=%s buildup=%.2f", tesla.TargetLocation.X, tesla.TargetLocation.Y,
                tostring(tesla.ShouldActuallyFire), tostring(tesla.Cooldown), tostring(tesla.Deactivated), tesla.Buildup) end)
            local ok2, dx = pcall(function()
                local mt = tesla.ManagedTick
                return string.format("tick=%s dist=%.0f max2=%.0f maxd=%s", tostring(tesla:IsActorTickEnabled()), T.dist(tesla, L.guestChar()), mt:GetSquaredMaxTickDistance(), tostring(mt.MaxTickDistance))
            end)
            T.log("PT|info %s", tostring(dx))
            T.log("PT|info tesla %s guest hp=%.0f fx=%d host hp=%.0f", tostring(st), guestHp, fx, health())
            return guestHp >= 0 and guestHp < 99
        end })
        add({ check = "guest_sees_tesla_fx", timeout = 90, cond = function() poll(); return fx > 0 end })
        -- grabber: put one in motion on the host, the guest's copy must follow without big jumps
        add({ run = function()
            local gs = {}
            for _, o in ipairs(FindAllOf("BP_Hazard_PhysicsGrabber_C") or {}) do
                if T.inWorld(o) then gs[#gs + 1] = { o = o, l = o:K2_GetActorLocation() } end
            end
            assert(#gs > 0, "no map grabber")
            local n = 0
            T.log("PT|info moving %d grabbers, 150 uu every 100 ms", #gs)
            PTNative_MsgToGuest(gpc:GetAddress(), "t.grab", "1")
            LoopInGameThreadWithDelay(100, function()
                n = n + 1
                if n > 50 then return true end
                for _, g in ipairs(gs) do
                    pcall(function() g.o:K2_SetActorLocation({ X = g.l.X + n * 150, Y = g.l.Y, Z = g.l.Z }, false, {}, true) end)
                end
                return false
            end)
        end })
        add({ check = "grabber_smooth_on_guest", timeout = 60, cond = function()
            poll()
            T.log("PT|info grabber samples=%d max step=%.1f", grabSeen, jump)
            return grabSeen >= 20 and jump <= 105 -- unsmoothed: one 150 uu step per update
        end })
        add({ run = function() PTNative_MsgToGuest(gpc:GetAddress(), "t.end", "1") end })
        add({ wait = 3 })
        return steps
    end

    local finished, fx = false, 0
    local hooks = { "CreateDischargeFX", "CreateTargetingBeam" } -- the class loads with the map: retried until it exists
    LoopInGameThreadWithDelay(1000, function()
        for i = #hooks, 1, -1 do
            if pcall(RegisterHook, "/Game/Gameplay/Hazards/TeslaAnomaly/BP_Hazard_Tesla.BP_Hazard_Tesla_C:" .. hooks[i], function() fx = fx + 1 end) then table.remove(hooks, i) end
        end
    end)
    -- grabber track: the guest's copy of the first grabber the host moves; frame-to-frame step while it moves
    local watch, last, maxStep, samples = nil, nil, 0, 0
    LoopInGameThreadWithDelay(16, function() pcall(function()
        if not watch then return end
        local g
        for _, o in ipairs(FindAllOf("BP_Hazard_PhysicsGrabber_C") or {}) do if T.inWorld(o) and not g then g = o end end
        if not g then return end
        local l = g:K2_GetActorLocation()
        if last then
            local d = math.sqrt((l.X - last.X) ^ 2 + (l.Y - last.Y) ^ 2 + (l.Z - last.Z) ^ 2)
            if d > 0.5 and d < 1500 then samples = samples + 1; maxStep = math.max(maxStep, d) end
        end
        last = l
    end) end)
    local home
    LoopInGameThreadWithDelay(1000, function() pcall(function()
        if T.netMode() ~= "client" then return end
        local me = T.myPawn()
        PTNative_MsgToHost(T.localPC():GetAddress(), "t.hp", string.format("%.0f", health()))
        PTNative_MsgToHost(T.localPC():GetAddress(), "t.fx", tostring(fx))
        PTNative_MsgToHost(T.localPC():GetAddress(), "t.jump", string.format("%.1f\t%d", maxStep, samples))
        if watch then
            local n, hit, hits = 0, nil, {}
            for _, o in ipairs(FindAllOf("BP_Hazard_PhysicsGrabber_C") or {}) do
                if T.inWorld(o) then n = n + 1; hits[#hits + 1] = T.name(o):sub(-34) .. ":" .. tostring(o.Role) end
            end
            T.log("PT|info guest grabbers=%d watch=%s %s", n, tostring(watch):sub(-34), table.concat(hits, ","))
        end
        while true do
            local kind, data = PTNative_MsgPoll("t.")
            if not kind then break end
            if kind == "t.end" then finished = true end
            if kind == "t.grab" then watch = data end
            if kind == "t.tp" and me and me:IsValid() then
                local x, y, z = data:match("^(%-?[%d%.]+)\t(%-?[%d%.]+)\t(%-?[%d%.]+)$")
                me:K2_SetActorLocation({ X = tonumber(x), Y = tonumber(y), Z = tonumber(z) }, false, {}, true)
            end
        end
    end) end)
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == mapName and T.cls(T.myPawn()) == T.CHAR end },
        { check = "client_stays_until_host_done", timeout = 600, cond = function() return finished end },
    }
end
