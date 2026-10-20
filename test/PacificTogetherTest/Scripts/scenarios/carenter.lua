-- Playtest bug 2026-10-20: the host got into the car and the guest's character was pulled into it and dropped through
-- the map; the run start then crashed the host. Cause: every PDP_MainCharacter binds the single-player manager's
-- CommandEnterCar, so the host's enter ran on the guest's character too. session.lua mutes those calls on the other
-- player's character (PTNative_Mute).
-- Run: tools/run-test.ps1 -Scenario carenter -Fixture garage -Headless
-- Mutation nomute: the host clears the mute list before entering, so the guest's character is attached again (checks FAIL).
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local function car() return T.first("BP_PlayerCarNew_C") end
    local function carMode()
        local st = {}
        local m = T.first("BP_CarManager_C")
        m["Get PlayerCarState"](m, st)
        return tonumber(st.ReturnedState)
    end
    local function attachedToCar(c) local p = c:GetAttachParentActor(); return p:IsValid() and T.cls(p) == "BP_PlayerCarNew_C" end
    local function inZone() return L.gameplay(T.map()) and T.map() ~= "RB_Garage" end

    if T.ROLE == "host" then
        local guestZ
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 8 })
        add({ run = function()
            guestZ = L.guestChar():K2_GetActorLocation().Z
            if T.MUTATE == "nomute" then PTNative_MuteClear() end
            local c, l = T.myPawn(), car():K2_GetActorLocation()
            local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X + 250, Y = l.Y + 200, Z = l.Z + 20 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
            c:K2_HandleSetCharacterLocation(xf, false, false)
        end })
        add({ wait = 1 })
        -- what the car's enter-door highlight calls; it runs the manager's CommandEnterCar broadcast
        add({ run = function() car().SLOT_FrontLeftDoor:GetItemActor({}):StartEntry(false) end })
        add({ check = "host_in_car", timeout = 30, cond = function() return carMode() == 1 end })
        add({ wait = 5 })
        add({ check = "host_guest_not_in_car", timeout = 1, cond = function()
            local g = L.guestChar()
            T.log("PT|info guest attached=%s z=%.0f was=%.0f muted=%s", tostring(g and attachedToCar(g)), g and g:K2_GetActorLocation().Z or -1, guestZ, tostring(PTNative_MuteCount()))
            return g ~= nil and not attachedToCar(g) and math.abs(g:K2_GetActorLocation().Z - guestZ) < 100
        end })
        -- the run start that crashed the host in the playtest
        add({ run = function()
            StaticFindObject("/Game/Systems/ScriptingLibraries/BFL_ProgressionHelpers.Default__BFL_ProgressionHelpers_C"):TravelToNextLeg(T.world())
        end })
        add({ check = "host_listens_zone", timeout = 240, cond = function() return inZone() and T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_back_zone", timeout = 300, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 5 })
        return steps
    end

    local z0
    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    add({ check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end })
    add({ run = function() z0 = T.myPawn():K2_GetActorLocation().Z end })
    -- the host enters the car within this window; our character must stay on the floor, unattached
    add({ check = "client_stays_out_of_car", timeout = 60, cond = L.holds(40, function()
        -- the window ends with the host's run start (the next check follows us into the zone)
        if T.map() ~= "RB_Garage" or T.netMode() ~= "client" then return true end
        local p = T.myPawn()
        -- dropped by the run start, waiting on the old map for the rejoin: no character to check
        if p == nil or T.cls(p) ~= T.CHAR then return true end
        return not attachedToCar(p) and p:K2_GetActorLocation().Z > z0 - 150
    end) })
    add({ check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and inZone() and T.cls(T.myPawn()) == T.CHAR end })
    add({ wait = 10 })
    return steps
end
