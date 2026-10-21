-- Playtest-1 bug A: the moved ARC hid dashboard panels and made the starter key unusable. The host sits in the driver's seat,
-- the guest enters by the door press; the driver's camera is aimed at the ignition key and the game's own highlight must be the
-- key (not the ARC); the guest's camera is aimed at the ARC screen and the highlight must be the ARC.
-- Run: tools/run-test.ps1 -Scenario arckey -Fixture garage -Headless      Mutation: arcold (the old ARC position)
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local C = require("scenarios.carlib")(T)
    local log = T.log
    local KML = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
    local got = {}
    local function has(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind] ~= nil
    end
    local function sendGuest(kind, data) PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), kind, data or "") end
    local function sendHost(kind, data) PTNative_MsgToHost(T.localPC():GetAddress(), kind, data or "") end
    local function theCar()
        for _, c in ipairs(FindAllOf("BP_PlayerCarNew_C") or {}) do
            local l = c:IsValid() and c:K2_GetActorLocation()
            if l and not (l.X == 0 and l.Y == 0 and l.Z == 0) and (T.ROLE == "host" or c.Role ~= 3) then return c end
        end
    end
    local function attached(c) local p = c:GetAttachParentActor(); return p:IsValid() and T.cls(p) == "BP_PlayerCarNew_C" end
    local function wrap(a) return (a + 180) % 360 - 180 end
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
    local function highlighted()
        local hm = T.first("BP_HighlightManager_C")
        local h = hm and hm.CurrentHighlight
        if not (h and h:IsValid()) then return "none" end
        return T.cls(h:GetOwner()) .. "." .. h:GetFName():ToString()
    end
    local function screenPoint()
        for _, a in ipairs(FindAllOf("BP_Carpart_Internal_GobblerScreen_C") or {}) do
            if a:IsValid() and a:GetAttachParentActor():IsValid() then
                local o, e = {}, {}
                a:GetActorBounds(true, o, e, false)
                return o
            end
        end
    end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 10 })
        add({ run = function()
            local c = theCar()
            local w = KML:TransformLocation(c:GetTransform(), { X = 131, Y = -200, Z = 0 })
            L.guestChar():K2_HandleSetCharacterLocation({ Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = w.X, Y = w.Y, Z = c:K2_GetActorLocation().Z + 10 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false, false)
            sendGuest("t.p1")
        end })
        add({ check = "guest_seated_by_door_press", timeout = 120, cond = function() local g = L.guestChar(); return g ~= nil and attached(g) end })
        -- the host as the driver: the character's eye is at the car camera's spot (X8)
        add({ run = function()
            local car, me = theCar(), T.myPawn()
            car:K2_SetActorRotation({ Pitch = 0, Yaw = 0, Roll = 0 }, true)
            C.seat(me, car, C.toLocal(car, C.driverSeat(me).Translation))
        end })
        add({ wait = 3 })
        add({ run = function()
            aimAt(function() return theCar().UICollision_Key:K2_GetComponentLocation() end, 150)
            sendGuest("t.aim")
        end })
        add({ wait = 4 })
        add({ check = "driver_highlights_ignition_key", timeout = 5, cond = function()
            local h = highlighted()
            local k = theCar().UICollision_Key:K2_GetComponentLocation()
            log("PT|info driver highlight=%s key world=%.0f,%.0f,%.0f arc screen=%s", h, k.X, k.Y, k.Z, tostring(screenPoint() and string.format("%.0f,%.0f,%.0f", screenPoint().X, screenPoint().Y, screenPoint().Z)))
            return h:find("Key", 1, true) ~= nil
        end })
        add({ check = "guest_highlights_arc", timeout = 60, cond = function() return has("t.hl") and (got["t.hl"]:find("Gobbler", 1, true) ~= nil) end })
        add({ wait = 2 })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    local id
    add({ check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end })
    add({ check = "guest_one_car", timeout = 90, cond = function() return theCar() ~= nil end })
    add({ check = "guest_told_p1", timeout = 240, cond = function() return has("t.p1") end })
    add({ wait = 2 })
    add({ run = function() id = T.act_begin("door_press", {}) end })
    add({ check = "guest_door_press", timeout = 90, cond = function() local d, _, ok = T.act_done(id); return d and ok end })
    add({ check = "guest_seated", timeout = 60, cond = function() return attached(T.myPawn()) end })
    add({ check = "guest_told_aim", timeout = 120, cond = function() return has("t.aim") end })
    add({ run = function() aimAt(screenPoint, 150) end })
    add({ wait = 4 })
    add({ check = "guest_reports_highlight", timeout = 10, cond = function()
        local h = highlighted()
        log("PT|info guest highlight=%s", h)
        sendHost("t.hl", h)
        return true
    end })
    add({ wait = 6 })
    return steps
end
