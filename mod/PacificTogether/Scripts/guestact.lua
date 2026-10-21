-- The guest works on the car and uses the ARC (C5, W11, D13, D22). The guest's own game runs the interaction (tool in hand,
-- ARC screen); what it does to the car is turned into an intent, the HOST applies it to its real car with the game's own
-- functions, and car.lua's state message shows the result on both sides. Item consumption stays in the guest's backpack.
--   g.act.heal  slot amount        repair putty on a part (BP_Tool_Target_Consumable_PatchKit:PatchPart)
--   g.act.fuel  slot class amount  fuel can into / out of the car (BP_FuelableComponent:TransferFuel), amount < 0 = siphoned
--   g.act.bat   slot amount        battery charger on a part (BP_Tool_Target_Consumable_ChargeBattery_Base:ChargeBattery)
--   g.act.gate  portal             gateway summon at the ARC (screen part OnExitUseComplete)
--   g.act.anchor archetype         anchor deposited into the ARC (Gobbler AddingAnchorCompleteLogic)
-- Part install/remove is the same container the state message mirrors; the guest's own changes are overwritten by the host's state.
-- Inert outside a session (Q7).
local UEHelpers = require("UEHelpers")
local common = require("common")
local safety = require("safety")
local net = require("net")
local car = require("car")
local log = common.log
local ov = require("overlay")

local M = {}
if os.getenv("PT_MUTATE") == "noguestact" or not car.theCar then
    log("PT|guestact disabled")
    return M
end

