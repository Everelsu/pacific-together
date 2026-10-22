-- PT2 car upgrades: the host's ability parts play their effects (sound, particles, animation) on the guest's copy too (g.up.*).
--   capacity: batteries and tanks are car parts; car.lua's state message already installs them on the guest, so the guest's
--     aggregate capacity (dashboard battery bar, fuel gauge) follows. Nothing to do here, proven by scenario upgrades.
--   abilities (host -> guest): the physics run on the host. The part blueprints play their own sound and particles from
--     two kinds of calls, both seen on the host and replayed on the guest's matching part:
--       a  provider events (BP_AbilityProviderComponent:DoAbilityStarted/Ended): Boost, Juke, Power Grip, Spotlight. The guest
--          calls the same function on its provider with an ability object of the right class (a bare instance, never ticked).
--       f  the ability calls a function on the part directly (jump rack onJumpStart, shields and bubble OnAbilityStart/End,
--          anti-gravity OnStart/OnStop): the guest calls the same function on its part.
--   The Chrono Dilator is not replayed (safety.lua keeps its time dilation off).
--   guest: a press on the guest's own ability slot is dropped (abilities are the driver's).
-- Inert in single player: nothing runs without a listening host that has a guest, or a client.
local common = require("common")
local net = require("net")
local log = common.log

local M = {}
if os.getenv("PT_MUTATE") == "noupgrades" then
    log("PT|upgrades disabled (mutation noupgrades)")
    return M
end

local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function mode() return common.netMode() end
local function same(a, b) return valid(a) and valid(b) and a:GetFullName() == b:GetFullName() end
local function carCar()
    local ok, car = pcall(require, "car")
    return ok and type(car) == "table" and car.theCar and car.theCar(mode() == "listen") or nil
end

local ABIL = "/Game/Gameplay/Inventory/Items/Car/Abilities/"
local PROV = "/Game/Gameplay/Inventory/GenericItemProperties/Components/BP_AbilityProviderComponent.BP_AbilityProviderComponent_C:"
-- part classes whose effects come from provider events
local PROVIDER_PARTS = {
    BP_Attach_Util_Ability_Boost_Base_C = true, BP_Attach_Util_Ability_Juke_C = true, BP_Attach_Util_Ability_PowerGrip_C = true,
    BP_CarPart_Attach_SpotLight_01_C = true,
}
-- part functions the ability calls directly: asset, class, function
local DIRECT = {
    { ABIL .. "Abilities_Jump/BP_Attach_Util_Ability_Jump", "BP_Attach_Util_Ability_Jump_C", { "onJumpStart" } },
    { ABIL .. "Abilities_Shields/BP_Attach_Util_Ability_Shield_Base", "BP_Attach_Util_Ability_Shield_Base_C", { "OnAbilityStart", "OnAbilityEnd" } },
    { ABIL .. "Abilities_Shields/Bracer/BP_Attach_Util_Ability_Shield_Bracer", "BP_Attach_Util_Ability_Shield_Bracer_C", { "OnAbilityStart", "OnAbilityEnd" } },
    { ABIL .. "Abilities_Shields/Impact/BP_Attach_Util_Ability_Shield_Impact", "BP_Attach_Util_Ability_Shield_Impact_C", { "OnAbilityStart", "OnAbilityEnd" } },
    { ABIL .. "Abilities_BubbleShield_01/BP_Attach_Util_Ability_BubbleShield", "BP_Attach_Util_Ability_BubbleShield_C", { "OnAbilityStart", "OnAbilityEnd" } },
    { ABIL .. "Abilities_AntiGravity_01/BP_Attach_Util_Ability_AntiGravity", "BP_Attach_Util_Ability_AntiGravity_C", { "OnStart", "OnStop" } },
}
local SPOT = "/Game/Gameplay/Inventory/Items/Car/Lights/External/AimableSpotlight/BP_CarPart_Attach_SpotLight_01"

local function hosting() return mode() == "listen" and #net.guests() > 0 end

-- host: what the ability code does is sent ---------------------------------------------------------------------------------

