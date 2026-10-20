-- "Observe and measure" helpers for the game MCP (tools/gamemcp/ext_observe.py). Run on the game thread through the live console.
-- One shared polling loop (started on first use, 20 ms tick, idle when no job is active) drives timed jobs: property watches,
-- frame-time sampling and screenshot bursts. Test copies only, never shipped.
local function try(f, ...) local ok, v = pcall(f, ...); if ok then return v end end

local function num(v)
    if math.type(v) == "integer" then return tostring(v) end
    local s = string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")
    return s
end

-- any Lua / UE4SS value as a short comparable string (structs with X,Y,Z / Pitch,Yaw,Roll, objects by full name, names/strings/text)
local function fmtv(T, v)
    if type(v) == "number" then return num(v) end
    if type(v) ~= "table" and type(v) ~= "userdata" then return tostring(v) end
    local g = type(v) == "userdata" and try(function() return v.get and v:get() end)
    if g ~= nil and g ~= false and type(g) ~= "userdata" then return fmtv(T, g) end
    -- structs: userdata (properties) or plain tables (function returns)
    local x = try(function() return v.X end)
    if type(x) == "number" then
        local parts = { "X=" .. num(x), "Y=" .. num(v.Y), "Z=" .. num(v.Z) }
        local w = try(function() return v.W end)
        if type(w) == "number" then parts[#parts + 1] = "W=" .. num(w) end
        return "(" .. table.concat(parts, " ") .. ")"
    end
    local p = try(function() return v.Pitch end)
    if type(p) == "number" then return "(P=" .. num(p) .. " Y=" .. num(v.Yaw) .. " R=" .. num(v.Roll) .. ")" end
    if type(v) == "table" then return T.show(v) end
    if try(function() return v.IsValid end) then
        return try(function() return v:IsValid() and v:GetFullName() or "<invalid>" end) or "<object>"
    end
    local s = try(function() return v.ToString and v:ToString() end)
    if s ~= nil then return tostring(s) end
    return T.show(v)
end

-- "A.B.C" reads a property chain; a trailing "()" calls a no-argument function (K2_GetActorLocation())
local function read(T, o, path)
    local cur = o
    for step in path:gmatch("[^%.]+") do
        if type(cur) ~= "userdata" and type(cur) ~= "table" then return "<n/a>" end
        local call = step:match("^(.-)%(%)$")
        local ok, v = pcall(function()
            if call then return cur[call](cur) end
            return cur[step]
        end)
        if not ok or v == nil then return "<unreadable>" end
        cur = v
    end
    return fmtv(T, cur)
end

return function(T)
    local jobs, nextId, loopOn = {}, 0, false

    local function ensureLoop()
        if loopOn then return end
        loopOn = true
        LoopInGameThreadWithDelay(20, function()
            if next(jobs) == nil then return end
            local now = os.clock() * 1000
            for _, j in pairs(jobs) do
                if not j.done then
                    if now >= j.deadline then
                        j.done = true
                    elseif now >= j.nextAt then
                        j.nextAt = now + j.interval
                        local ok, err = pcall(j.step, j, now - j.t0)
                        if not ok then j.err = tostring(err); j.done = true end
                    end
                end
            end
        end)
    end

    local function startJob(interval, seconds, step, extra)
        ensureLoop()
        nextId = nextId + 1
        local now = os.clock() * 1000
        local j = extra or {}
        j.interval, j.deadline, j.step, j.t0, j.nextAt, j.n, j.done = interval, now + seconds * 1000, step, now, now, 0, false
        jobs[nextId] = j
        return nextId, j
    end

    -- returns the finished job and forgets it
    local function takeJob(id)
        local j = assert(jobs[id], "no such job " .. tostring(id) .. " (already read?)")
        jobs[id] = nil
        j.done = true
        return j
    end

    local function instances(target, cap)
        if target:find("/", 1, true) then return { T.mcp_obj(target) } end
        local res = {}
        for _, o in ipairs(FindAllOf(target) or {}) do
            if o:IsValid() and not o:GetFullName():find("Default__", 1, true) and select(2, pcall(T.inWorld, o)) == true then
                res[#res + 1] = o
                if #res >= cap then break end
            end
        end
        assert(#res > 0, "no live instance of '" .. target .. "' in the current world")
        return res
    end

    local function label(o) return try(function() return o:GetFName():ToString() end) or "?" end

    -- watch_property: target = object path/full name or class name (every instance, up to cap); props = "A|B.C|Fn()"
    function T.mcp_wp_start(target, props, intervalMs, seconds, cap)
        local objs, plist = instances(target, cap), {}
        for p in props:gmatch("[^|]+") do plist[#plist + 1] = p end
        assert(#plist > 0, "no properties given")
        local last = {}
        local id, j = startJob(intervalMs, seconds, function(job, t)
            job.n = job.n + 1
            for oi, o in ipairs(objs) do
                local valid = try(function() return o:IsValid() end)
                for _, p in ipairs(plist) do
                    local key = oi .. "|" .. p
                    local v = valid and read(T, o, p) or "<gone>"
                    if last[key] ~= v then
                        if #job.log < 400 then
                            job.log[#job.log + 1] = string.format("+%dms\t%s\t%s\t%s", t, label(o), p, last[key] == nil and ("= " .. v) or (last[key] .. " -> " .. v))
                        else
                            job.dropped = job.dropped + 1
                        end
                        last[key] = v
                    end
                end
            end
        end, { log = {}, dropped = 0 })
        j.targets, j.props = #objs, #plist
        return id
    end

    function T.mcp_wp_read(id)
        local j = takeJob(id)
        local head = string.format("targets=%d props=%d samples=%d changes=%d%s%s", j.targets, j.props, j.n, #j.log + j.dropped,
            j.dropped > 0 and (" dropped=" .. j.dropped) or "", j.err and (" error=" .. j.err) or "")
        return head .. "\n" .. table.concat(j.log, "\n")
    end

    -- GetWorldDeltaSeconds is the previous frame's duration; sampled every 20 ms it gives a frame-time distribution (not every frame)
    local function worldDelta()
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        return gs:GetWorldDeltaSeconds(T.world())
    end
    -- net_stats: one window per side. Frame time and the net driver's real tick rate are sampled every 20 ms; socket counters (native
    -- net.cpp) are read at the start and the end; ping comes from the PlayerStates (compressed byte, 4 ms steps).
    local function counters()
        local ok, s = pcall(PTNative_NetStats)
        if not ok then return nil end
        local t = {}
        for n in tostring(s):gmatch("%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    function T.mcp_net_start(seconds)
        local drv = try(function() return T.world().NetDriver end)
        local id, j = startJob(20, seconds, function(job)
            job.n = job.n + 1
            local d = worldDelta()
            if type(d) == "number" and d > 0 then job.v[#job.v + 1] = d * 1000 end
            local t = drv and try(function() return drv.Time end)
            if type(t) == "number" and job.lastT ~= t then
                if job.lastT then job.ticks = job.ticks + 1 end
                job.lastT = t
            end
        end, { v = {}, ticks = 0 })
        j.c0, j.wall0 = counters(), os.clock()
        return id
    end
    function T.mcp_net_read(id)
        local j = takeJob(id)
        local wall = os.clock() - j.wall0
        local c1 = counters()
        local drv = try(function() return T.world().NetDriver end)
        local lines = { string.format("window_s=%.2f", wall) }
        local role = T.netMode()
        lines[#lines + 1] = "net=" .. role
        if drv then
            lines[#lines + 1] = string.format("driver=%s configured_tick_hz=%s measured_tick_hz=%.1f (lower bound: polled every ~20 ms, %d polls)", label(drv), tostring(try(function() return drv.NetServerMaxTickRate end)), j.ticks / wall, j.n)
            local conns = {}
            local cc = try(function() return drv.ClientConnections end)
            for i = 1, cc and #cc or 0 do conns[#conns + 1] = cc[i] end
            local sc = try(function() return drv.ServerConnection end)
            if sc and try(function() return sc:IsValid() end) then conns[#conns + 1] = sc end
            for _, c in ipairs(conns) do
                local lr = try(function() return c.LastReceiveTime end)
                local now = try(function() return drv.Time end)
                lines[#lines + 1] = string.format("connection %s last_receive_age_s=%s", label(c),
                    (lr and now) and string.format("%.2f", now - lr) or "?")
            end
        end
        for _, ps in ipairs(FindAllOf("PlayerState") or {}) do
            if ps:IsValid() and not ps:GetFullName():find("Default__", 1, true) and select(2, pcall(T.inWorld, ps)) == true then
                local p = try(function() return ps.Ping end)
                lines[#lines + 1] = string.format("player %s ping_ms=%s (Ping byte %s x4: 4 ms steps, 0 = under 4 ms)", tostring(try(function() return ps:GetPlayerName():ToString() end) or label(ps)),
                    p and tostring(p * 4) or "?", tostring(p))
            end
        end
        if j.c0 and c1 and c1[5] and c1[5] > 0 then
            local function rate(i) return (c1[i] - j.c0[i]) / wall end
            lines[#lines + 1] = string.format("udp_out packets_per_s=%.1f bytes_per_s=%.0f   udp_in packets_per_s=%.1f bytes_per_s=%.0f", rate(1), rate(2), rate(3), rate(4))
        else
            lines[#lines + 1] = "udp counters unavailable (native net.cpp missing or no sendto/recvfrom import found)"
        end
        lines[#lines + 1] = "lost_packets: not exposed (UNetConnection counters are plain C++ members; reflection cannot read them)"
        local v = j.v
        if #v > 0 then
            table.sort(v)
            local sum = 0
            for _, x in ipairs(v) do sum = sum + x end
            lines[#lines + 1] = string.format("frame_time_ms samples=%d avg=%.2f p50=%.2f p95=%.2f max=%.2f", #v, sum / #v, v[math.ceil(#v * 0.5)], v[math.ceil(#v * 0.95)], v[#v])
        else
            lines[#lines + 1] = "frame_time_ms: no samples"
        end
        return table.concat(lines, "\n")
    end

    -- screenshot burst: N HighResShot commands on the game thread, interval apart (min 100 ms)
    function T.mcp_burst_start(count, intervalMs)
        local fired = 0
        return (startJob(math.max(intervalMs, 100), (count + 2) * math.max(intervalMs, 100) / 1000 + 5, function(job, t)
            if fired < count then
                fired = fired + 1
                T.console("HighResShot 1")
            else
                job.done = true
            end
        end, {}))
    end
    function T.mcp_burst_done(id) return jobs[id] == nil or jobs[id].done end

    -- game events the engine does not log: possess changes of the local controller and players (PlayerStates) coming and going.
    -- Written as "PT|observe ..." lines for the events tool; polls twice a second and logs only changes.
    local lastPawn, lastPlayers
    LoopInGameThreadWithDelay(500, function()
        local pc = try(T.localPC)
        local pawn = pc and try(function() return pc.Pawn:IsValid() and label(pc.Pawn) or "none" end) or "none"
        if pawn ~= lastPawn then
            lastPawn = pawn
            T.log("PT|observe possess pawn=%s", pawn)
        end
        local names = {}
        for _, ps in ipairs(FindAllOf("PlayerState") or {}) do
            if ps:IsValid() and not ps:GetFullName():find("Default__", 1, true) and select(2, pcall(T.inWorld, ps)) == true then
                names[#names + 1] = tostring(try(function() return ps:GetPlayerName():ToString() end) or label(ps)):sub(1, 24)
            end
        end
        table.sort(names)
        local joined = table.concat(names, ",")
        if joined ~= lastPlayers then
            lastPlayers = joined
            T.log("PT|observe players n=%d %s", #names, joined)
        end
    end)
end
