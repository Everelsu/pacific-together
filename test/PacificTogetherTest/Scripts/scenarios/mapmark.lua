-- P8 (D17): the other player on the ARC map and as a HUD marker (mapmark.lua). Fixture `zone`, the guest joins by itself.
-- On each side: a map icon (in the game's MapTracker) and the game's HUD objective marker exist for the other player, their
-- world positions are within 5 m of the other's REAL position (reported over the message channel), the HUD marker is hidden
-- within 30 m and shown past it with "<name> <m> m", both follow after the other player moved 50 m (guest moves, then host),
-- and both are gone when the guest leaves.
-- Run: tools/run-test.ps1 -Scenario mapmark -Fixture zone -Headless
-- Mutation nomapmark: the module is off in both processes (every marker check fails).
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local mapName = "Rural_Forest_Radio_Scylla_02"
    local TOL = 500 -- 5 m
    local ticks = 0
    local real, realAt, left -- the other's own report of where it stands
    local function me() return T.ROLE == "host" and L.own() or T.myPawn() end
    local function addr()
        if T.ROLE == "host" then local pc = L.remotePCs()[1]; return pc and pc:GetAddress() end
        return T.localPC():GetAddress()
    end
    local function send(kind, data)
        local a = addr()
        if not a then return end
        if T.ROLE == "host" then PTNative_MsgToGuest(a, kind, data) else PTNative_MsgToHost(a, kind, data) end
    end
    LoopInGameThreadWithDelay(250, function()
        pcall(function()
            local m = me()
            if m and m:IsValid() then local l = m:K2_GetActorLocation(); ticks = ticks + 1
                if ticks % 8 == 0 then T.log("PT|info own pos %.0f %.0f %.0f (%s) got=%s", l.X, l.Y, l.Z, T.cls(m), real and string.format("%.0f %.0f %.0f", real.X, real.Y, real.Z) or "-") end
                send("t.pos", string.format("%.0f %.0f %.0f", l.X, l.Y, l.Z)) end
            while true do
                local kind, data = PTNative_MsgPoll("t.")
                if not kind then break end
                if kind == "t.pos" then
                    local x, y, z = data:match("^(%-?%d+) (%-?%d+) (%-?%d+)$")
                    real, realAt = { X = tonumber(x), Y = tonumber(y), Z = tonumber(z) }, os.clock()
                end
                if kind == "t.leave" then left = true; T.console("disconnect") end
            end
        end)
    end)

    local function d3(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end
    local function owned(cls, o)
        local r = {}
        for _, c in ipairs(FindAllOf(cls) or {}) do
            if c:IsValid() and T.inWorld(c) and c:GetOwner():IsValid() and c:GetOwner():GetClass():GetFName():ToString() == T.CHAR
                and (not o or c:GetOwner():GetFullName() == o:GetFullName()) then r[#r + 1] = c end
        end
        return r
    end
    local function trackerHas(icon)
        local lib = StaticFindObject("/Script/MinimapPlugin.Default__MapFunctionLibrary")
        local tr = lib:GetMapTracker(T.world())
        if not tr:IsValid() then return false end
        for _, e in ipairs(tr:GetMapIcons() or {}) do
            local ok, v = pcall(function() return e:get() end)
            if (ok and v or e):GetFullName() == icon:GetFullName() then return true end
        end
        return false
    end

    local ref -- where the other stood when the step began
    local function mark() return { run = function() ref = real end } end
    -- the markers for the other player match its real position; wantShown: the HUD marker must be visible (past 30 m);
    -- minMove: the other moved that far since mark()
    local function markCheck(id, wantShown, minMove)
        return { check = id, timeout = 30, cond = function()
            local o, m = T.otherChar(), me()
            local icons, huds = owned("MapIconComponent", o), owned("SC_GenericObjective_C", o)
            if not (o and m and real and os.clock() - realAt < 3 and #icons == 1 and #huds == 1) then
                T.log("PT|info %s: waiting o=%s real=%s icons=%d huds=%d", id, tostring(o ~= nil), tostring(real ~= nil), #icons, #huds)
                return false
            end
            local w = huds[1].MainIconWidget
            if not w:IsValid() then return false end
            local ip, hp = icons[1]:K2_GetComponentLocation(), w.Position
            local d = d3(T.localPC().PlayerCameraManager:GetCameraLocation(), real)
            local text = w.TaskText:GetText():ToString()
            local shown = w:GetVisibility() == 0
            local tracked = trackerHas(icons[1])
            T.log("PT|info %s: icon %.0f hud %.0f off real, d=%.0f shown=%s inView=%s text='%s' moved=%.0f tracker=%s", id, d3(ip, real), d3(hp, real), d,
                tostring(shown), tostring(w:IsInViewport()), text, ref and d3(ref, real) or -1, tostring(tracked))
            return d3(ip, real) <= TOL and d3(hp, real) <= TOL and w:IsInViewport() and tracked
                and shown == wantShown and (not wantShown or text:find("%d+ m$") ~= nil)
                and (not minMove or (ref and d3(ref, real) >= minMove))
        end }
    end
    -- teleport a character 50 m away (walls: four directions)
    local function away(char)
        local l = char:K2_GetActorLocation()
        for i = 0, 3 do
            local a = math.rad(90 * i + 30)
            if char:K2_TeleportTo({ X = l.X + math.cos(a) * 5000, Y = l.Y + math.sin(a) * 5000, Z = l.Z + 50 }, char:K2_GetActorRotation()) then return true end
        end
        T.log("PT|info no room to move 50 m")
    end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("zone")) do add(s) end
        add({ check = "host_listen", timeout = 120, cond = function() return T.netMode() == "listen" and T.listening() and T.map() == mapName end })
        add({ check = "host_guest_in", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 8 })
        add(markCheck("host_marks_guest_near", false))
        add(mark())
        add({ run = function() away(L.guestChar()) end }) -- the guest moves 50 m
        add(markCheck("host_marks_guest_far", true, 4500))
        add({ wait = 4 }) -- the guest checks its side of the host, then we move
        add({ run = function() away(L.own()) end }) -- the host moves 50 m
        add({ wait = 6 })
        add({ run = function() send("t.leave", "1") end })
        add({ check = "host_markers_gone_after_guest_left", timeout = 60, cond = function()
            local n, h = #owned("MapIconComponent"), #owned("SC_GenericObjective_C")
            T.log("PT|info after leave: icons on characters=%d huds=%d guest=%s", n, h, tostring(L.guestChar() ~= nil))
            return L.guestChar() == nil and n == 0 and h == 0
        end })
        return steps
    end

    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == mapName and T.cls(T.myPawn()) == T.CHAR end },
        { wait = 12 },
        markCheck("client_marks_host_near", false),
        mark(),
        markCheck("client_marks_host_after_guest_moved", true), -- the host moves us 50 m away from it
        mark(),
        markCheck("client_marks_host_after_host_moved", true, 4500), -- then the host moves 50 m
        { check = "client_told_to_leave", timeout = 120, cond = function() return left end },
    }
end
