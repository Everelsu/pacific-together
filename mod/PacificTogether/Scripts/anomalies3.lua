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
        me.CharacterMovement:AddRadialImpulse({ X = tonumber(x), Y = tonumber(y), Z = tonumber(z) }, tonumber(r), tonumber(s), 0, true)
        M.applied = M.applied + 1
        log("PT|anom3 bunny push applied")
    end)
end)

return M
