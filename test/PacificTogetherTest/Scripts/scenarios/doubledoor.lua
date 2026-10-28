-- Double doors and door swings (visual.lua applyDoor). Owner, 2026-10-28: double doors sync badly and doors move "in jerks". A double
-- door (BP_Door_Double) has a second leaf with its own highlight and angle (currentRotOtherDoor, not in CurrentState), which never
-- synced; and the guest snapped every door with "Set Door from State". The garage's back room door (placed in the map):
--   1. the host presses the main leaf: on the guest it swings (many angles in between, not one jump) and ends at the host's angle
--   2. the host presses the second leaf: the guest's follows
--   3. the guest presses its second leaf: the host's follows
-- Run: tools/run-test.ps1 -Scenario doubledoor -Fixture garage -Headless   (the owner's long save: on the fresh save this door is chained)
-- Mutations: nodoorswing (snaps: check 1 FAILS), nodoubledoor (the guest's second leaf is not sent: check 3 FAILS).
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local NAME = "BP_Door_Double_Backroom_Exterior"
    local got = {}
    local function g(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind]
    end
    local function door()
        for _, d in ipairs(FindAllOf("BP_Door_Double_C") or {}) do
            if d:IsValid() and d:GetFName():ToString() == NAME and not d:GetFullName():find("/Engine/Transient", 1, true) then return d end
        end
    end
    local function leaf(d, n)
        local smc = StaticFindObject("/Script/Engine.StaticMeshComponent")
        for _, c in ipairs(d:K2_GetComponentsByClass(smc) or {}) do
            local o = c.get and c:get() or c
            if o:GetFName():ToString() == n then return o:K2_GetComponentRotation().Yaw end
        end
    end
    local function near(a, b) return a and b and math.abs(((a - b + 180) % 360) - 180) < 4 end
    local function press(h) h:InteractPressed(nil); h:InteractReleased(nil) end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local function toGuest(k, v) PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), k, v or "1") end
        local function guestYaw(n) local x = tonumber(g("t." .. n) or ""); return x end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "host_has_double_door", timeout = 20, cond = function() return door() ~= nil end })
        add({ check = "guest_door_matches_at_start", timeout = 60, cond = function() local d = door(); return near(leaf(d, "SM_DoorMesh"), guestYaw("main")) and near(leaf(d, "OtherDoor"), guestYaw("other")) end })
        add({ run = function() toGuest("t.watch"); press(door().Highlight) end })
        add({ wait = 4 })
        add({ check = "guest_main_leaf_follows", timeout = 10, cond = function() return near(leaf(door(), "SM_DoorMesh"), guestYaw("main")) end })
        add({ check = "guest_main_leaf_swung", timeout = 10, cond = function()
            local n = tonumber(g("t.steps") or "") or 0
            T.log("PT|info guest main leaf took %d different angles", n)
            return n >= 5
        end })
        add({ run = function() press(door().Highlight_OtherDoor) end })
        add({ check = "guest_second_leaf_follows", timeout = 8, cond = function() return near(leaf(door(), "OtherDoor"), guestYaw("other")) end })
        add({ wait = 3 })
        add({ run = function() got["t.other"] = nil; T.log("PT|info host second leaf before guest press %.0f", leaf(door(), "OtherDoor")); toGuest("t.press2") end })
        add({ check = "guest_pressed", timeout = 15, cond = function() return g("t.pressed2") ~= nil end })
        add({ wait = 1 })
        add({ check = "host_second_leaf_follows_guest", timeout = 8, cond = function()
            local h, x = leaf(door(), "OtherDoor"), tonumber(g("t.pressed2"))
            T.log("PT|info second leaf: host %.1f, guest before its press %s, guest now %s", h or -1, tostring(x), tostring(guestYaw("other")))
            return x and not near(h, x) and near(h, guestYaw("other"))
        end })
        add({ run = function() toGuest("t.done") end })
        add({ wait = 3 })
        return steps
    end

    -- guest: reports both leaves' angles; while watching, counts how many different angles the main leaf passes through
    local watch, last, steps, pressed = false, nil, 0, false
    LoopInGameThreadWithDelay(16, function()
        if not watch then return end
        pcall(function()
            local y = leaf(door(), "SM_DoorMesh")
            if last and math.abs(y - last) > 0.5 then steps = steps + 1 end
            last = y
        end)
    end)
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end },
        { check = "guest_reports", timeout = 600, cond = function()
            local d = door()
            if d then
                local pc = T.localPC():GetAddress()
                if g("t.watch") and not watch then watch = true end
                if watch then PTNative_MsgToHost(pc, "t.steps", tostring(steps)) end
                if g("t.press2") and not pressed then
                    pressed = true
                    PTNative_MsgToHost(pc, "t.pressed2", string.format("%.1f", leaf(d, "OtherDoor")))
                    press(d.Highlight_OtherDoor)
                end
                PTNative_MsgToHost(pc, "t.main", string.format("%.1f", leaf(d, "SM_DoorMesh")))
                PTNative_MsgToHost(pc, "t.other", string.format("%.1f", leaf(d, "OtherDoor")))
            end
            return g("t.done") ~= nil
        end },
    }
end