local recent = {}
local function sendOnce(kind, data)
    local t = os.clock()
    if recent[data] and t - recent[data] < 0.1 then return end -- the Impact shield calls its base class's function too
    recent[data] = t
    net.toGuests(kind, data)
    log("PT|up sent %s %s", kind, data:gsub("\t", " "))
end

local function hookProvider(fn, flag)
    return pcall(RegisterHook, PROV .. fn, function(self)
        if not hosting() then return end
        local ok, err = pcall(function()
            local p = self:get()
            local own = p:GetOwner()
            local cls = valid(own) and own:GetClass():GetFName():ToString()
            if cls and PROVIDER_PARTS[cls] then sendOnce("g.up.a", cls .. "\t" .. flag) end
        end)
        if not ok then log("PT|error up provider hook %s", tostring(err)) end
    end, function() end)
end

local function hookDirect(asset, cls, fn)
    local name = asset:match("[^/]+$")
    return pcall(RegisterHook, asset .. "." .. name .. "_C:" .. fn, function(self)
        if not hosting() then return end
        local ok, err = pcall(function()
            local o = self:get()
            sendOnce("g.up.f", o:GetClass():GetFName():ToString() .. "\t" .. fn)
        end)
        if not ok then log("PT|error up direct hook %s", tostring(err)) end
    end, function() end)
end

local pending = nil
local function installHooks()
    if not pending then
        pending = { { "provider", "DoAbilityStarted", "1" }, { "provider", "DoAbilityEnded", "0" } }
        for _, d in ipairs(DIRECT) do for _, fn in ipairs(d[3]) do pending[#pending + 1] = { "direct", d[1], d[2], fn } end end
    end
    local left = {}
    for _, h in ipairs(pending) do
        -- only once the class is loaded: a RegisterHook on an unloaded part took ~240 ms and was retried every second while a
        -- guest was in, freezing both games every 1-2 s (local playtest 2026-10-22, PT|slow upgrades.lua)
        local cls = h[1] == "provider" and PROV:sub(1, -2) or (h[2] .. "." .. h[2]:match("[^/]+$") .. "_C")
        local ok = false
        if StaticFindObject(cls):IsValid() then
            if h[1] == "provider" then ok = hookProvider(h[2], h[3]) else ok = hookDirect(h[2], h[3], h[4]) end
        end
        if not ok then
            left[#left + 1] = h
            if not h.warned then h.warned = true; log("PT|up hook pending %s %s", tostring(h[2]), tostring(h[4])) end
        end
    end
    pending = left
    if #left == 0 and not M.hooked then M.hooked = true; log("PT|up hooks installed") end
end

-- guest: replay ---------------------------------------------------------------------------------------------------------

local function guestPart(cls)
    local car = carCar()
    if not car then return end
    for _, o in ipairs(FindAllOf(cls) or {}) do
        if valid(o) and same(o:GetAttachParentActor(), car) then return o end
    end
end

local abilities = {} -- provider address -> bare ability object of the part's ability class
local function abilityFor(p)
    local key = p:GetAddress()
    if valid(abilities[key]) then return abilities[key] end
    local t = { {}, {}, {}, {}, {}, {}, {}, {} }
    p:GetAbilityStatus(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8])
    local c = t[1].MyAbility
    if not valid(c) then return end
    local a = StaticConstructObject(c, p)
    abilities[key] = a
    return a
end

net.on("g.up.a", function(_, data)
    if mode() ~= "client" then return end
    local cls, flag = data:match("^([^\t]+)\t(%d)$")
    local part = cls and guestPart(cls)
    if not part then log("PT|up no part %s", tostring(cls)); return end
    local ok, err = pcall(function()
        local p = part.BP_AbilityProviderComponent
        local a = abilityFor(p)
        if not a then error("no ability class") end
        if flag == "1" then p:DoAbilityStarted(a) else p:DoAbilityEnded(a) end
    end)
    log("PT|up replay %s %s %s", cls, flag, ok and "ok" or tostring(err))
end)

net.on("g.up.f", function(_, data)
    if mode() ~= "client" then return end
    local cls, fn = data:match("^([^\t]+)\t(.+)$")
    local part = cls and guestPart(cls)
    if not part then log("PT|up no part %s", tostring(cls)); return end
    local ok, err = pcall(function() part[fn](part) end)
    log("PT|up replay %s %s %s", cls, fn, ok and "ok" or tostring(err))
end)

-- the guest does not fire abilities itself
local dropHooked = false
local function hookDrop()
    if dropHooked then return end
    local ok = pcall(RegisterHook, "/Script/PenDriverPro.AbilityContainer:SetAbilityPressed", function(_, slot, pressed)
        if mode() ~= "client" or not pressed:get() then return end
        pressed:set(false)
        log("PT|up guest ability press %d dropped", slot:get())
    end)
    dropHooked = ok
end

local lastTry = -math.huge
LoopInGameThreadWithDelay(1000, function()
    local m = mode()
    local ok, err = pcall(function()
        -- a missing part class costs ~60 ms to look up even unhooked: the ones still pending are retried every 30 s
        if m == "listen" and #net.guests() > 0 and (not pending or (#pending > 0 and os.clock() - lastTry > 30)) then
            lastTry = os.clock()
            installHooks()
        elseif m == "client" then hookDrop() end
    end)
    if not ok then log("PT|error up tick %s", tostring(err)) end
end)

-- car quirks ------------------------------------------------------------------------------------------------------------
-- Quirks are status effects on the host's car parts; their behaviours work the car manager (doors, lights, horn, wipers, radio,
-- engine, gearbox), and car.lua / carfeel.lua already carry those states to the guest. The interior light was missing: the
-- host's value is copied (g.up.i). The guest's own game must not roll quirks of its own: its quirk effects are removed.
local function first(class)
    for _, o in ipairs(FindAllOf(class) or {}) do if valid(o) then return o end end
