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

-- Garage stations (Unmaker, fax, doors' keypads, storage ...): each level-placed BP_GarageInstallation_Spawner has an upgrade item in
-- its slot (a status effect of an ItemUpgrade class). The guest never loaded the host's save, so its slots are empty; the host lists
-- "spawner name -> installed upgrade classes" and the guest installs the missing ones with the spawner's own InstallSpecificUpgrade.
local function spawners()
    local r = {}
    for _, s in ipairs(FindAllOf("BP_GarageInstallation_Spawner_C") or {}) do
        if live(s) and not s:GetFullName():find("/Engine/Transient", 1, true) then r[#r + 1] = s end
    end
    return r
end
local function installed(s, im, sm)
    local a, t, r = {}, {}, {}
    s:GetUpgradeArchetype(a)
    s:GetInstallTag(t)
    if not (a.Archetype and a.Archetype:IsValid()) then return r end
    local item = im:FindOrCreateGarageUpgradeSlot(a.Archetype, t.Station):GetItem(0)
    if not (item and item:IsValid()) then return r end
    local list = sm:GetStatusEffects(item)
    for i = 1, #list do
        local e = list[i]:get()
        if e and e:IsValid() then r[#r + 1] = (e:GetClass():GetFullName():gsub("^%S+ ", "")) end
    end
    return r
end
local function managers()
    local im, sm = FindFirstOf("BP_InventoryManager_C"), FindFirstOf("BP_StatusEffectManager_C")
    if live(im) and live(sm) then return im, sm end
end
local function upgradeLines()
    local im, sm = managers()
    if not im then return nil end
    local L = {}
    for _, s in ipairs(spawners()) do
        local ok, r = pcall(installed, s, im, sm)
        if ok and #r > 0 then L[#L + 1] = s:GetFName():ToString() .. "\t" .. table.concat(r, ",") end
    end
    table.sort(L)
    return table.concat(L, "\n")
end

local done = {} -- guest: spawner full name .. class -> true once installed here
local function applyUpgrades(data)
    local im, sm = managers()
    if not im then return end
    local byName = {}
    for _, s in ipairs(spawners()) do byName[s:GetFName():ToString()] = s end
    for line in data:gmatch("[^\n]+") do
        local n, classes = line:match("^([^\t]+)\t(.*)$")
        local s = n and byName[n]
        if s then
            local have
            for c in classes:gmatch("[^,]+") do
                local key = s:GetFullName() .. c
                if not done[key] then
                    have = have or installed(s, im, sm)
                    local present = false
                    for _, h in ipairs(have) do if h == c then present = true end end
                    local cls = StaticFindObject(c)
                    if not (cls and cls:IsValid()) then cls = LoadAsset(c) end
                    if not present and cls and cls:IsValid() then
                        s:InstallSpecificUpgrade(cls, true)
                        log("PT|garage installed %s on %s", c:match("[^.]+$"), n)
                    end
                    if present or (cls and cls:IsValid()) then done[key] = true end
                end
            end
        end
    end
end

local last, lastSent, lastUp, lastUpSent, lastUpCheck = nil, 0, nil, 0, 0
local function hostTick()
    local s = readSwitches()
    if s and (s ~= last or os.clock() - lastSent > 3) then
        last, lastSent = s, os.clock()
        net.toGuests("g.garage.sw", s)
    end
    if os.clock() - lastUpCheck < 2 then return end
    lastUpCheck = os.clock()
    local u = upgradeLines()
    if u and (u ~= lastUp or os.clock() - lastUpSent > 4) then
        lastUp, lastUpSent = u, os.clock()
        net.toGuests("g.garage.up", u)
    end
end

local want, wantUp
net.on("g.garage.sw", function(_, data) want = data end)
net.on("g.garage.up", function(_, data) wantUp = data end)

local function guestTick()
    for _, s in ipairs(SW) do
        if s[3] then
            for _, d in ipairs(FindAllOf(s[3]) or {}) do if live(d) and d:IsTickEnabled() then d:SetTickEnabled(false) end end
        end
    end
    if wantUp then try("upgrades", applyUpgrades, wantUp) end
    local g = gi()
    if not (g and want) then return end
    for i, s in ipairs(SW) do
        local a = asset(s[1])
        local on = want:sub(i, i) == "1"
        if a:IsValid() and (g:GetGlobalSwitch(a) and true or false) ~= on then g:SetGlobalSwitch(a, FName(s[2]), on and 1 or 2) end
    end
end

RegisterLoadMapPostHook(function() done = {} end)

-- The guest presses the back-door button: its own press toggles its own switch, the host's copy of the button gets the same press
-- (the host's switch is the truth and comes back in g.garage.sw). Registered once the button's class is loaded (garage map).
local hooked = false
local function hookButton()
    if hooked or not live(FindFirstOf("BP_BackDoorButton_01_C")) then return end
    local ok = pcall(RegisterHook, "/Game/Gameplay/CarGarage/BP_BackDoorButton_01.BP_BackDoorButton_01_C:BndEvt__Highlight_K2Node_ComponentBoundEvent_0_OnHighlightInteract__DelegateSignature", function()
        if M.enabled and safety.guest() then net.toHost("g.garage.btn", "") end
    end)
    hooked = ok
end
net.on("g.garage.btn", function()
    local b = FindFirstOf("BP_BackDoorButton_01_C")
    if M.enabled and live(b) then
        b.Highlight:InteractPressed(nil)
        b.Highlight:InteractReleased(nil)
    end
end)

LoopInGameThreadWithDelay(500, function()
    if not M.enabled or not netted() then last, want = nil, nil return end
    try("hook", hookButton)
    if safety.guest() then try("guest", guestTick) elseif safety.active() then try("host", hostTick) end
end)

LoopInGameThreadWithDelay(50, function()
    if not M.enabled or not netted() then return end
    try("drive", driveDoors)
end)

M.readSwitches = readSwitches
return M
