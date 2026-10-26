-- Messages between host and guest for features (intents up, state down), on the native channel (msg.cpp).
-- Kinds start with "g." (the test mod owns "t."). Handlers run on the game thread: fn(fromPC, data); on the guest
-- fromPC is its own controller (the host is the only sender).
--   local net = require("net")
--   net.on("g.car", function(pc, data) ... end)
--   net.toHost("g.repair", data)   guest      net.toGuests("g.car", data)   host
local UEHelpers = require("UEHelpers")
local common = require("common")
local log = common.log

local M = {}
local handlers = {}

function M.on(kind, fn) handlers[kind] = fn end
M.heardAt = {} -- kind -> os.clock() when its last message was handled

local function localPC()
    local pc = UEHelpers.GetPlayerController()
    return pc and pc:IsValid() and pc or nil
end

-- every send and every received message looked the controllers up (1340 times a minute on a host, PT|perf 2026-10-22):
-- the list is reused for 100 ms; a sender not in it looks again
local pcs, pcsAt = {}, -1
RegisterLoadMapPreHook(function() pcs, pcsAt = {}, -1 end)
local function controllers(fresh)
    if fresh or os.clock() - pcsAt > 0.1 then pcs, pcsAt = FindAllOf("PlayerController") or {}, os.clock() end
    return pcs
end

-- the host's controllers for its guests
function M.guests()
    local list = {}
    for _, pc in ipairs(controllers()) do
        if pc:IsValid() and not pc:IsLocalController() then list[#list + 1] = pc end
    end
    return list
end

function M.toHost(kind, data)
    local pc = localPC()
    return pc ~= nil and PTNative_MsgToHost ~= nil and PTNative_MsgToHost(pc:GetAddress(), kind, data or "")
end

function M.toGuest(pc, kind, data)
    return pc:IsValid() and PTNative_MsgToGuest ~= nil and PTNative_MsgToGuest(pc:GetAddress(), kind, data or "")
end

function M.toGuests(kind, data)
    local n = 0
    for _, pc in ipairs(M.guests()) do if M.toGuest(pc, kind, data) then n = n + 1 end end
    return n
end

local function sender(address)
    for _, fresh in ipairs({ false, true }) do
        for _, pc in ipairs(controllers(fresh)) do
            if pc:IsValid() and pc:GetAddress() == address then return pc end
        end
    end
end

local function dispatch()
    if not PTNative_MsgPoll then return end
    while true do
        local kind, data, from = PTNative_MsgPoll("g.")
        if not kind then return end
        local fn, pc = handlers[kind], sender(from)
        if not fn then
            log("PT|error net no handler for %s", kind)
        elseif pc then
            local t0 = os.clock()
            local ok, err = pcall(fn, pc, data)
            if not ok then log("PT|error net %s %s", kind, tostring(err)) end
            M.heardAt[kind] = os.clock()
            -- which handler holds the frame (playtest 2026-10-24: this loop took 0.7-2.2 s at a time on both sides)
            if M.heardAt[kind] - t0 > 0.05 then log("PT|slow net %s %.0f ms %d bytes", kind, (M.heardAt[kind] - t0) * 1000, #data) end
        end
    end
end

-- every frame: intents should feel instant
LoopInGameThreadWithDelay(16, function()
    local ok, err = pcall(dispatch)
    if not ok then log("PT|error net dispatch %s", tostring(err)) end
end)

-- A connection may send CurrentNetSpeed bytes per second, but its budget grows per net tick by a clamped frame time (our
-- reading of UNetConnection::Tick, not checked in the binary): at 16 fps (two rendered games on the owner's laptop) the 100000
-- the game negotiates was far less in practice. One window of our chunks
-- (~48 KB) or a joining guest's state saturated it, and a saturated connection gets no actor replication and no move acks:
-- the host stood still on the guest's screen for minutes and the guest hit "96 saved moves" (rendered lane 2026-10-24, engine
-- log "Saturated. Mark PDP_MainCharacter_C NetUpdateTime"). 1 MB/s drained a 300 KB burst in under 3 s; at 100000 the
-- guest saw nothing for 15 s and more. Real bandwidth stays what the game and we actually send.
local SPEED = os.getenv("PT_MUTATE") == "oldspeed" and 0 or 1000000
LoopInGameThreadWithDelay(500, function()
    if SPEED == 0 then return end
    pcall(function()
        for _, pc in ipairs(controllers()) do
            local nc = pc:IsValid() and pc.NetConnection
            if nc and nc:IsValid() and nc.CurrentNetSpeed < SPEED then
                nc.CurrentNetSpeed = SPEED
                local d = nc.Driver
                if d and d:IsValid() and d.MaxClientRate < SPEED then d.MaxClientRate, d.MaxInternetClientRate = SPEED, SPEED end
                log("PT|net speed %s raised to %d", pc:IsLocalController() and "to host" or "to guest", SPEED)
            end
        end
    end)
end)

return M
