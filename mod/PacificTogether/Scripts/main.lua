local UEHelpers = require("UEHelpers")
local common = require("common")
local log = common.log

-- One file per feature, so parallel work does not collide; each module sets itself up when required.
local FEATURES = { "overlay", "steam", "session", "safety", "nametag", "health", "world", "anomalies", "anomalies2", "car", "loot", "backpack", "guestact", "story", "progression", "garage", "guestparts", "carfeel", "guestswap", "anomalies3", "mapmark", "ping", "upgrades", "stations", "hands", "visual" }

-- Status lines are for the test runner only; players never set PT_STATUS, so the mod stays silent in single player.
local STATUS_MS = tonumber(os.getenv("PT_STATUS") or "")

local function status()
    local world = UEHelpers.GetWorld()
    local map = world:IsValid() and UEHelpers.GetGameplayStatics():GetCurrentLevelName(world, true):ToString() or "none"
    local pcs = 0
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        if pc:IsValid() then pcs = pcs + 1 end
    end
    log("PT|status net=%s map=%s pcs=%d", common.netMode(), map, pcs)
end

log("PT|boot version=%s protocol=%d", common.MOD_VERSION, common.PROTOCOL_VERSION)

-- hitch finder (playtest 2026-10-22: both games froze every 2-3 s): a loop or hook body over 30 ms is logged with where it was registered
local function timed(fn, where)
    return function(...)
        local t = os.clock()
        local r = table.pack(fn(...))
        local d = os.clock() - t
        if d > 0.03 then log("PT|slow %s %.0f ms", where, d * 1000) end
        return table.unpack(r, 1, r.n)
    end
end
local function caller() -- the module line, past pcall
    for lv = 3, 8 do
        local i = debug.getinfo(lv, "Sl")
        if not i then break end
        if i.what ~= "C" then return i.short_src:match("[^/\\]+$") .. ":" .. i.currentline end
    end
    return "?"
end
local rawLoop, rawHook = LoopInGameThreadWithDelay, RegisterHook
LoopInGameThreadWithDelay = function(ms, fn) return rawLoop(ms, timed(fn, caller())) end
RegisterHook = function(name, pre, post)
    local where = caller()
    if post then return rawHook(name, timed(pre, where), timed(post, where)) end
    return rawHook(name, timed(pre, where))
end

for _, name in ipairs(FEATURES) do
    local ok, err = pcall(require, name)
    -- a feature that is not written yet is fine; one that fails to load is an error the tests catch
    if not ok and not tostring(err):find("module '" .. name .. "' not found", 1, true) then
        log("PT|error feature %s %s", name, tostring(err))
    end
end

-- the native layer registers its functions only after this script has started
ExecuteInGameThreadWithDelay(1000, function()
    log("PT|native version=%s", PTNative_Version and PTNative_Version() or "missing")
end)

if STATUS_MS then
    LoopInGameThreadWithDelay(STATUS_MS, function()
        local ok, err = pcall(status)
        if not ok then log("PT|error status %s", tostring(err)) end
    end)
end
