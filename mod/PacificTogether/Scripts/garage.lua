-- PT1 garage: doors for both players (docs/spikes/PT1-garage.md).
--   The garage doors' Logic Driver state machines never leave Closed in a listen/client session (playtest 1: no door ever moved),
--   so in a session the door position is driven here from the door's global switch. The guest's own directors would decide the
--   switches from the guest's fresh game, so they are stopped there and the host's three switches ("g.garage.sw") are applied.
-- Inert in single player (Q7): only runs as a listening host or a guest.
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

-- MoveDoorPosition is the call the state machine makes every tick; here it runs over MoveDuration seconds.
-- shortcut: no obstruction check (the machine reverses a rear door that hits something); add one if players get crushed.
local lastDrive = os.clock()
local function driveDoors()
    local now = os.clock()
    local dt = math.min(now - lastDrive, 0.25)
    lastDrive = now
    local g = gi()
    if not g then return end
    for _, d in ipairs(FindAllOf("BP_GarageDoor_C") or {}) do
        if live(d) and not d:GetFullName():find("/Engine/Transient", 1, true) then
            local a = asset(d.IsFrontGarageDoor and SW[1][1] or SW[2][1])
            if a:IsValid() then
                local target = g:GetGlobalSwitch(a) and 1 or 0
                local pos = d.CurrentDoorPosition
                if math.abs(target - pos) > 0.001 then
                    local step = math.min(dt / math.max(d.MoveDuration, 0.5), math.abs(target - pos))
                    d:MoveDoorPosition(target > pos and step or -step)
                end
            end
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
    if safety.guest() then try("guest", guestTick) elseif safety.active() then try("host", hostTick) end
end)

LoopInGameThreadWithDelay(50, function()
    if not M.enabled or not netted() then return end
    try("drive", driveDoors)
end)

M.readSwitches = readSwitches
return M
