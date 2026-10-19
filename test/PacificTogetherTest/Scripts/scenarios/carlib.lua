-- Shared by the car scenarios (X7 carride, X8 carseat): guest spawn, car lookup, seating, driving bot, car-local math.
local UEHelpers = require("UEHelpers")

return function(T)
    local L = {}
    local log, ROLE, MUTATE = T.log, T.ROLE, T.MUTATE
    local KML = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local KSL = UEHelpers.GetKismetSystemLibrary()
    local GS = UEHelpers.GetGameplayStatics()
    local NONE = FName("None")

    -- QueryPerformanceCounter seconds: the same clock in every process on this machine, so host and guest samples line up
    function L.now()
        local s, p = {}, {}
        GS:GetAccurateRealTime(s, p)
        return s.Seconds + p.PartialSeconds
    end

    function L.alive(o) return o ~= nil and o:IsValid() and KSL:IsValid(o) end

    -- shortcut: after K2_DestroyActor the guest's car copy stays IsValid with IsActorBeingDestroyed false, but sits at
    -- exactly 0,0,0 (run 20261019-202851); treated as gone. A real fix needs to know what Destroy left behind (M3).
    function L.destroyed(a)
        local ok, r = pcall(function()
            local p = a:K2_GetActorLocation()
            return a:IsActorBeingDestroyed() or not a.RootComponent:IsValid() or (p.X == 0 and p.Y == 0 and p.Z == 0)
        end)
        return ok and r
    end
    -- every BaseNewCar of this world (FindAllOf includes subclasses; PendingKill ones are left out)
    function L.cars()
        local r = {}
        -- a destroyed car stays IsValid (also for KismetSystemLibrary) until GC and sits at 0,0,0 (runs 20261019-195752, -201151)
        for _, c in ipairs(FindAllOf("BaseNewCar") or {}) do if L.alive(c) and not L.destroyed(c) and T.inWorld(c) then r[#r + 1] = c end end
        return r
    end
    -- the host's car: on the host its only car, on the guest the replicated one (a Role 3 car there is the guest's own copy)
    function L.car()
        for _, c in ipairs(L.cars()) do if ROLE == "host" or c.Role ~= 3 then return c end end
    end
    function L.localCopies()
        local r = {}
        if ROLE == "host" then return r end
        for _, c in ipairs(L.cars()) do if c.Role == 3 then r[#r + 1] = c end end
        return r
    end
    -- actors of a class attached to car (directly or through its components)
    function L.attachedOf(car, class)
        local r = {}
        for _, a in ipairs(FindAllOf(class) or {}) do
            if L.alive(a) and T.inWorld(a) then
                local p = a:GetAttachParentActor()
                if p:IsValid() and p:GetFullName() == car:GetFullName() then r[#r + 1] = a end
            end
        end
        return r
    end
    function L.count(class)
        local n = 0
        for _, a in ipairs(FindAllOf(class) or {}) do if L.alive(a) and T.inWorld(a) then n = n + 1 end end
        return n
    end

    -- Blueprint classes often have a delegate with the same name as a function; call the UFunction itself
    function L.callBP(obj, fn, ...)
        local f = StaticFindObject(obj:GetClass():GetFullName():match("^%S+ (.+)$") .. ":" .. fn)
        assert(f and f:IsValid(), "no UFunction " .. fn)
        return f(obj, ...)
    end

    function L.v(x, y, z) return { X = x, Y = y, Z = z } end
    function L.fmt(p) return p and string.format("(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z) or "nil" end
    function L.d(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end
    function L.toLocal(car, p) return KML:InverseTransformLocation(car:GetTransform(), p) end
    function L.toWorld(car, p) return KML:TransformLocation(car:GetTransform(), p) end
    function L.localOf(car, comp) return L.toLocal(car, comp:K2_GetComponentLocation()) end

    -- the game's own seat for a character: driver's seat in world space (UE4SS fills the out-struct table)
    function L.driverSeat(char)
        local t = {}
        L.callBP(char, "GetCarAttachTransformForCharacter", t)
        return t
    end
    -- passenger seat = the driver's seat mirrored across the car's centre line (car-local Y -> -Y)
    function L.passengerLocal(car, char)
        local dl = L.toLocal(car, L.driverSeat(char).Translation)
        return L.v(dl.X, -dl.Y, dl.Z), dl
    end

    -- host: spawn a PDP_MainCharacter_C for the remote PC next to the host and possess it (as in X13)
    function L.spawnGuestStep()
        local guest
        return { check = "host_spawned_guest", timeout = 30, cond = function()
            local hostChar = T.myPawn()
            assert(hostChar and T.cls(hostChar) == T.CHAR, "host pawn " .. T.cls(hostChar))
            for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
                if T.inWorld(pc) and not pc:IsLocalController() then
                    local cm = T.first("BP_MainCharacterManager_C")
                    local before = cm and cm.CharacterActor
                    local l = hostChar:K2_GetActorLocation()
                    local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X, Y = l.Y + 300, Z = l.Z + 60 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
                    local a = GS:FinishSpawningActor(GS:BeginDeferredActorSpawnFromClass(T.world(), hostChar:GetClass(), xf, 2, nil), xf)
                    pc:Possess(a)
                    -- the single-player manager flips to the newest character; keep the host's
                    if cm and before and before:IsValid() and cm.CharacterActor:GetFullName() ~= before:GetFullName() then cm.CharacterActor = before end
                    guest = a
                    L.guest = a
                    log("PT|info spawned %s for %s possessed=%s", T.name(a), T.name(pc), tostring(pc.Pawn:GetFullName() == a:GetFullName()))
                end
            end
            return guest ~= nil and guest:IsValid()
        end }
    end

    -- host: put a character at a car-local spot and attach it (replicates to the guest)
    function L.seat(char, car, lp)
        pcall(function() char.CharacterMovement:DisableMovement() end)
        char:SetActorEnableCollision(false)
        local r = car:K2_GetActorRotation()
        char:K2_SetActorLocationAndRotation(L.toWorld(car, lp), { Pitch = 0, Yaw = r.Yaw, Roll = 0 }, false, {}, true)
        char:K2_AttachToActor(car, NONE, 1, 1, 1, false)
        log("PT|info seated %s at local %s world %s parent=%s", T.name(char), L.fmt(lp), L.fmt(char:K2_GetActorLocation()), T.name(char:GetAttachParentActor()))
    end

    -- guest: once the host attached us, stop our own movement and take the server's attach offset this frame
    function L.ride(char)
        pcall(function() char.CharacterMovement:DisableMovement() end)
        pcall(function() char.CharacterMovement:SetComponentTickEnabled(false) end)
        pcall(function() char:SetActorEnableCollision(false) end)
        local ar = char.AttachmentReplication
        char:K2_SetActorRelativeLocation({ X = ar.LocationOffset.X, Y = ar.LocationOffset.Y, Z = ar.LocationOffset.Z }, false, {}, true)
        log("PT|info riding offset %s parent=%s", L.fmt(ar.LocationOffset), T.name(char:GetAttachParentActor()))
    end

    -- guest: drop our own copies of the host's car (the guest's level spawns one too, X3)
    function L.dedupe()
        local n = 0
        for _, c in ipairs(L.localCopies()) do
            log("PT|info destroying local car copy %s at %s", T.name(c), L.fmt(c:K2_GetActorLocation()))
            c:K2_DestroyActor(); n = n + 1
        end
        return n
    end

    -- host: the game's own way into the driver's seat first, Possess as fallback (the reference saw CommandEnterCar do nothing)
    function L.enterCar(car)
        local pc, char = T.localPC(), T.myPawn()
        local ok, err = pcall(L.callBP, char, "CommandEnterCar", true, nil, false)
        log("PT|info CommandEnterCar ok=%s %s", tostring(ok), ok and "" or tostring(err))
        return pc, char
    end
    function L.possessing(car)
        local pc = T.localPC()
        return pc and pc.Pawn:IsValid() and pc.Pawn:GetFullName() == car:GetFullName()
    end
    function L.forcePossess(car, char)
        local pc = T.localPC()
        pc:Possess(car)
        pcall(function() L.callBP(T.first("BP_CarManager_C"), "Register Car Possessed", true) end)
        if char and not char:GetAttachParentActor():IsValid() then
            local t = L.driverSeat(char)
            L.seat(char, car, L.toLocal(car, t.Translation))
        end
        log("PT|info Possess fallback possessed=%s", tostring(L.possessing(car)))
    end
    function L.startEngine(car)
        local ok1 = pcall(function() car:ManualSetIgnition_NoAnim(2) end)
        local ok2 = pcall(function() car:ManualActivate_Gearbox(0, true) end)
        pcall(function() car.VehicleController:SetParkingBrakeActive(false) end)
        log("PT|info ignition=%s gearbox=%s", tostring(ok1), tostring(ok2))
    end

    -- host: per-frame throttle; forward/back every `half` s so the car stays in the garage yard; steer a little
    function L.drive(car, half)
        local t0, loop = L.now(), nil
        L.driving = true
        loop = LoopInGameThreadWithDelay(1, function()
            if not L.driving or not L.alive(car) then CancelDelayedAction(loop); return end
            local dt = L.now() - t0
            local dir = math.floor(dt / half) % 2 == 0 and 1.0 or -1.0
            pcall(function() car:AccelerateBrake(dir) end)
            pcall(function() car:DriveControl(dir) end)
            pcall(function() car.VehicleController.ThrottleInput = dir; car.VehicleController.SteerInput = 0.3 * dir end)
        end)
    end

    -- guest: the host is the only simulation of the car. Physics on the guest's copy fights replication (the car flew
    -- off in carseat run 20261019-191154), so the guest's car is kinematic and we place it every frame ourselves.
    function L.kinematic(car)
        pcall(function() car.Chassis:SetSimulatePhysics(false) end)
        pcall(function() car.VehicleController:SetComponentTickEnabled(false) end)
    end

    local function wrap(a) return (a + 180) % 360 - 180 end
    -- cubic Hermite between two snapshots using their replicated velocities; rotation by shortest-path lerp
    local function hermite(a, b, s, k)
        local h = b[k] - a[k]
        local s2, s3 = s * s, s * s * s
        local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
        local function ax(k, vk) return h00 * a[k] + h10 * h * a[vk] + h01 * b[k] + h11 * h * b[vk] end
        local function ang(k) return a[k] + wrap(b[k] - a[k]) * s end
        return L.v(ax("x", "vx"), ax("y", "vy"), ax("z", "vz")), { Pitch = ang("pitch"), Yaw = ang("yaw"), Roll = ang("roll") }
    end
    -- where the car is at render time r: between the two snapshots around r, or extrapolated from the newest (<= 0.25 s)
    -- k = which snapshot time to use: t (arrival) or tm (motion-timed, see L.follow)
    function L.sample(buf, r, k)
        local n = #buf
        if n == 0 then return end
        for i = n - 1, 1, -1 do
            local a, b = buf[i], buf[i + 1]
            if a[k] <= r and r < b[k] then return hermite(a, b, (r - a[k]) / (b[k] - a[k]), k) end
        end
        local z = buf[n]
        if r < buf[1][k] then z = buf[1] end
        local dt = math.max(0, math.min(r - z[k], 0.25))
        return L.v(z.x + z.vx * dt, z.y + z.vy * dt, z.z + z.vz * dt), { Pitch = z.pitch, Yaw = z.yaw, Roll = z.roll }
    end

    -- guest: every frame, record new ReplicatedMovement snapshots and place the kinematic car by L.mode:
    -- phys = leave it to the engine, snap = newest snapshot (the reference), interp = Hermite at now - L.delay on arrival
    -- times, motion = the same on motion times, freeze = never.
    -- Arrival times jitter by a frame and by the network; a motion time is the previous one plus the time the car needed
    -- for the distance at its replicated speed, pulled 10 % per snapshot towards the arrival time so it cannot drift.
    L.mode, L.delay, L.delayTarget, L.adaptive, L.buf, L.gaps = "snap", 0.1, 0.1, false, {}, {}
    local function motionTime(prev, now, p, v)
        if not prev then return now end
        local h = now - prev.t
        local sp = (math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2) + math.sqrt(prev.vx ^ 2 + prev.vy ^ 2 + prev.vz ^ 2)) / 2
        if sp > 50 then
            local d = math.sqrt((p.X - prev.x) ^ 2 + (p.Y - prev.y) ^ 2 + (p.Z - prev.z) ^ 2)
            h = math.max(0.3 * h, math.min(3 * h, d / sp))
        end
        local tm = prev.tm + h
        return tm + 0.1 * (now - tm)
    end
    function L.follow(car)
        local last, loop
        loop = LoopInGameThreadWithDelay(1, function()
            if not L.alive(car) then CancelDelayedAction(loop); return end
            local ok, err = pcall(function()
                local now, rm = L.now(), car.ReplicatedMovement
                local p, r, v = rm.Location, rm.Rotation, rm.LinearVelocity
                if not last or p.X ~= last.x or p.Y ~= last.y or p.Z ~= last.z then
                    local tm = motionTime(last, now, p, v)
                    if last then
                        table.insert(L.gaps, now - last.t)
                        if #L.gaps > 60 then table.remove(L.gaps, 1) end
                        local s = {}
                        for i, g in ipairs(L.gaps) do s[i] = g end
                        table.sort(s)
                        -- render far enough behind to cover 95 % of snapshot gaps (a loaded host sent 250 ms gaps, run 20261019-201151)
                        L.delayTarget = math.max(0.1, math.min(0.25, 1.5 * s[math.ceil(#s * 0.95)] + 0.02))
                    end
                    last = { t = now, tm = tm, x = p.X, y = p.Y, z = p.Z, vx = v.X, vy = v.Y, vz = v.Z, pitch = r.Pitch, yaw = r.Yaw, roll = r.Roll }
                    table.insert(L.buf, last)
                    if #L.buf > 64 then table.remove(L.buf, 1) end
                    if L.logRep then log("PT|crep t=%.4f x=%.1f y=%.1f z=%.1f v=%.0f", now, p.X, p.Y, p.Z, math.sqrt(v.X ^ 2 + v.Y ^ 2)) end
                end
                -- the delay moves 1 % per frame, so a change never shows as a jump
                if L.adaptive then L.delay = L.delay + (L.delayTarget - L.delay) * 0.01 end
                local to, rot
                if L.mode == "snap" then to, rot = L.v(last.x, last.y, last.z), { Pitch = last.pitch, Yaw = last.yaw, Roll = last.roll }
                elseif L.mode == "interp" then to, rot = L.sample(L.buf, now - L.delay, "t")
                elseif L.mode == "motion" then to, rot = L.sample(L.buf, now - L.delay, "tm") end
                if to then car:K2_SetActorLocationAndRotation(to, rot, false, {}, true) end
                if L.onFrame then L.onFrame(now, car) end
            end)
            if not ok and not L.followErr then L.followErr = true; log("PT|info follow error %s", tostring(err)) end
        end)
    end

    return L
end
