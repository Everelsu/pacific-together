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
        -- other hazards (spike doc item 3): a Landmine next to the guest, far from the host, arms (its PlayerRange sees a player in range)
        local mine
        add({ run = function()
            for _, o in ipairs(FindAllOf("BP_Hazard_Landmine_C") or {}) do if T.inWorld(o) and not mine then mine = o end end
            assert(mine, "no landmine")
            local l = mine:K2_GetActorLocation()
            PTNative_MsgToGuest(gpc:GetAddress(), "t.tp", string.format("%.0f\t%.0f\t%.0f", l.X + 600, l.Y, l.Z + 150))
            pcall(function() L.guestChar():K2_TeleportTo({ X = l.X + 600, Y = l.Y, Z = l.Z + 150 }, { Pitch = 0, Yaw = 0, Roll = 0 }) end)
            T.log("PT|info guest to landmine %s", T.name(mine))
        end })
        add({ check = "landmine_arms_for_guest", timeout = 60, cond = function()
            local ok, r = pcall(function() return mine.BP_HazardProperty_PlayerRange.PlayerInRange end)
            T.log("PT|info landmine PlayerInRange=%s dist=%.0f", tostring(r), T.dist(mine, L.guestChar()))
            return ok and r == true
        end })
        -- grabber: put one in motion on the host, the guest's copy must follow without big jumps
        add({ run = function()
            local gs = {}
            for _, o in ipairs(FindAllOf("BP_Hazard_PhysicsGrabber_C") or {}) do
                if T.inWorld(o) then gs[#gs + 1] = { o = o, l = o:K2_GetActorLocation() } end
            end
            assert(#gs > 0, "no map grabber")
            local n = 0
            T.log("PT|info moving %d grabbers, 700 uu every 500 ms", #gs)
            PTNative_MsgToGuest(gpc:GetAddress(), "t.grab", "1")
            LoopInGameThreadWithDelay(500, function()
                n = n + 1
                if n > 12 then return true end
                for _, g in ipairs(gs) do
                    pcall(function() g.o:K2_SetActorLocation({ X = g.l.X + n * 700, Y = g.l.Y, Z = g.l.Z }, false, {}, true) end)
                end
                return false
            end)
        end })
        add({ check = "grabber_smooth_on_guest", timeout = 60, cond = function()
            poll()
            T.log("PT|info grabber samples=%d frames moved=%.0f%%", grabSeen, jump)
            return grabSeen >= 15 and jump >= 60 -- percent of frames in which it moved: smoothed 78, a copy that jumps per update 18 (runs 20261024-014213 / -014417-nosmooth)
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
    -- a copy that only jumps when an update arrives moves in few frames of the motion window (the guest renders ~6 fps headless, the host moves
    -- it every 500 ms); a smoothed one moves in almost every frame. frames = frames from the first to the last movement, moved = frames with movement.
    local watch, last, flags = nil, nil, {}
    LoopInGameThreadWithDelay(16, function() pcall(function()
        if not watch then return end
        local g
        for _, o in ipairs(FindAllOf("BP_Hazard_PhysicsGrabber_C") or {}) do if T.inWorld(o) and not g then g = o end end
        if not g then return end
        local l, did = g:K2_GetActorLocation(), false
        if last then
            local d = math.sqrt((l.X - last.X) ^ 2 + (l.Y - last.Y) ^ 2 + (l.Z - last.Z) ^ 2)
            did = d > 0.5 and d < 1500
        end
        last = l
        flags[#flags + 1] = did
    end) end)
    local function ratio()
        local i, j = nil, nil
        for k, f in ipairs(flags) do if f then i = i or k; j = k end end
        if not i or j - i < 10 then return 0, 0 end
        local m = 0
        for k = i, j do if flags[k] then m = m + 1 end end
        return 100 * m / (j - i + 1), j - i + 1
    end
    local home
    LoopInGameThreadWithDelay(1000, function() pcall(function()
        if T.netMode() ~= "client" then return end
        local me = T.myPawn()
        PTNative_MsgToHost(T.localPC():GetAddress(), "t.hp", string.format("%.0f", health()))
        PTNative_MsgToHost(T.localPC():GetAddress(), "t.fx", tostring(fx))
        PTNative_MsgToHost(T.localPC():GetAddress(), "t.jump", string.format("%.1f\t%d", ratio()))
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
