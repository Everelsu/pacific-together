-- Radiation on the guest (playtest 2026-10-23 #8). The game hurts the player from its own process: BP_ResourceDirector asks
-- BP_HazardManager (GetInfluenceValue "LocalRadiation") what the radiation is at the player. The zone's radiated areas
-- (BP_Hazard_RadiatedZone_* spawn a BP_VolCascade_Radiation_C at runtime) exist on the host only (zone: host 8 volumes,
-- guest 3, the 3 being level-placed with no radiation), so on the guest the value was always 0.
-- The host lists its radiating volumes, the guest spawns the missing ones with the same numbers. Inert outside a session (Q7).
local UEHelpers = require("UEHelpers")
local common = require("common")
local net = require("net")
local safety = require("safety")
local log = common.log

local M = { enabled = os.getenv("PT_MUTATE") ~= "norad" } -- the test mutation switches the module off
local CLS = "/Game/Systems/VolumeCascade/BP_VolCascade_Radiation.BP_VolCascade_Radiation_C"
local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end

local function volumes()
    local r = {}
    for _, o in ipairs(FindAllOf("BP_VolCascade_Radiation_C") or {}) do
        if valid(o) and o["Max Local Radiation"] > 0 then r[#r + 1] = o end
    end
    return r
end

-- host: x y z yaw radius falloff max shape bx by bz fx fy fz, volumes joined by ";"
local function describe()
    local list = {}
    for _, o in ipairs(volumes()) do
        local l, rot, b, f = o:K2_GetActorLocation(), o:K2_GetActorRotation(), o.BoxShapeSize, o.BoxShapeFalloff
        list[#list + 1] = string.format("%.0f %.0f %.0f %.1f %.1f %.1f %.4f %d %.1f %.1f %.1f %.1f %.1f %.1f", l.X, l.Y, l.Z, rot.Yaw,
            o.Radius, o["Falloff Size"], o["Max Local Radiation"], o.Shape, b.X, b.Y, b.Z, f.X, f.Y, f.Z)
    end
    return table.concat(list, ";")
end

local function spawn(cls, w, n)
    local a = w:SpawnActor(cls, { X = n[1], Y = n[2], Z = n[3] }, { Pitch = 0, Yaw = n[4], Roll = 0 })
    if not valid(a) then return false end
    a.Radius, a["Falloff Size"], a["Max Local Radiation"], a.Shape = n[5], n[6], n[7], n[8]
    a.BoxShapeSize, a.BoxShapeFalloff = { X = n[9], Y = n[10], Z = n[11] }, { X = n[12], Y = n[13], Z = n[14] }
    a:UpdateInfluenceZone(a.Influence_LocalRadiation)
    return true
end

net.on("g.rad.vols", function(_, data)
    if not (M.enabled and safety.guest()) then return end
    local cls, hm = StaticFindObject(CLS), FindFirstOf("BP_HazardManager_C")
    if not (cls and cls:IsValid() and valid(hm)) then return end
    local have = volumes()
    for entry in data:gmatch("[^;]+") do
        local n = {}
        for v in entry:gmatch("%S+") do n[#n + 1] = tonumber(v) end
        local known = false
        for _, o in ipairs(have) do
            local l = o:K2_GetActorLocation()
            if math.abs(l.X - n[1]) < 100 and math.abs(l.Y - n[2]) < 100 and math.abs(l.Z - n[3]) < 100 then known = true break end
        end
        if not known then
            local ok, made = pcall(spawn, cls, hm:GetWorld(), n)
            if ok and made then log("PT|radiation guest volume at %.0f %.0f %.0f r=%.0f max=%.2f", n[1], n[2], n[3], n[5], n[7])
            else log("PT|error radiation spawn %s", tostring(made)) end
        end
    end
end)

-- host: the list every 4 s (a zone's volumes appear as it loads, a guest may join late)
LoopInGameThreadWithDelay(4000, function()
    if not (M.enabled and safety.active() and not safety.guest()) then return end
    local ok, err = pcall(function()
        local s = describe()
        if s ~= "" then net.toGuests("g.rad.vols", s) end
    end)
    if not ok then log("PT|error radiation %s", tostring(err)) end
end)

return M
