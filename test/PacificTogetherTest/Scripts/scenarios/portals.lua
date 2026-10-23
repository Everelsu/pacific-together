-- The guest sees the exit portals and the story pickups (Q01 radio bits) the host has, at the same places. Fixture `gateway`.
-- Run: tools/run-test.ps1 -Scenario portals -Fixture gateway -Headless [-Root .. -Port ..]
-- Mutation noportals: the shipping mod's portal/pickup mirror is switched off in both processes.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local CLASSES = { portal = "BP_LevelTransition_ExitPortal_C", bits = "BP_Resource_Narrative_Q01_RadioBitsGrabbable_C" }
    local function live(o) return o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) and not T.name(o):find("/Engine/Transient", 1, true) end
    local function read()
        local r = {}
        for k, c in pairs(CLASSES) do
            r[k] = {}
            for _, o in ipairs(FindAllOf(c) or {}) do
                if live(o) then
                    local l = o:K2_GetActorLocation()
                    r[k][#r[k] + 1] = { n = T.name(o):match("[^%.]+$"), x = l.X, y = l.Y, z = l.Z, role = o.Role }
                end
            end
            table.sort(r[k], function(a, b) return a.n < b.n end)
        end
        return r
    end
    local function ser(r)
        local t = {}
        for k, l in pairs(r) do for _, a in ipairs(l) do t[#t + 1] = string.format("%s|%s|%.1f|%.1f|%.1f", k, a.n, a.x, a.y, a.z) end end
        return table.concat(t, "\n")
    end
    local function de(s)
        local r = { portal = {}, bits = {} }
        for k, n, x, y, z in s:gmatch("([^|\n]+)|([^|\n]+)|([^|\n]+)|([^|\n]+)|([^|\n]+)") do
            r[k][#r[k] + 1] = { n = n, x = tonumber(x), y = tonumber(y), z = tonumber(z) }
        end
        return r
    end
    local slow = (T.MUTATE == "noportals") and 0.2 or 1
    local function to(s) return math.max(15, math.floor(s * slow)) end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("gateway")) do add(s) end
        add({ check = "host_listen_zone", timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_zone", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ run = function()
            LoopInGameThreadWithDelay(1000, function() pcall(function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.read", ser(read())) end) end)
            local r = read()
            T.log("PT|info host portals=%d bits=%d", #r.portal, #r.bits)
        end })
        -- the guest grabs the pickup: the host's copy must be grabbed too (its quest counts)
        add({ check = "host_pickup_grabbed_by_guest", timeout = to(150), cond = function()
            for _, o in ipairs(FindAllOf(CLASSES.bits) or {}) do if live(o) and o.SuccessfullyGrabbed then return true end end
            return false
        end })
        add({ check = "host_guest_finished", timeout = 400 * slow, cond = function()
            while true do
                local kind = PTNative_MsgPoll("t.")
                if not kind then return false end
                if kind == "t.done" then return true end
            end
        end })
        return steps
    end

    local host
    local function onRead()
        while true do
            local kind, data = PTNative_MsgPoll("t.")
            if not kind then return end
            if kind == "t.read" then host = de(data) end
        end
    end
    local function matches(k)
        return function()
            onRead()
            if not host or #host[k] == 0 then return false end
            local g, miss = read()[k], 0
            for _, a in ipairs(host[k]) do
                local found = false
                for _, b in ipairs(g) do
                    if b.n == a.n and math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z) < 150 then found = true break end
                end
                if not found then miss = miss + 1 end
            end
            T.log("PT|info %s host=%d guest=%d missing=%d", k, #host[k], #g, miss)
            return miss == 0
        end
    end
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "Rural_Forest_Radio_Scylla_02" and T.cls(T.myPawn()) == T.CHAR end },
        { check = "guest_got_host_readings", timeout = to(120), cond = function() onRead(); return host ~= nil end },
        { check = "guest_sees_host_portals", timeout = to(60), cond = matches("portal") },
        { check = "guest_sees_host_story_pickups", timeout = to(60), cond = matches("bits") },
        { run = function()
            for _, o in ipairs(FindAllOf(CLASSES.bits) or {}) do
                if live(o) and o.Role == 1 then o:ShortGrabComplete({}); T.log("PT|info guest grabbed %s", T.name(o)) end
            end
        end },
        { wait = 6 },
        { run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.done", "1") end },
        { wait = 3 },
    }
end
