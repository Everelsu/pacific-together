-- X8: guest in the passenger seat, ARC device (BP_Carpart_Internal_Gobbler_C + its screen) moved so both reach it.
-- Run without -Headless for screenshots. Mutations: noarc (the ARC stays on the passenger seat), far (the ARC goes onto the
-- driver's seat), kick (see L.ride).
local UEHelpers = require("UEHelpers")

return function(T)
    local L = require("scenarios.carlib")(T)
    local log, ROLE, MUTATE = T.log, T.ROLE, T.MUTATE
    local GOBBLER, SCREEN = "BP_Carpart_Internal_Gobbler_C", "BP_Carpart_Internal_GobblerScreen_C"
    local S = {}

    local function arc(car)
        car = car or L.car()
        return L.attachedOf(car, GOBBLER)[1], L.attachedOf(car, SCREEN)[1]
    end
    -- car-local box of an actor: only its colliding parts (the interaction volumes) or everything
    local function box(car, a, colliding)
        local o, e = {}, {}
        a:GetActorBounds(colliding, o, e, false)
        return L.toLocal(car, o), L.v(e.X, e.Y, e.Z)
    end
    -- where the passenger and the driver really are (car-local), measured on this side
    local function seatLocal(car)
        return L.toLocal(car, (ROLE == "host" and L.guest or T.myPawn()):K2_GetActorLocation())
    end
    local function driverLocal(car)
        return L.toLocal(car, (ROLE == "host" and S.char or T.otherChar()):K2_GetActorLocation())
    end
    -- visible parts of the ARC: its mesh components, as car-local boxes (exact while the car stands at yaw 0)
    local function meshes(car)
        local r = {}
        for _, a in ipairs({ arc(car) }) do
            local an = a:GetFullName()
            for _, c in ipairs(FindAllOf("MeshComponent") or {}) do
                -- skeletal mesh bounds here cover the whole physics asset (106 x 68 x 110 uu for the gobbler), so they are left out
                if c:IsValid() and c:GetOwner():IsValid() and c:GetOwner():GetFullName() == an and c:IsVisible() and not c:IsA(StaticFindObject("/Script/Engine.SkeletalMeshComponent")) then
                    local o, e, rad = {}, {}, {}
                    UEHelpers.GetKismetSystemLibrary():GetComponentBounds(c, o, e, rad)
                    -- shortcut: a mesh bigger than the cabin is a stray (FX); skipped
                    if e.X < 80 and e.Y < 80 then r[#r + 1] = { name = T.cls(a) .. "." .. c:GetFName():ToString(), c = L.toLocal(car, o), e = L.v(e.X, e.Y, e.Z) } end
                end
            end
        end
        return r
    end
    -- a body core (seat point up to the eyes, 10 uu around) must be in its seat and not cut into an ARC mesh
    local function clear(car, p, want)
        p, want = p or seatLocal(car), want or S.want
        if L.d(p, want) > 20 then return false, "off seat " .. L.fmt(want) end
        for _, m in ipairs(meshes(car)) do
            if math.abs(p.X - m.c.X) < m.e.X + 10 and math.abs(p.Y - m.c.Y) < m.e.Y + 10 and p.Z - 10 < m.c.Z + m.e.Z and p.Z + 75 > m.c.Z - m.e.Z then return false, m.name end
        end
        return true, "none"
    end
    -- what draws the brown blotches over the passenger's view: every post-process source in this world
    local function ppReport(tag)
        for _, c in ipairs(FindAllOf("PostProcessComponent") or {}) do
            if c:IsValid() and T.inWorld(c:GetOwner()) then
                log("PT|pp side=%s tag=%s comp=%s owner=%s enabled=%s unbound=%s weight=%s priority=%s", ROLE, tag, c:GetFName():ToString(), T.cls(c:GetOwner()),
                    T.str(T.get(c, "bEnabled")), T.str(T.get(c, "bUnbound")), T.str(T.get(c, "BlendWeight")), T.str(T.get(c, "Priority")))
            end
        end
        for _, v in ipairs(FindAllOf("PostProcessVolume") or {}) do
            if v:IsValid() and T.inWorld(v) then
                log("PT|pp side=%s tag=%s volume=%s enabled=%s unbound=%s weight=%s", ROLE, tag, T.name(v), T.str(T.get(v, "bEnabled")), T.str(T.get(v, "bUnbound")), T.str(T.get(v, "BlendWeight")))
            end
        end
        for _, c in ipairs(FindAllOf("CameraComponent") or {}) do
            if c:IsValid() and c:GetOwner():IsValid() and T.inWorld(c:GetOwner()) and c:IsActive() then
                log("PT|pp side=%s tag=%s camera=%s owner=%s ppWeight=%s", ROLE, tag, c:GetFName():ToString(), T.cls(c:GetOwner()), T.str(T.get(c, "PostProcessBlendWeight")))
            end
        end
    end

    local function report(tag)
        local car = L.car()
        local g, s = arc(car)
        for _, m in ipairs(meshes(car)) do log("PT|seat side=%s tag=%s mesh=%s box=%s+-%s", ROLE, tag, m.name, L.fmt(m.c), L.fmt(m.e)) end
        for _, a in ipairs({ g, s }) do
            local c1, e1 = box(car, a, true)
            local c2, e2 = box(car, a, false)
            log("PT|seat side=%s tag=%s arc=%s colliding=%s+-%s all=%s+-%s slot=%s slotRel=%s", ROLE, tag, T.cls(a), L.fmt(c1), L.fmt(e1),
                L.fmt(c2), L.fmt(e2), T.name(a.RootComponent:GetAttachParent()), L.fmt(T.get(a.RootComponent:GetAttachParent(), "RelativeLocation")))
        end
        local hm = T.first("BP_HighlightManager_C")
        local cm = T.localPC().PlayerCameraManager
        local cl = cm:GetCameraLocation()
        local ok, why = clear(car)
        local dok, dwhy = clear(car, driverLocal(car), S.driverWant)
        log("PT|seat side=%s tag=%s driver=%s driverClear=%s(%s) %s", ROLE, tag, L.fmt(driverLocal(car)), tostring(dok), dwhy,
            ROLE == "host" and L.seatInfo(L.guest, car) or L.seatInfo(T.myPawn(), car))
        log("PT|seat side=%s tag=%s seat=%s clear=%s(%s) cam=%s camRot=(p%.0f y%.0f) carYaw=%.0f camToScreen=%.0f highlight=%s", ROLE, tag,
            L.fmt(seatLocal(car)), tostring(ok), why, L.fmt(L.toLocal(car, cl)), cm:GetCameraRotation().Pitch, cm:GetCameraRotation().Yaw,
            car:K2_GetActorRotation().Yaw, L.d(cl, L.toWorld(car, (box(car, s, true)))),
            hm and hm.CurrentHighlight:IsValid() and T.name(hm.CurrentHighlight:GetOwner()) .. "." .. hm.CurrentHighlight:GetFName():ToString() or "none")
    end

    local function wrap(a) return (a + 180) % 360 - 180 end
    -- turn our view until the camera (not just the control rotation: the car camera lags) looks at p, for n frames
    local function aimAt(getP, n)
        local i, loop = 0, nil
        loop = LoopInGameThreadWithDelay(1, function()
            i = i + 1
            pcall(function()
                local pc = T.localPC()
                local cm = pc.PlayerCameraManager
                local c, cr, p = cm:GetCameraLocation(), cm:GetCameraRotation(), getP()
                local dx, dy, dz = p.X - c.X, p.Y - c.Y, p.Z - c.Z
                local wp, wy = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), math.deg(math.atan(dy, dx))
                local ctl = pc:GetControlRotation()
                pc:SetControlRotation({ Pitch = ctl.Pitch + wrap(wp - cr.Pitch) * 0.3, Yaw = ctl.Yaw + wrap(wy - cr.Yaw) * 0.3, Roll = 0 })
            end)
            if i >= n then CancelDelayedAction(loop) end
        end)
    end
    local function forward()
        local car = L.car()
        local c, f = T.localPC().PlayerCameraManager:GetCameraLocation(), car:GetActorForwardVector()
        return L.v(c.X + f.X * 1000, c.Y + f.Y * 1000, c.Z + f.Z * 1000 - 80)
    end
    local function screenCentre()
        local car = L.car()
        local _, s = arc(car)
        return L.toWorld(car, (box(car, s, true)))
    end
    local function highlighted()
        local hm = T.first("BP_HighlightManager_C")
        local h = hm and hm.CurrentHighlight
        return h and h:IsValid() and T.cls(h:GetOwner()) or "none"
    end

    -- slide both ARC slots so the device sits between the seats (car-local Y = 0)
    local function moveArc()
        local car = L.car()
        local g = arc(car)
        local c = box(car, g, true)
        local delta = L.v(0, (MUTATE == "far" and -2 or -1) * c.Y, 0)
        local done = {}
        for _, a in ipairs({ arc(car) }) do
            local slot = a.RootComponent:GetAttachParent()
            if not done[slot:GetFullName()] then
                done[slot:GetFullName()] = true
                local r = slot.RelativeLocation
                slot:K2_SetRelativeLocation(L.v(r.X + delta.X, r.Y + delta.Y, r.Z + delta.Z), false, {}, true)
            end
        end
        log("PT|info moved ARC slots by %s", L.fmt(delta))
    end
    -- the gobbler's interaction box centred between the seats, the screen still on the car (fixed target, not before + delta)
    local function moved()
        local car = L.car()
        local g, s = arc(car)
        return g ~= nil and s ~= nil and math.abs(box(car, g, true).Y) < 2
    end

    local function arcSteps()
        local x = ROLE == "host" and "host" or "client"
        return {
            { check = x .. "_arc_found", timeout = 10, cond = function() local g, s = arc(); return g ~= nil and s ~= nil end },
            -- the game's driver seat and its mirror, from this side's own car
            { run = function() S.want, S.driverWant = L.passengerLocal(L.car(), T.myPawn()); log("PT|info seats passenger=%s driver=%s", L.fmt(S.want), L.fmt(S.driverWant)) end },
            { run = function() report("seated"); ppReport("seated"); aimAt(forward, 120) end }, { wait = 3 },
            { run = function() T.shot("before-forward") end }, { wait = 1 },
            { run = function() aimAt(screenCentre, 120) end }, { wait = 3 },
            { run = function() report("before-arc"); S.hlBefore = highlighted(); T.shot("before-arc") end }, { wait = 1 },
            { check = x .. "_arc_blocks_passenger_seat", timeout = 1, cond = function()
                local car = L.car()
                return L.d(seatLocal(car), S.want) <= 20 and not clear(car)
            end },
            { run = function() if MUTATE ~= "noarc" then moveArc() end end },
            { wait = 1 },
            { check = x .. "_arc_moved", timeout = 3, cond = function() return moved() end },
            { check = x .. "_passenger_seat_clear", timeout = 3, cond = function() return clear(L.car()) end },
            { check = x .. "_driver_seat_clear", timeout = 3, cond = function() local car = L.car(); return clear(car, driverLocal(car), S.driverWant) end },
            { run = function() aimAt(forward, 120) end }, { wait = 3 },
            { run = function() report("after-forward"); T.shot("after-forward") end }, { wait = 1 },
            { run = function() aimAt(screenCentre, 120) end }, { wait = 3 },
            { run = function() report("after-arc"); T.shot("after-arc") end },
            { check = x .. "_highlights_arc", timeout = 5, cond = function() return highlighted() == SCREEN or highlighted() == GOBBLER end },
            -- the game's own interact press on the current highlight: the ARC screen takes the camera
            { run = function()
                local hm = T.first("BP_HighlightManager_C")
                S.camBefore = T.localPC().PlayerCameraManager:GetCameraLocation()
                hm:HighlightPress(true, {})
                ExecuteInGameThreadWithDelay(200, function() pcall(function() hm:HighlightPress(false, {}) end) end)
            end },
            { wait = 3 },
            { run = function() report("after-use"); T.shot("after-use") end },
            { check = x .. "_uses_arc", timeout = 5, cond = function()
                local _, s = arc()
                local fp = s.BP_InteractCameraComponent["Focused Player"]
                return fp:IsValid() and fp:GetFullName() == T.localPC():GetFullName()
            end },
            { wait = 3 },
        }
    end

    local steps
    if ROLE == "host" then
        steps = {
            T.onMap("RB_MainMenu", 90),
            { wait = 5 },
            { run = function() T.console("open " .. T.GARAGE .. "?listen") end },
            { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
            { check = "host_two_pcs", timeout = 180, cond = function() return T.pcs() == 2 end },
            { wait = 10 },
            L.spawnGuestStep(),
            { wait = 10 },
            { run = function()
                local car = L.car()
                car:K2_SetActorRotation({ Pitch = 0, Yaw = 0, Roll = 0 }, true)
                log("PT|info car at yaw 0; camera limits yaw=(%.0f,%.0f) pitch=(%.0f,%.0f)", car.CameraYawMinMaxAngles.X, car.CameraYawMinMaxAngles.Y,
                    car.CameraPitchMinMaxAngles.X, car.CameraPitchMinMaxAngles.Y)
            end },
            { wait = 3 },
            -- the host sits in the driver's seat as a character, not possessing the car: the possessed car's camera ignored
            -- every look we fed it (runs 20261019-193105, -193711), and the character's eye is at the car camera's spot
            { check = "host_in_driver_seat", timeout = 10, cond = function()
                local car = L.car()
                S.char = T.myPawn()
                local dl = L.toLocal(car, L.driverSeat(S.char).Translation)
                L.seat(S.char, car, dl)
                return L.d(L.toLocal(car, S.char:K2_GetActorLocation()), dl) < 2
            end },
            { check = "host_seated_guest", timeout = 10, cond = function()
                local car = L.car()
                S.passenger = L.passengerLocal(car, S.char)
                L.seat(L.guest, car, S.passenger)
                return L.guest:GetAttachParentActor():GetFullName() == car:GetFullName()
            end },
            { run = function() T.flip(L.guest) end },
            { wait = 8 },
        }
    else
        steps = {
            T.onMap("RB_MainMenu", 90),
            T.join("client_connected_garage", "RB_Garage", 210, 30),
            { check = "client_possessed", timeout = 60, cond = function() return T.cls(T.myPawn()) == T.CHAR end },
            { check = "client_seated", timeout = 90, cond = function() local p = T.myPawn():GetAttachParentActor(); return p:IsValid() and L.car() ~= nil and p:GetFullName() == L.car():GetFullName() end },
            { run = function()
                log("PT|info local car copies removed: %d", L.dedupe())
                local car = L.car()
                L.kinematic(car); L.follow(car)
                L.ride(T.myPawn())
                local o = T.otherChar(); if o then T.flip(o) end
            end },
            { wait = 3 },
            { check = "client_in_seat", timeout = 15, cond = function()
                local car, me = L.car(), T.myPawn()
                log("PT|info seat %s", L.seatInfo(me, car))
                return L.seatErr(me, car) < 3
            end },
        }
    end
    for _, s in ipairs(arcSteps()) do steps[#steps + 1] = s end
    return steps
end