end
local intSent, intWant, intAt, intHostAt, lastGuests = nil, nil, 0, 0, 0
net.on("g.up.i", function(_, data)
    if mode() == "client" then intWant = data == "1" end
end)
local function interiorTick()
    local cm = first("BP_CarManager_C")
    if not cm then return end
    if mode() == "listen" and #net.guests() > 0 then
        local v = cm.CarTopLightOnOff and "1" or "0"
        if #net.guests() > lastGuests or v ~= intSent or os.clock() - intHostAt > 3 then
            if v ~= intSent then log("PT|up interior light sent %s", v) end
            net.toGuests("g.up.i", v)
            intSent, intHostAt = v, os.clock()
        end
        lastGuests = #net.guests()
    elseif mode() == "client" and intWant ~= nil and cm.CarTopLightOnOff ~= intWant and os.clock() - intAt > 1 then
        local car = carCar()
        if car then
            intAt = os.clock()
            pcall(function() car:ToggleInteriorLight() end)
            log("PT|up interior light %s", tostring(intWant))
        end
    end
end

-- The quirk effects stations.lua mirrored from the host's list stay (the cure UI needs them); the guest's own rolls and every
-- SE_FAF_DoQuirkBehavior (what runs a behaviour) are removed.
local QUIRK_EFFECTS = { "SE_Quirk_MixAndMatch_C", "SE_FAF_DoQuirkBehavior_C" }
local function guestQuirkSweep()
    local sm = first("BP_StatusEffectManager_C")
    if not sm then return end
    local okS, stations = pcall(require, "stations")
    for _, class in ipairs(QUIRK_EFFECTS) do
        for _, e in ipairs(FindAllOf(class) or {}) do
            if valid(e) and not e:GetFullName():find("Default__", 1, true) and not e:GetFullName():find("_DIRECTOR_", 1, true)
                and not (class == "SE_Quirk_MixAndMatch_C" and okS and stations.mirrored and stations.mirrored(e)) then
                local name = e:GetFullName():sub(-70)
                pcall(function() sm:RemoveStatusEffect(e) end)
                log("PT|up guest quirk removed %s", name)
            end
        end
    end
end
LoopInGameThreadWithDelay(200, function()
    local ok, err = pcall(interiorTick)
    if not ok then log("PT|error up interior %s", tostring(err)) end
end)
LoopInGameThreadWithDelay(2000, function()
    if mode() ~= "client" then return end
    local ok, err = pcall(guestQuirkSweep)
    if not ok then log("PT|error up quirk sweep %s", tostring(err)) end
end)
return M