local COMP = "/Game/Gameplay/Inventory/GenericItemProperties/Components/"
local TOOLS = "/Game/Gameplay/Inventory/Items/Tools/"
local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function same(a, b) return valid(a) and valid(b) and a:GetFullName() == b:GetFullName() end
local function try(what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then log("PT|error guestact %s %s", what, tostring(err)) end
end
local function now() return os.clock() end

local function slotOf(actor)
    local cm, cont = car.carManager(), car.equipped()
    if not (valid(actor) and cm and cont) then return end
    local found
    cont.Slots:ForEach(function(_, e)
        local slot = e:get()
        if not found and car.itemOf(slot) then
            local name = car.slotName(slot)
            if same(car.manifestation(cm, name), actor) then found = name end
        end
    end)
    return found
end
local function fuelComps(m) -- every fuelable component of a part (the gas cap passes fuel on to the tanks)
    local r = {}
    for _, x in ipairs(m:K2_GetComponentsByClass(StaticFindObject(COMP .. "BP_FuelableComponent.BP_FuelableComponent_C"))) do r[#r + 1] = x:get() end
    return r
end
local function fuelOf(c)
    local t = { {}, {}, {}, {}, {}, {}, {} }
    c:GetFuelStatus(t[1], t[2], t[3], t[4], t[5], t[6], t[7])
    return t[1].Fuel
end
-- the car part (slot name) a component belongs to, nil for a component that is not on the car (the can in the backpack)
local function carSlotOf(comp)
    local owner = comp:GetOwner()
    return valid(owner) and slotOf(owner) or nil
end

-- host: apply intents -----------------------------------------------------------------------------------------------------

local function split(s) local t = {} for x in (s .. "\t"):gmatch("([^\t]*)\t") do t[#t + 1] = x end return t end
local function hostCar() return common.netMode() == "listen" and safety.active() end

local function partComps(slot)
    local cm = car.carManager()
    local m = cm and car.manifestation(cm, slot)
    return m, m and car.propComps(m)
end

net.on("g.act.heal", function(_, data)
    if not hostCar() then return end
    local f = split(data)
    local m, c = partComps(f[1])
    local amount = tonumber(f[2])
    if c and c.h and amount and amount > 0 and amount < 1000 then
        c.h:HealDamage(amount, false, {}, {}, {})
        log("PT|act heal %s %.2f", f[1], amount)
        ov.post(ov.other() .. " repaired " .. f[1]:match("[^%.]+$"), "good", "act.heal")
    end
end)

net.on("g.act.fuel", function(_, data)
    if not hostCar() then return end
    local f = split(data)
    local cm = car.carManager()
    local m = cm and car.manifestation(cm, f[1])
    local amount = tonumber(f[3])
    if not (m and amount and math.abs(amount) < 1000) then return end
    for _, c in ipairs(fuelComps(m)) do
        if c:GetClass():GetFName():ToString() == f[2] then
            if amount > 0 then c["Give Fuel"](c, amount, {}, {}) else c["Take Fuel"](c, -amount, {}, {}) end
            log("PT|act fuel %s %.2f", f[1], amount)
            ov.post(ov.other() .. (amount > 0 and " refuelled " or " siphoned fuel from ") .. f[1]:match("[^%.]+$"), "good", "act.fuel")
            return
        end
    end
end)

net.on("g.act.bat", function(_, data)
    if not hostCar() then return end
    local f = split(data)
    local m, c = partComps(f[1])
    local amount = tonumber(f[2])
    if c and c.b and amount and amount > 0 and amount < 1000 then
        local t = { {}, {}, {}, {}, {} }
        c.b:GetBatteryStatus(t[1], t[2], t[3], t[4], t[5])
        -- Set Battery does not clamp
        c.b["Set Battery"](c.b, math.min(t[1].BATTERY + amount, t[2]["Battery Capacity"] or math.huge))
        pcall(function() car.carManager():UpdateAggregateBattery() end)
        log("PT|act battery %s %.2f", f[1], amount)
        ov.post(ov.other() .. " charged " .. f[1]:match("[^%.]+$"), "good", "act.bat")
    end
end)

-- the gateway: the ARC screen's own gate (charged, able to choose) is checked here because the guest's UI is not trusted
net.on("g.act.gate", function(_, data)
    if not hostCar() then return end
    local screen, sm
    for _, o in ipairs(FindAllOf("BP_Carpart_Internal_GobblerScreen_C") or {}) do if valid(o) then screen = o break end end
    for _, o in ipairs(FindAllOf("BP_StormManager_C") or {}) do if valid(o) then sm = o break end end
    if not (screen and sm) then log("PT|act gate: no ARC screen or storm manager"); return end
    if not screen.AbleToChooseExit then log("PT|act gate refused (ARC not charged or exit already chosen)"); return end
    for _, p in ipairs(FindAllOf("BP_LevelTransition_ExitPortal_C") or {}) do
        if valid(p) and p:GetFName():ToString() == data then
            sm["Select Exit Portal Actor"](sm, p)
            log("PT|act gate selected %s", data)
            ov.post(ov.other() .. " summoned the gateway", "good")
            return
        end
    end
    log("PT|act gate: no portal %s", data)
end)

net.on("g.act.anchor", function(_, data)
    if not hostCar() then return end
    local gob
    for _, o in ipairs(FindAllOf("BP_Carpart_Internal_Gobbler_C") or {}) do if valid(o) then gob = o break end end
    local arch = StaticFindObject(data)
    if not (gob and valid(arch)) then log("PT|act anchor: no gobbler or archetype %s", data); return end
    gob:AddingAnchorCompleteLogic(arch:CreateInstance(UEHelpers.GetWorldContextObject(), 0))
    log("PT|act anchor %s", data)
    ov.post(ov.other() .. " deposited an anchor", "good")
end)

-- ARC energy: the host's charge (Gobbler item properties) and the screen's "charged" flag are mirrored once a second, so the guest's
-- screen shows the energy and lets the guest pick a gateway; deposits are intents (g.act.anchor)
local IP_GOBBLER = "/Game/Gameplay/Inventory/Items/Car/Internal/Gobbler/IP_Gobbler.IP_Gobbler"
local function bits(x) return (string.unpack("<i4", string.pack("<f", x))) end -- SetItemProperty takes the float's raw bits
local function arcState()
    local cm, screen = car.carManager(), nil
    for _, o in ipairs(FindAllOf("BP_Carpart_Internal_GobblerScreen_C") or {}) do if valid(o) then screen = o break end end
    local widget
    for _, o in ipairs(FindAllOf("UMG_GobblerScreen_C") or {}) do if valid(o) then widget = o break end end
    if not (cm and screen) then return end
    local has, item, man = {}, {}, {}
    cm:GetGobblerItem(has, item, man)
    return screen, widget, has.HasItem and item.Item or nil
end
local lastArc, arcAt = nil, 0
local function arcHost()
    local screen, widget = arcState()
    if not screen then return end
    local c, m = {}, {}
    screen:GetAnchorCharge(c, m)
    local s = string.format("%.3f\t%.3f\t%d", c.CurrentCharge, m.MaxCharge, (widget and widget.Charged) and 1 or 0)
    if s ~= lastArc or os.clock() - arcAt > 3 then
        lastArc, arcAt = s, os.clock()
        net.toGuests("g.act.arc", s)
    end
end
net.on("g.act.arc", function(_, data)
    if common.netMode() ~= "client" then return end
    local f = split(data)
    local screen, widget, inst = arcState()
    if not (screen and inst) then return end
    local lib = StaticFindObject("/Script/PenDriverInventory.Default__InventoryBlueprintLibrary")
    local ip = StaticFindObject(IP_GOBBLER)
    local c, m = {}, {}
    screen:GetAnchorCharge(c, m)
    if math.abs(c.CurrentCharge - tonumber(f[1])) > 0.01 then lib:SetItemProperty(ip, inst, FName("CurrentCharge"), bits(tonumber(f[1]))) end
    if math.abs(m.MaxCharge - tonumber(f[2])) > 0.01 then lib:SetItemProperty(ip, inst, FName("MaxCharge"), bits(tonumber(f[2]))) end
    if widget and (widget.Charged and 1 or 0) ~= tonumber(f[3]) then widget.Charged = f[3] == "1" end
end)

-- guest: hooks on the game's effect points -------------------------------------------------------------------------------------

local function guest() return common.netMode() == "client" and safety.active() end

-- UE4SS runs these hooks after the Blueprint function has returned, so out parameters hold the result. A heal or charge is
-- first noted by the component's own function and sent only when the tool that does it confirms (the guest's own car systems
-- and garage stations call the same functions and are not the guest's work).
local noted = {}
local function note(kind, comp, amount)
    local slot = carSlotOf(comp)
    if slot and amount and amount > 0.005 then noted[#noted + 1] = { kind = kind, slot = slot, amount = amount, at = now() } end
end
local function confirm(kind, actor)
    local slot = slotOf(actor)
    local keep, t = {}, now()
    for _, n in ipairs(noted) do
        if n.kind == kind and n.slot == slot and t - n.at < 0.5 then
            log("PT|act send %s %s %.3f", kind, slot, n.amount)
            net.toHost("g.act." .. kind, slot .. "\t" .. n.amount)
        elseif t - n.at < 0.5 then
            keep[#keep + 1] = n
        end
    end
    noted = keep
end

local function healNote(self, _, _, healed)
    if guest() then note("heal", self:get(), healed:get()) end
end
local function chargeNote(self, _, charged)
    if guest() then note("bat", self:get(), charged:get()) end
end
local function healHook(self)
    if guest() then confirm("heal", self:get().TargetedActor) end
end
local function batHook(self)
    if guest() then confirm("bat", self:get().TargetedActor) end
end

local function fuelHook(self, src, dst, _, moved)
    if not guest() then return end
    local s, d, amount = src:get(), dst:get(), moved:get()
    local ss, ds = carSlotOf(s), carSlotOf(d)
    -- exactly one side is the car; the other one is the can the guest carries
    if (ss == nil) == (ds == nil) or not amount or amount <= 0.0001 then return end
    local slot, cc, sign = ds, d, 1 -- from the can into the car
    if ss then slot, cc, sign = ss, s, -1 end -- siphoned out of the car
    log("PT|act send fuel %s %.3f", slot, sign * amount)
    net.toHost("g.act.fuel", slot .. "\t" .. cc:GetClass():GetFName():ToString() .. "\t" .. sign * amount)
end

-- the hook runs after OnExitUseComplete, which would already have summoned locally: the guest's screen never may choose on its own
local function holdGate()
    for _, o in ipairs(FindAllOf("BP_Carpart_Internal_GobblerScreen_C") or {}) do
        if valid(o) and not o.ExitSelected and o.AbleToChooseExit then o.AbleToChooseExit = false end
    end
end
local function gateHook(self, portal)
    if not guest() then return end
    local name = portal:get():GetFName():ToString()
    log("PT|act gate intent %s", name)
    net.toHost("g.act.gate", name)
end

local function anchorHook(self, inst)
    if not guest() then return end
    local i = inst:get()
    if not valid(i) then return end
    local path = i.Archetype:GetFullName():match("^%S+ ([^%.]+)")
    if not path then return end
    path = path .. "." .. path:match("([^/]+)$")
    log("PT|act anchor intent %s", path)
    net.toHost("g.act.anchor", path)
end

local HOOKS = {
    { TOOLS .. "PatchKit/BP_Tool_Target_Consumable_PatchKit.BP_Tool_Target_Consumable_PatchKit_C:PatchPart", healHook },
    { TOOLS .. "BatteryCharger/Consumable/BP_Tool_Target_Consumable_ChargeBattery_Base.BP_Tool_Target_Consumable_ChargeBattery_Base_C:ChargeBattery", batHook },
    { COMP .. "BP_FuelableComponent.BP_FuelableComponent_C:TransferFuel", fuelHook },
    { COMP .. "BP_HealthComponent.BP_HealthComponent_C:HealDamage", healNote },
    { COMP .. "BP_BatteryComponent.BP_BatteryComponent_C:ChargeBattery", chargeNote },
    { "/Game/Gameplay/Inventory/Items/Car/Internal/Gobbler/BP_Carpart_Internal_GobblerScreen.BP_Carpart_Internal_GobblerScreen_C:OnExitUseComplete", gateHook },
    { "/Game/Gameplay/Inventory/Items/Car/Internal/Gobbler/BP_Carpart_Internal_Gobbler.BP_Carpart_Internal_Gobbler_C:AddingAnchorCompleteLogic", anchorHook },
}
local done = {}
local function hookAll()
    for i, h in ipairs(HOOKS) do
        if not done[i] then
            local fn = h[2]
            -- the Blueprint may not be loaded yet: retried every tick
            local ok = pcall(RegisterHook, h[1], function(...)
                local ok2, err = pcall(fn, ...)
                if not ok2 then log("PT|error guestact hook %d %s", i, tostring(err)) end
            end)
            if ok then done[i] = true; log("PT|guestact hooked %d", i) end
        end
    end
end

-- slow on purpose: every call here walks the object array, and the guest's camera in a moving car notices a hitch
local beat = 0
LoopInGameThreadWithDelay(1000, function()
    if not guest() then noted = {}; return end
    beat = beat + 1
    try("gate", holdGate)
    if beat % 2 == 0 then try("hook", hookAll) end
end)

LoopInGameThreadWithDelay(1000, function()
    if hostCar() then try("arc", arcHost) end
end)

return M
