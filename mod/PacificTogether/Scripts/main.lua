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
-- An error escaping a hook went back into UE4SS and the guest's game closed without a crash report (host dropped items next to
-- the guest, local playtest 2026-10-22): caught here and logged with where the hook was registered.
local function timed(fn, where)
    return function(...)
        local t = os.clock()
        local r = table.pack(pcall(fn, ...))
        local d = os.clock() - t
        if d > 0.03 then log("PT|slow %s %.0f ms", where, d * 1000) end
        if not r[1] then log("PT|error in %s: %s", where, tostring(r[2])); return end
        return table.unpack(r, 2, r.n)
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
-- loops only: wrapping RegisterHook callbacks was followed by a never-seen hook error and a guest crash (2026-10-22)
local rawLoop = LoopInGameThreadWithDelay
LoopInGameThreadWithDelay = function(ms, fn) return rawLoop(ms, timed(fn, caller())) end

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
