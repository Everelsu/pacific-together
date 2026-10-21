local UEHelpers = require("UEHelpers")
local common = require("common")
local log = common.log

-- One file per feature, so parallel work does not collide; each module sets itself up when required.
local FEATURES = { "overlay", "session", "safety", "nametag", "health", "world", "anomalies", "anomalies2", "car", "loot", "backpack", "guestact", "story", "progression", "garage" }

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
