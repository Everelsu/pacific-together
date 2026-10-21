-- PT1 garage: doors and garage upgrades for both players (docs/spikes/PT1-garage.md).
--   doors     the garage doors' Logic Driver state machines are configured "Client" only: in a listen/client session the host never
--             ticks them and no door ever moves. Both sides set them to client-and-server. The guest's own directors would decide the
--             door switches from the guest's fresh game, so they are stopped there and the host's three switches ("g.garage.sw") drive it.
-- Inert in single player (Q7): only runs as a listening host or a guest.
local UEHelpers = require("UEHelpers")
local common = require("common")
local safety = require("safety")
local net = require("net")
local log = common.log

local M = { enabled = os.getenv("PT_MUTATE") ~= "nogarage" }

local function live(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function try(what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then log("PT|error garage %s %s", what, tostring(err)) end
end

-- switch asset, the state name the game itself uses for it, the guest's director that writes it
local SW = {
    { "GSS_Garage_FrontDoorOpened", "LegSelectedAndEmbark", "BP_Director_GSS_GarageFrontDoor_C" },
    { "GSS_Garage_RearDoorOpened", "ButtonToggle" },
    { "GSS_Garage_ExitGateOpened", "GarageFrontDoor", "BP_Director_GSS_GarageExitGate_C" },
}
local function asset(n) return StaticFindObject("/Game/Systems/GlobalStateSwitches/" .. n .. "." .. n) end
local function gi() local g = FindFirstOf("DrivingGameInstance"); return live(g) and g or nil end

local function netted() local m = common.netMode(); return m == "listen" or m == "client" end

local fixed, seen = {}, {} -- door full name -> configured / first seen (a map load makes new doors; touching one during the load crashed)
local function fixDoors()
    for _, d in ipairs(FindAllOf("BP_GarageDoor_C") or {}) do
        local n = live(d) and d:GetFullName()
        if n and not n:find("/Engine/Transient", 1, true) and not fixed[n] then seen[n] = seen[n] or os.clock() end
        if n and seen[n] and not fixed[n] and os.clock() - seen[n] > 4 then
            local c = d.DoorStateMachine
            c.NetworkTickConfiguration = 2
            c.NetworkTransitionConfiguration = 2
            -- the switch's position at load, which the stalled machine missed (ForceDoorToCompletion crashed the game here)
            local g, a = gi(), asset(d.IsFrontGarageDoor and SW[1][1] or SW[2][1])
            if g and a:IsValid() and g:GetGlobalSwitch(a) then pcall(function() d["DbgActEvt_Force Open Door_Execute"](d) end) end
            fixed[n] = true
            log("PT|garage door %s fixed", d:GetFName():ToString())
        end
    end
end

local function readSwitches()
    local g = gi()
    if not g then return nil end
    local t = {}
    for i, s in ipairs(SW) do
        local a = asset(s[1])
        t[i] = (a:IsValid() and g:GetGlobalSwitch(a)) and "1" or "0"
    end
    return table.concat(t)
end

local last, lastSent = nil, 0
local function hostTick()
    local s = readSwitches()
    if not s then return end
    if s ~= last or os.clock() - lastSent > 3 then
        last, lastSent = s, os.clock()
        net.toGuests("g.garage.sw", s)
    end
end

local want
net.on("g.garage.sw", function(_, data) want = data end)

local function guestTick()
    for _, s in ipairs(SW) do
        if s[3] then
            for _, d in ipairs(FindAllOf(s[3]) or {}) do if live(d) and d:IsTickEnabled() then d:SetTickEnabled(false) end end
        end
    end
    local g = gi()
    if not (g and want) then return end
    for i, s in ipairs(SW) do
        local a = asset(s[1])
        local on = want:sub(i, i) == "1"
        if a:IsValid() and (g:GetGlobalSwitch(a) and true or false) ~= on then g:SetGlobalSwitch(a, FName(s[2]), on and 1 or 2) end
    end
end

LoopInGameThreadWithDelay(500, function()
    if not M.enabled or not netted() then last, want = nil, nil return end
    try("doors", fixDoors)
    if safety.guest() then try("guest", guestTick) elseif safety.active() then try("host", hostTick) end
end)

M.readSwitches = readSwitches
return M
