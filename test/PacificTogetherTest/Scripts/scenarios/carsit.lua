-- Steam playtest #12: the seated guest's body shows its legs under the car. Checks the sitting state (thigh bones hidden)
-- on the host's body copy and on the guest's own pawn, and (host) that the survivor legs folded into the seated pose.
-- Run: tools/run-test.ps1 -Scenario carsit -Fixture garage -Headless      Mutation: nosit (fix off)
-- (was: Playtest-1 bug B: the guest pressed X in the car; on the host they stood outside, on their own screen they stayed in the car.
-- The guest enters through the door press (real input), exits by the exit intent (the key X is a UE4SS key bind, not drivable
-- headless), then 3 s later its OWN pawn must be outside the seat, near where the host sees it, and able to walk.
-- Only one guest seat exists (the mirrored driver seat), so there is no separate driver case.
-- Run: tools/run-test.ps1 -Scenario carexit -Fixture garage -Headless      Mutation: noexitfix (guest does not follow the exit)
return function(T)
    local L = require("scenarios.sessionlib")(T)
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
    local function placeGuest(x, y, z)
        L.guestChar():K2_HandleSetCharacterLocation({ Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = x, Y = y, Z = z }, Scale3D = { X = 1, Y = 1, Z = 1 } }, false, false)
    end
    local function theCar()
        for _, c in ipairs(FindAllOf("BP_PlayerCarNew_C") or {}) do
            local l = c:IsValid() and c:K2_GetActorLocation()
            if l and not (l.X == 0 and l.Y == 0 and l.Z == 0) and (T.ROLE == "host" or c.Role ~= 3) then return c end
        end
    end
    local function attached(c) local p = c:GetAttachParentActor(); return p:IsValid() and T.cls(p) == "BP_PlayerCarNew_C" end
    local function d3(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end
    local function pos(o) local l = o:K2_GetActorLocation(); return string.format("%.0f|%.0f|%.0f", l.X, l.Y, l.Z) end
    local function unpos(s) local x, y, z = s:match("^([^|]*)|([^|]*)|(.*)$"); return { X = tonumber(x), Y = tonumber(y), Z = tonumber(z) } end


    -- the legs are hidden by bone while seated (the game has no sitting pose)
    local function sitInfo(c)
        return string.format("%s|%s", tostring(c.Mesh:IsBoneHiddenByName(FName("thigh_l"))), tostring(c.Mesh:IsBoneHiddenByName(FName("thigh_r"))))
    end
    local function sitOk(s)
        log("PT|info sit state %s", s)
        return s == "true|true"
    end
    -- survivor.lua's seated legs: a thigh part hinged on the pelvis part, a shin part hinged on it; seated, the knee is level with
    -- the hip (thigh forward) and the standing leg parts are hidden
    local function seatLegs(c)
        local PMC = "ProceduralMeshComponent"
        for _, p in ipairs(FindAllOf(PMC) or {}) do
            local hip = p:IsValid() and p:GetOuter():GetAddress() == c:GetAddress() and p.AttachParent
            if hip and hip:IsValid() and T.cls(hip) == PMC and T.cls(hip.AttachParent) == PMC then
                return string.format("%.0f|%s|%s", p:K2_GetComponentLocation().Z - hip:K2_GetComponentLocation().Z, tostring(hip:IsVisible()),
                    tostring(L.survivorParts(c).thigh_l:IsVisible()))
            end
        end
        return "none"
    end
    local function legsOk(s)
        log("PT|info seat legs knee-hip dz|rig shown|standing thigh shown %s", s)
        local dz, shown, standing = s:match("^(-?%d+)|(%a+)|(%a+)$")
        return dz ~= nil and math.abs(tonumber(dz)) < 20 and shown == "true" and standing == "false"
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
            placeGuest(w.X, w.Y, c:K2_GetActorLocation().Z + 10)
            sendGuest("t.p1")
        end })
        add({ check = "guest_seated_by_door_press", timeout = 120, cond = function() local g = L.guestChar(); return g ~= nil and attached(g) end })
        add({ wait = 4 })
        add({ check = "host_sees_guest_body_sitting", timeout = 15, cond = function() return sitOk(sitInfo(L.guestChar())) end })
        add({ check = "host_sees_guest_legs_folded", timeout = 10, cond = function() return legsOk(seatLegs(L.guestChar())) end })
        add({ run = function() sendGuest("t.report") end })
        add({ check = "guest_own_pawn_sitting", timeout = 20, cond = function() return has("t.r") and sitOk(got["t.r"]) end })
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
    -- garage play 2026-10-24: the guest waited 4-14 s for the replicated attachment after the host seated it
    add({ check = "guest_seated_within_3s", timeout = 3, cond = function() return attached(T.myPawn()) end })
    add({ check = "guest_seated", timeout = 60, cond = function() return attached(T.myPawn()) end })
    -- and once with its head in the roof (seat 18 uu high): the passenger seat sits at about -12 uu
    add({ check = "guest_seat_height", timeout = 10, cond = function() return T.myPawn().RootComponent.RelativeLocation.Z < -5 end })
    add({ check = "guest_told_report", timeout = 120, cond = function() return has("t.report") end })
    add({ run = function() sendHost("t.r", sitInfo(T.myPawn())) end })
    add({ wait = 4 })
    return steps
end
