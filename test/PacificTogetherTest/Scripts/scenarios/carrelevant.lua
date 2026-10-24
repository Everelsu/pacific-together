-- Garage play 2026-10-24: the host drove out to the junction and the guest's car stayed in the garage (the car stopped
-- replicating past the default 150 m net cull from the guest's camera; in a zone the guest then fell through unstreamed ground).
-- The host moves its car 300 m away from the guest standing in the garage; the guest's copy must follow.
-- Run: tools/run-test.ps1 -Scenario carrelevant -Fixture garage -Headless      Mutation: norelevant (car not always relevant)
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local got = {}
    local function has(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind] ~= nil
    end
    local function theCar()
        for _, c in ipairs(FindAllOf("BP_PlayerCarNew_C") or {}) do
            local l = c:IsValid() and c:K2_GetActorLocation()
            if l and not (l.X == 0 and l.Y == 0 and l.Z == 0) and (T.ROLE == "host" or c.Role ~= 3) then return c end
        end
    end
    local function d2(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2) end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 10 })
        add({ run = function()
            local car = theCar()
            pcall(function() car.Chassis:SetSimulatePhysics(false) end) -- placed, not driven: no fall where the move lands
            local l = car:K2_GetActorLocation()
            car:K2_SetActorLocation({ X = l.X + 30000, Y = l.Y, Z = l.Z + 2000 }, false, {}, true)
            T.log("PT|info host car moved 300 m")
        end })
        -- an actor that left the cull range still gets about 5 s of updates (RelevantTimeout): move again after that
        add({ wait = 8 })
        add({ run = function()
            local car = theCar()
            local l = car:K2_GetActorLocation()
            car:K2_SetActorLocation({ X = l.X + 1000, Y = l.Y + 1000, Z = l.Z }, false, {}, true)
            local n = car:K2_GetActorLocation()
            PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.moved", string.format("%.0f|%.0f", n.X, n.Y))
            T.log("PT|info host car moved again to %.0f,%.0f", n.X, n.Y)
        end })
        add({ wait = 20 })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    add({ check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end })
    add({ check = "guest_one_car", timeout = 90, cond = function() return theCar() ~= nil end })
    add({ check = "guest_told_moved", timeout = 240, cond = function() return has("t.moved") end })
    add({ check = "guest_car_followed_300m", timeout = 10, cond = function()
        local x, y = got["t.moved"]:match("^([^|]*)|(.*)$")
        local car = theCar()
        return car ~= nil and d2(car:K2_GetActorLocation(), { X = tonumber(x), Y = tonumber(y) }) < 500
    end })
    return steps
end
