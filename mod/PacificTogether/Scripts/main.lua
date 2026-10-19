local UEHelpers = require("UEHelpers")

local MOD_VERSION = "0.0.1"
local PROTOCOL_VERSION = 1
local TAG = "[PacificTogether] "

local function log(fmt, ...) print(TAG .. string.format(fmt, ...) .. "\n") end

-- Status lines are for the test runner only; players never set PT_STATUS, so the mod stays silent in single player.
local STATUS_MS = tonumber(os.getenv("PT_STATUS") or "")

local function netMode()
    local ksl, wco = UEHelpers.GetKismetSystemLibrary(), UEHelpers.GetWorldContextObject()
    if not wco:IsValid() then return "none" end
    if ksl:IsStandalone(wco) then return "standalone" end
    return ksl:IsServer(wco) and "listen" or "client"
end

local function status()
    local world = UEHelpers.GetWorld()
    local map = world:IsValid() and UEHelpers.GetGameplayStatics():GetCurrentLevelName(world, true):ToString() or "none"
    local pcs = 0
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        if pc:IsValid() then pcs = pcs + 1 end
    end
    log("PT|status net=%s map=%s pcs=%d", netMode(), map, pcs)
end

log("PT|boot version=%s protocol=%d", MOD_VERSION, PROTOCOL_VERSION)

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
