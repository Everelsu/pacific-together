-- Anomalies, third pass (W6). The host runs every hazard; what the guest still lacks (docs/spikes/PT1-anom3.md):
--   bunny (Loot Creature)  its push (radial impulse + MSG_Damage_Physical_Impact, PushDamage) goes to the host's character only: a guest's pawn within
--                          PushRadius of the creature gets the game's own damage (anomalies.lua forwards it) and the impulse, applied by the guest.
-- Spark Tower (Tesla) and Pickpocket (Part Stealer) needed nothing beyond anomalies.lua, car.lua and world.lua if the scenario says so.
-- Inert outside a session (Q7).
local UEHelpers = require("UEHelpers")
local common = require("common")
local net = require("net")
local safety = require("safety")
local ov = require("overlay")
local log = common.log

local M = { enabled = os.getenv("PT_MUTATE") ~= "noanom3", pushed = 0, applied = 0 } -- the test mutation switches the module off
local function try(what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then log("PT|error anomalies3 %s %s", what, tostring(err)) end
end

local IMPACT = "/Game/Systems/Messages/MSG_Damage_Physical_Impact.MSG_Damage_Physical_Impact_C"
local function hurt(pawn, dmg)
    local ms, c = FindFirstOf("MessageSystem"), StaticFindObject(IMPACT)
    if not c:IsValid() then pcall(LoadAsset, IMPACT); c = StaticFindObject(IMPACT) end
    if not (ms and c:IsValid()) then return end
    local m = StaticConstructObject(c, ms)
    m.Damage = dmg
    ms:DispatchMessage(m, pawn)
end

local function tune(t)
    local lib = StaticFindObject("/Script/PenDriverUtils.Default__TuningFloatLibrary")
    local ok, v = pcall(function() return lib:Conv_TuningFloatToFloat(t) end)
    return ok and tonumber(v) or nil
end

local function alive(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) and not o:GetFullName():find("/Engine/Transient", 1, true) end
local function each(class, fn) for _, o in ipairs(FindAllOf(class) or {}) do if alive(o) then fn(o) end end end
local function hurtSelf(dmg)
    local pc = UEHelpers.GetPlayerController()
    if pc and pc:IsValid() and pc.Pawn:IsValid() then hurt(pc.Pawn, dmg) end
end

-- ---------------------------------------------------------------- hazards created at run time reach the guest

-- world.lua replicates BP_Base_Hazard children; spawned Tesla / Part Stealer / Loot Creature are made sure of here (docs/spikes/PT1-anom3.md)
LoopInGameThreadWithDelay(1000, function()
    if not (M.enabled and safety.active() and not safety.guest()) then return end
    try("replicate", function()
        for _, class in ipairs({ "BP_Hazard_Tesla_C", "BP_Hazard_PartStealer_C", "BP_Boon_LootCreature_C" }) do
            each(class, function(o)
                if o.RemoteRole ~= 0 or not o:HasAuthority() then return end
                o:SetReplicates(true)
                o:SetReplicateMovement(true)
                o.bAlwaysRelevant = true
                o.NetUpdateFrequency = 10
                o:ForceNetUpdate()
                log("PT|anom3 replicating %s", o:GetFName():ToString())
            end)
        end
    end)
end)

-- ---------------------------------------------------------------- pickpocket (Part Stealer) takes a guest's item

-- The stealer reaches for the host's character only: when the host is on foot in range it hits (3, MSG_Damage_Physical_Impact), then takes a random
-- item of the player's inventory (Spawn Item In World at the reach spot, GrabCarPart(item, true)). For a guest on foot within reach (the game's
-- 1500 uu) the host asks the guest: it hurts itself 3 and gives up a random backpack item, the host spawns that item at the guest's reach spot
-- (SpawnItemActor, the game's own drop call) and the stealer takes it (GrabCarPart) unless it is holding something already.
local REACH, COOL = 1200, 25
local stealCool = {} -- stealer name -> os.clock() when it may act again
M.stolen = 0
local function xform(l) return { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X, Y = l.Y, Z = l.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } } end

LoopInGameThreadWithDelay(250, function()
    if not (M.enabled and safety.active() and not safety.guest()) then return end
    try("pickpocket", function()
        local now = os.clock()
        each("BP_Hazard_PartStealer_C", function(s)
            local key = s:GetFName():ToString()
            local st = s.State
            if (stealCool[key] or 0) > now or st == 1 or st == 3 or st == 4 then return end
            local core = s.CoreFloatingMesh:K2_GetComponentLocation()
            for _, pc in ipairs(net.guests()) do
                local pawn = pc:IsValid() and pc.Pawn or nil
                if pawn and pawn:IsValid() then
                    local l = pawn:K2_GetActorLocation()
                    if (l.X - core.X) ^ 2 + (l.Y - core.Y) ^ 2 + (l.Z - core.Z) ^ 2 < REACH ^ 2 then
                        stealCool[key] = now + 8
                        net.toGuest(pc, "g.anom3.steal", key)
                        log("PT|anom3 pickpocket %s reaches for the guest", key)
                        return
                    end
                end
            end
        end)
    end)
end)

