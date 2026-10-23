-- PT3 world, garage: the chained side doors of the garage (first Steam play #1). Map-placed doors exist on both sides and are not mirrored:
-- the guest pried one open, it swung on the guest, the host's stayed shut and its collision blocked the guest.
--   host_door_unlocked_by_guest_pry   the guest works the lock of Garage_Exterior_Rear the way the prybar does (BP_LockedComponent:WorkLock):
--                                     the guest's door opens (guest_door_open), the host's door leaves the locked state (3) within 5 s
--   host_door_pressed_by_guest        the guest presses E on the (now open) door (Highlight, as E does): the host's door changes state again
-- Run: tools/run-test.ps1 -Scenario worlddoors -Fixture garage -Headless [-Root .. -Port ..]   Mutation novisual: visual.lua inert on both sides.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local DOOR = "BP_Door_Single_Garage_Exterior_Rear"
    local slow = (T.MUTATE == "novisual") and 0.15 or 1
    local function to(s) return math.max(12, math.floor(s * slow)) end
    local function door()
        for _, d in ipairs(FindAllOf("BP_Door_Single_C") or {}) do
            if d:IsValid() and d:GetFName():ToString() == DOOR and not d:GetFullName():find("/Engine/Transient", 1, true) then return d end
        end
    end
    local got = {}
    local function poll()
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then return end
            got[k] = d
        end
    end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "host_door_locked", timeout = 10, cond = function() local d = door(); return d and d.CurrentState >= 3 end })
        add({ check = "guest_ready", timeout = 400 * slow, cond = function() poll(); return got["t.ready"] ~= nil end })
        add({ check = "host_door_unlocked_by_guest_pry", timeout = to(30), cond = function()
            poll()
            local d = door()
            T.log("PT|info host door %s state=%s", DOOR, tostring(d and d.CurrentState))
            return got["t.pried"] ~= nil and d and d.CurrentState < 3
        end })
        add({ run = function() got["s0"] = tostring(door().CurrentState) end })
        add({ check = "host_door_pressed_by_guest", timeout = to(30), cond = function()
            poll()
            local d = door()
            T.log("PT|info host door %s state=%s (was %s)", DOOR, tostring(d.CurrentState), got["s0"])
            return got["t.pressed"] ~= nil and tostring(d.CurrentState) ~= got["s0"]
        end })
        add({ wait = 2 })
        return steps
    end

    -- guest
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end },
        { wait = 14 }, -- the guest hooks the garage doors a few seconds after the map
        { check = "guest_door_locked", timeout = 20, cond = function() local d = door(); return d and d.CurrentState >= 3 end },
        { run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.ready", "1") end },
        { wait = 2 },
        { run = function() -- the prybar's call on the lock (MessageBind_MSG_Damage_Physical_Impact -> WorkLock)
            local d = door()
            d.BP_LockedComponent:WorkLock(d.LockStrength, true, nil, {}, {}, {})
            T.log("PT|info guest pried %s state=%s", DOOR, tostring(d.CurrentState))
            PTNative_MsgToHost(T.localPC():GetAddress(), "t.pried", "1")
        end },
        { check = "guest_door_open", timeout = 10, cond = function() local d = door(); return d.CurrentState > 0 and d.CurrentState < 3 end },
        { wait = 6 },
        { run = function()
            door().Highlight:InteractPressed(nil) -- what the guest's E does on the door it looks at
            door().Highlight:InteractReleased(nil)
            PTNative_MsgToHost(T.localPC():GetAddress(), "t.pressed", "1")
        end },
        { wait = 15 },
    }
end
