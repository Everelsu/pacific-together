-- PT1 guest tool damage on car parts (player car and wrecks). The guest's scrapper damages the guest's own copy of a part;
-- the copy never breaks locally (no ghost drops) and the damage goes to the host as an intent. The host applies it to its real
-- part with the game's own damage message, so HP, breaking, the part's removal and the drops all happen there and come back
-- through car.lua (state) and loot.lua (D, items).
--   g.parts.dmg  kind id damage   kind C = car slot name, P = wreck part id (loot.lua)
-- Only the scrapper's message (MSG_Damage_Physical_Piercing_Scrapper) is forwarded; hammer, cutter and prybar are a known gap.
-- Inert outside a session (Q7).
local UEHelpers = require("UEHelpers")
local common = require("common")
local safety = require("safety")
local net = require("net")
local car = require("car")
local loot = require("loot")
local ga = require("guestact")
local log = common.log

local M = {}
if os.getenv("PT_MUTATE") == "noguestparts" then
    log("PT|guestparts disabled")
    return M
end

local COMP = "/Game/Gameplay/Inventory/GenericItemProperties/Components/"
local TOOL = "/Game/Gameplay/Inventory/Items/Tools/Scrapper/BP_Tool_Target_ItemHarvest_Scrapper.BP_Tool_Target_ItemHarvest_Scrapper_C"
local MSG = "/Game/Systems/Messages/MSG_Damage_Physical_Piercing_Scrapper.MSG_Damage_Physical_Piercing_Scrapper_C"
local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function guest() return common.netMode() == "client" and safety.active() end

-- host --------------------------------------------------------------------------------------------------------------------

local dummy -- a scrapper actor far away: the message's source (the game reads the harvest settings from it)
local function source()
    if valid(dummy) then return dummy end
    local gs, cls = UEHelpers.GetGameplayStatics(), StaticFindObject(TOOL)
    if not valid(cls) then pcall(LoadAsset, TOOL); cls = StaticFindObject(TOOL) end
    local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = -50000 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local a = gs:BeginDeferredActorSpawnFromClass(UEHelpers.GetWorld(), cls, xf, 1, nil)
    dummy = gs:FinishSpawningActor(a, xf)
    return dummy
end

net.on("g.parts.dmg", function(_, data)
    if common.netMode() ~= "listen" or not safety.active() then return end
    local kind, id, dmg = data:match("^(%a)\t([^\t]*)\t(.*)$")
    dmg = tonumber(dmg)
    if not (kind and dmg and dmg > 0 and dmg < 500) then return end
    local target
    if kind == "P" then target = loot.actorOf(id)
    else
        local cm = car.carManager()
        target = cm and car.manifestation(cm, id)
    end
    if not valid(target) then return end
    local src = source()
    local msg = StaticConstructObject(StaticFindObject(MSG), src)
    msg.Damage, msg.IsDamageOverTime, msg.ToolDispatched = dmg, true, true
    StaticFindObject("/Script/PenDriverPro.Default__BlueprintGameUtilities"):GetMessageSystem(src):DispatchMessage(msg, target)
    log("PT|parts damage %s %s %.2f", kind, id, dmg)
end)
-- guest -------------------------------------------------------------------------------------------------------------------

local acc, held = {}, {} -- "kind\tid" -> damage; hc address -> { hc, hp } the part's health before the damage, put back by the loop
local function targetOf(owner)
    local id = loot.idOf(owner)
    if id then return "P", id end
    local slot = ga.slotOf and ga.slotOf(owner)
    if slot then return "C", slot end
end
local function healthOf(hc)
    local t = { {}, {}, {}, {}, {}, {}, {}, {} }
    hc:GetHealth(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8])
    return t[1].Health, t[2].MaxHealth
end
local function mine(msg)
    return msg:GetClass():GetFName():ToString() == "MSG_Damage_Physical_Piercing_Scrapper_C"
end

-- lift the copy to full health so the damage cannot kill it (no local break, no ghost drops), keep the damage for the host
-- (UE4SS post callbacks did not fire next to a pre callback here, so the health goes back from the loop below)
local function pre(self, msg)
    if not guest() then return end
    local hc, m = self:get(), msg:get()
    if not mine(m) then return end
    local kind, id = targetOf(hc:GetOwner())
    if not kind then return end
    local hp, max = healthOf(hc)
    local key = hc:GetAddress()
    if not held[key] then held[key] = { hc = hc, hp = hp } end
    hc:SetHealth(max)
    local k = kind .. "\t" .. id
    acc[k] = (acc[k] or 0) + m.Damage
end

local hooked = false
LoopInGameThreadWithDelay(200, function()
    if not guest() then acc, held = {}, {}; return end
    -- only once a health component of the run map exists (a hook set while the menu is up did not survive the map load)
    if not hooked and valid(FindFirstOf("BP_HealthComponent_C")) and valid(car.theCar(false)) then
        hooked = pcall(RegisterHook, COMP .. "BP_HealthComponent.BP_HealthComponent_C:Process Damage Message", function(...)
            local ok, err = pcall(pre, ...)
            if not ok then log("PT|error guestparts pre %s", tostring(err)) end
        end, function() end)
        if hooked then log("PT|guestparts hooked") end
    end
    for _, h in pairs(held) do if valid(h.hc) then h.hc:SetHealth(h.hp) end end
    held = {}
    for key, dmg in pairs(acc) do
        log("PT|parts send %s %.2f", (key:gsub("\t", " ")), dmg)
        net.toHost("g.parts.dmg", key .. "\t" .. dmg)
    end
    acc = {}
end)

return M