net.on("g.anom3.steal", function(_, key) -- guest
    if not (M.enabled and safety.guest()) then return end
    try("steal", function()
        local cm, im = FindFirstOf("BP_MainCharacterManager_C"), FindFirstOf("BP_InventoryManager_C")
        local pct = {}
        if cm and cm:IsValid() then cm:GetPlayerInCarPercent(pct) end
        if (pct.Percent or 0) > 0 or not (im and im:IsValid()) then return end -- the game only reaches for a player on foot
        local c, have = im.Inventory_Player, {}
        for i = 0, c:GetNumSlots() - 1 do
            local s = c:GetSlot(i)
            if s:GetNumItems() > 0 then have[#have + 1] = s:GetCurrentArchetype() end
        end
        if #have == 0 then return end
        local a = have[math.random(#have)]
        local p = a:GetFullName():match("^%S+ (.+)$")
        c:RemoveItemsOfType(a, 1)
        hurtSelf(3)
        net.toHost("g.anom3.stolen", key .. "\t" .. p)
        ov.post("A pickpocket took " .. p:match("[^/%.]+$"), "warn", "anom")
        log("PT|anom3 pickpocket took %s from the guest's backpack", p)
    end)
end)

net.on("g.anom3.stolen", function(pc, data) -- host
    if not (M.enabled and safety.active() and not safety.guest()) then return end
    try("stolen", function()
        local key, p = data:match("^([^\t]+)\t(.+)$")
        local ids = require("ids")
        local arch = key and ids.archetype(p)
        if not arch then log("PT|error anom3 stolen: no archetype %s", tostring(p)); return end
        local pawn, stealer = pc.Pawn, nil
        each("BP_Hazard_PartStealer_C", function(s) if s:GetFName():ToString() == key then stealer = s end end)
        if not (pawn and pawn:IsValid()) then return end
        local l = pawn:K2_GetActorLocation()
        local w = ids.system():SpawnItemActor(UEHelpers.GetWorld(), xform({ X = l.X, Y = l.Y, Z = l.Z + 100 }), arch, 0, 0)
        M.stolen = M.stolen + 1
        if stealer and alive(stealer) and alive(w) and not (stealer.GrabbedMesh and stealer.GrabbedMesh:IsValid()) then
            local ok, err = pcall(function() stealer:GrabCarPart(w, true, {}, {}, {}, {}) end)
            log("PT|anom3 pickpocket %s took %s from the guest grab=%s %s", key, p:match("[^/%.]+$"), tostring(ok), ok and "" or tostring(err))
        else
            log("PT|anom3 pickpocket item dropped (stealer busy) %s", p:match("[^/%.]+$"))
        end
    end)
end)

-- ---------------------------------------------------------------- bunny push

local PUSH = "/Game/Gameplay/Boons/ChubbyBunny/BP_Boon_LootCreature.BP_Boon_LootCreature_C:PushFx"
local pending = true
LoopInGameThreadWithDelay(2000, function()
    if not pending then return end
    pending = not pcall(RegisterHook, PUSH, function(self)
        if not (M.enabled and safety.active() and not safety.guest()) then return end
        try("push", function()
            local b = self:get()
            local at = b.PlayerPusher:K2_GetComponentLocation()
            local radius, strength = b.PlayerPusher.Radius, b.PlayerPusher.ImpulseStrength
            local dmg = tune(b.PushDamage) or 5
            for _, pc in ipairs(net.guests()) do
                local pawn = pc:IsValid() and pc.Pawn or nil
                if pawn and pawn:IsValid() then
                    local l = pawn:K2_GetActorLocation()
                    if (l.X - at.X) ^ 2 + (l.Y - at.Y) ^ 2 + (l.Z - at.Z) ^ 2 < radius ^ 2 then
                        hurt(pawn, dmg)
                        net.toGuest(pc, "g.anom3.push", string.format("%.0f\t%.0f\t%.0f\t%.0f\t%.0f", at.X, at.Y, at.Z, radius, strength))
                        M.pushed = M.pushed + 1
                        ov.post(ov.other() .. " was pushed by a bunny", "warn", "anom")
                        log("PT|anom3 bunny pushed the guest dmg=%.1f radius=%.0f strength=%.0f", dmg, radius, strength)
                    end
                end
            end
        end)
    end)
end)

net.on("g.anom3.push", function(_, data)
    if not (M.enabled and safety.guest()) then return end
    try("apply push", function()
        local x, y, z, r, s = data:match("^(%-?[%d%.]+)\t(%-?[%d%.]+)\t(%-?[%d%.]+)\t([%d%.]+)\t([%d%.]+)$")
        if not x then return end
        local pc = UEHelpers.GetPlayerController()
        local me = pc and pc:IsValid() and pc.Pawn or nil
        if not (me and me:IsValid()) then return end
        local l = me:K2_GetActorLocation()
        local d = { X = l.X - tonumber(x), Y = l.Y - tonumber(y), Z = l.Z - tonumber(z) }
        local len = math.max(math.sqrt(d.X ^ 2 + d.Y ^ 2 + d.Z ^ 2), 1)
        local v = math.max(300, math.min(1200, tonumber(s) / 100)) -- shortcut: the radial impulse of a 100 kg body, no falloff; calibrate with the logged strength
        me.CharacterMovement:AddImpulse({ X = d.X / len * v, Y = d.Y / len * v, Z = d.Z / len * v + 200 }, true)
        M.applied = M.applied + 1
        log("PT|anom3 bunny push applied")
    end)
end)

return M
