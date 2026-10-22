local UEHelpers = require("UEHelpers")

local M = {
    MOD_VERSION = "0.0.6",
    PROTOCOL_VERSION = 2,
}

function M.log(fmt, ...) print("[PacificTogether] " .. string.format(fmt, ...) .. "\n") end

-- UEHelpers.GetPlayerController/GetWorld run FindAllOf("PlayerController") per call (0.26 ms in a zone, measured 2026-10-22),
-- and every module calls them per item and per tick: keep the local controller and its world while they stay valid.
-- A new map makes new ones, so the old ones fail IsValid and are looked up again.
local rawPC, cachedPC, cachedWorld = UEHelpers.GetPlayerController, nil, nil
local function live(pc) return pc and pc:IsValid() and not pc:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
-- the stock helper returns the first player controller, on a host possibly a guest's: the local one is looked for here
function UEHelpers.GetPlayerController()
    if live(cachedPC) then return cachedPC end
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        if live(pc) and pc:IsLocalController() then cachedPC, cachedWorld = pc, nil; return pc end
    end
    return rawPC()
end
local rawWorld = UEHelpers.GetWorld
function UEHelpers.GetWorld()
    if live(cachedPC) and live(cachedWorld) then return cachedWorld end
    local w = rawWorld()
    if live(cachedPC) and live(w) then cachedWorld = w end
    return w
end

-- A StaticFindObject or RegisterHook path that is not loaded makes UE4SS scan every object (25-45 ms in a zone, 2026-10-22),
-- and modules retry hooks and asset lookups in loops until a class loads: look paths up in the engine's hash tables
-- (PTNative_Find, main.dll; registered after this script starts, so checked per call) and fail fast on a miss.
local rawFind, rawHook = StaticFindObject, RegisterHook
function StaticFindObject(path, ...)
    if PTNative_Find and type(path) == "string" and select("#", ...) == 0 then return PTNative_Find(path) or CreateInvalidObject() end
    return rawFind(path, ...)
end
function RegisterHook(path, ...)
    if PTNative_Find and type(path) == "string" and not PTNative_Find(path) then error("RegisterHook: " .. path .. " is not loaded") end
    return rawHook(path, ...)
end

-- object lookups per class, for main.lua's PT|perf report (which loops cost what)
M.lookups = {}
local function counted(name, raw)
    return function(class, ...)
        local t = os.clock()
        local r = raw(class, ...)
        local byClass = M.lookups[name] or {}
        M.lookups[name] = byClass
        local c = byClass[class] or { total = 0, n = 0 }
        byClass[class] = c
        c.total, c.n = c.total + os.clock() - t, c.n + 1
        return r
    end
end
FindAllOf, FindFirstOf = counted("FindAllOf", FindAllOf), counted("FindFirstOf", FindFirstOf)

-- Singletons (managers, the game instance) were looked up hundreds of times a minute each (PT|perf lookup, 2026-10-22): the
-- one found is kept while it is live, and every map load drops them all (the old world's go with it).
local SINGLE = { DrivingGameInstance = true, BP_ResourceManager_C = true, BP_InventoryManager_C = true, BP_MainCharacterManager_C = true,
    BP_CarManager_C = true, BP_StatusEffectManager_C = true, BP_ProgressionManager_C = true, BP_QuestManager_C = true,
    BP_DialogueManager_C = true, MessageSystem = true, InventorySystem = true, BP_SaveGameManager_C = true, BP_MusicManager_C = true }
local singles = {}
local rawFirst = FindFirstOf
function FindFirstOf(class)
    if not SINGLE[class] then return rawFirst(class) end
    local o = singles[class]
    if live(o) then return o end
    o = rawFirst(class)
    if live(o) then singles[class] = o end
    return o
end
-- the cached controller and world too: a freed object's address can come back as another object, which IsValid cannot tell
local function forget() singles, cachedPC, cachedWorld = {}, nil, nil end
RegisterLoadMapPreHook(forget)
RegisterLoadMapPostHook(forget)

function M.netMode()
    local ksl, wco = UEHelpers.GetKismetSystemLibrary(), UEHelpers.GetWorldContextObject()
    if not wco:IsValid() then return "none" end
    if ksl:IsStandalone(wco) then return "standalone" end
    return ksl:IsServer(wco) and "listen" or "client"
end

return M
