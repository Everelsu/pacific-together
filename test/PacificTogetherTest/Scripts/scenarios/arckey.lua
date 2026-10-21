-- Playtest-1 bug A: the moved ARC hid dashboard panels and made the starter key unusable. The host enters as the driver through
-- the game's door entry, the guest by the door press. The driver's real camera traces to the ignition key like the game's highlight
-- trace (no ARC volume on the way); the guest's camera, aimed at the ARC screen, gets the game's highlight on the ARC.
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
    -- the ignition key's highlight collision (what the game's trace has to hit), first live volume
    local KSL = require("UEHelpers").GetKismetSystemLibrary()
    local function keyPoint()
        local hc = theCar().Highlight_Key.HighlightCollision
        for i = 1, hc:GetArrayNum() do
            local c = hc[i]
            if c and c:IsValid() then
                local o, e, r = {}, {}, {}
                KSL:GetComponentBounds(c, o, e, r)
                log("PT|info key collision %d %s origin=%.0f,%.0f,%.0f ext=%.0f,%.0f,%.0f enabled=%s", i, c:GetFullName(), o.X, o.Y, o.Z, e.X, e.Y, e.Z, tostring(c:GetCollisionEnabled()))
                return { X = o.X, Y = o.Y, Z = o.Z }
            end
        end
        return theCar().UICollision_Key:K2_GetComponentLocation()
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
        -- the host as the driver through the game's own door entry (as carenter): the key's highlight is a driving-state thing
        add({ run = function()
            local car, me = theCar(), T.myPawn()
            local l = car:K2_GetActorLocation()
            me:K2_HandleSetCharacterLocation({ Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X + 250, Y = l.Y + 200, Z = l.Z + 20 }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false, false)
        end })
        add({ wait = 1 })
        add({ run = function() theCar().SLOT_FrontLeftDoor:GetItemActor({}):StartEntry(false) end })
        add({ check = "host_in_car", timeout = 30, cond = function()
            local st = {}
            local m = T.first("BP_CarManager_C")
            m["Get PlayerCarState"](m, st)
            return tonumber(st.ReturnedState) == 1
        end })
        add({ wait = 5 })
        add({ run = function() sendGuest("t.aim") end })
        add({ wait = 4 })
        -- The game's highlight trace (BP_HighlightManager.PerformTrace) is a multi sphere trace for objects from the view target's camera;
        -- the view cannot be turned in the car state headless, so the same trace is run from the driver's real camera towards the key's
        -- collision: the key must be hit and none of the ARC's volumes may be in the swept sphere.
        add({ check = "driver_key_trace_not_blocked_by_arc", timeout = 5, cond = function()
            local hm = T.first("BP_HighlightManager_C")
            local cam = T.localPC().PlayerCameraManager:GetCameraLocation()
            local k = keyPoint()
            local dx, dy, dz = k.X - cam.X, k.Y - cam.Y, k.Z - cam.Z
            local n = math.sqrt(dx * dx + dy * dy + dz * dz)
            local e = { X = cam.X + dx / n * (n + 15), Y = cam.Y + dy / n * (n + 15), Z = cam.Z + dz / n * (n + 15) }
            local radius = hm.SelectionRadius_Inside
            local hits = {}
            KSL:SphereTraceMultiForObjects(T.world(), cam, e, radius, { 1, 7, 3, 12, 0, 6, 8, 13 }, true, {}, 0, hits, true,
                { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, 0)
            local key, arc = false, false
            for _, h in ipairs(hits) do
                local c = h:get().Component
                local ok, name = pcall(function() return c:get():GetFullName() end)
                name = ok and name or "?"
                log("PT|info trace hit %s", name)
                if name:find("UICollision_Key", 1, true) then key = true end
                if name:find("Gobbler", 1, true) then arc = true end
            end
            log("PT|info key trace cam=%.0f,%.0f,%.0f key=%.0f,%.0f,%.0f radius=%.1f hits=%d key=%s arc=%s", cam.X, cam.Y, cam.Z, k.X, k.Y, k.Z, radius, #hits, tostring(key), tostring(arc))
            return key and not arc
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
