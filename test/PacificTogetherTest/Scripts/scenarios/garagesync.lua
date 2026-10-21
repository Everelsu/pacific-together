-- PT1 garage: the rear garage door opens and closes for both players when the host presses its button the way a player does
-- (the button highlight's own interact), in a session. Playtest 1: no garage door ever moved.
-- Run: tools/run-test.ps1 -Scenario garagesync -Fixture garage -Headless      Mutation nogarage: garage.lua inert (the doors stay stuck).
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local function alive(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
    local function rear()
        for _, d in ipairs(FindAllOf("BP_GarageDoor_C") or {}) do
            if alive(d) and not d.IsFrontGarageDoor and not d:GetFullName():find("/Engine/Transient", 1, true) then return d end
        end
    end
    local function pos() local d = rear(); return d and d.CurrentDoorPosition or -1 end

    local got = {}
    local function has(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind] ~= nil
    end
    local function guestPos() has("t.rear"); return tonumber(got["t.rear"] or "-1") end
    local function press()
        local b = T.first("BP_BackDoorButton_01_C")
        b.Highlight:InteractPressed(nil)
        b.Highlight:InteractReleased(nil)
    end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "host_rear_door_open_at_start", timeout = 40, cond = function() return pos() > 0.99 end })
        add({ check = "guest_rear_door_open_at_start", timeout = 40, cond = function() return guestPos() > 0.99 end })
        add({ run = press })
        add({ check = "host_rear_door_closes", timeout = 30, cond = function() return pos() < 0.01 end })
        add({ check = "guest_rear_door_closes", timeout = 30, cond = function() return guestPos() >= 0 and guestPos() < 0.01 end })
        add({ run = press })
        add({ check = "host_rear_door_reopens", timeout = 30, cond = function() return pos() > 0.99 end })
        add({ check = "guest_rear_door_reopens", timeout = 30, cond = function() return guestPos() > 0.99 end })
        add({ run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.done", "") end })
        add({ wait = 3 })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    add({ check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end })
    add({ check = "guest_reports_door", timeout = 600, cond = function()
        PTNative_MsgToHost(T.localPC():GetAddress(), "t.rear", string.format("%.3f", pos()))
        return got["t.done"] ~= nil or has("t.done")
    end })
    return steps
end
