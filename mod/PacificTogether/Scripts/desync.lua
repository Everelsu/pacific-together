-- Position desync watch and repair (the host is the truth). Hand playtest 2026-10-24: on the host the guest stood at a door, on the
-- guest's own screen it was already in the room, and the host's character stood still on the guest's screen while the host walked.
-- The engine's own move correction only works while the host's copy of the guest simulates the guest's moves.
--   guest  "g.ds.p" twice a second: its own position and where it sees the host's character, "gx,gy,gz;hx,hy,hz"
--   host   compares them with its own: the guest's copy off by more than OFF for two reports -> logs PT|desync and repairs the copy
--          (movement tick, collision, walking); still off two reports later -> "g.ds.fix" puts the guest at the host's spot.
--          Its own character off on the guest's screen for three reports -> ForceNetUpdate.
-- Seated players (attached to the car) are skipped: their spot is the seat. Inert outside a session (Q7).
local UEHelpers = require("UEHelpers")
local common = require("common")
local safety = require("safety")
local net = require("net")
local ov = require("overlay")
local log = common.log

local M = { enabled = os.getenv("PT_MUTATE") ~= "nodesync" }
local OFF = 150 -- uu; a walking player covers ~190 uu in a report interval, but both sides sample near the same moment

local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function fmt(l) return string.format("%.0f,%.0f,%.0f", l.X, l.Y, l.Z) end
local function parse(s) local x, y, z = s:match("^(-?[%d.]+),(-?[%d.]+),(-?[%d.]+)$"); return x and { X = tonumber(x), Y = tonumber(y), Z = tonumber(z) } end
local function dist(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end
local function seated(c) local ok, p = pcall(function() return c:GetAttachParentActor() end); return ok and valid(p) end

-- the other player's character on this side (not our own), and our own
local function chars()
    local pc = UEHelpers.GetPlayerController()
    local mine = valid(pc) and pc.Pawn or nil
    if not valid(mine) then return nil end
    for _, c in ipairs(FindAllOf("PDP_MainCharacter_C") or {}) do
        if valid(c) and c:GetAddress() ~= mine:GetAddress() and not c:GetFullName():find("/Engine/Transient", 1, true) then return mine, c end
    end
    return mine, nil
end

-- guest ----------------------------------------------------------------------------------------------------------------------

net.on("g.ds.fix", function(_, data)
    if not (M.enabled and safety.guest()) then return end
    local to, me = parse(data), (chars())
    if not (to and valid(me)) or seated(me) then return end
    me:K2_SetActorLocation(to, false, {}, true)
    log("PT|desync guest put back at the host's spot %s", data)
end)

local function guestTick()
    local me, host = chars()
    if not (valid(me) and valid(host)) then return end
    net.toHost("g.ds.p", fmt(me:K2_GetActorLocation()) .. ";" .. fmt(host:K2_GetActorLocation()))
end

-- host -----------------------------------------------------------------------------------------------------------------------

local bad, badHost, fixes = 0, 0, 0
local function repair(c)
    -- what lets a copy stand while its guest walks on: the engine's own correction off, or no movement mode on the host's side
    pcall(function() c.CharacterMovement.bIgnoreClientMovementErrorChecksAndCorrection = false end)
    pcall(function() c.CharacterMovement.bServerAcceptClientAuthoritativePosition = false end)
    pcall(function() c.CharacterMovement:SetComponentTickEnabled(true) end)
    pcall(function() c:SetActorEnableCollision(true) end)
    pcall(function() if c.CharacterMovement.MovementMode == 0 then c.CharacterMovement:SetMovementMode(1, 0) end end)
end
net.on("g.ds.p", function(pc, data)
    if not (M.enabled and safety.active()) or safety.guest() then return end
    local gs, hs = data:match("^([^;]+);(.+)$")
    local gSelf, hSeen = gs and parse(gs), hs and parse(hs)
    local g, me = pc.Pawn, (chars())
    if not (gSelf and hSeen and valid(g) and valid(me)) then return end
    if seated(g) then bad = 0 else
        local d = dist(g:K2_GetActorLocation(), gSelf)
        bad = d > OFF and bad + 1 or 0
        if bad == 2 then
            repair(g)
            log("PT|desync guest %.0f uu off: host has %s, guest has %s; host copy repaired", d, fmt(g:K2_GetActorLocation()), gs)
        elseif bad >= 4 then
            bad, fixes = 0, fixes + 1
            net.toGuest(pc, "g.ds.fix", fmt(g:K2_GetActorLocation()))
            log("PT|desync guest still %.0f uu off: put back at the host's spot (%d so far)", d, fixes)
            ov.post("Position resynced", "warn", "desync")
        end
    end
    if seated(me) then badHost = 0 else
        local d = dist(me:K2_GetActorLocation(), hSeen)
        badHost = d > OFF and badHost + 1 or 0
        if badHost == 3 then
            badHost = 0
            pcall(function() me:ForceNetUpdate() end)
            log("PT|desync host %.0f uu off on the guest's screen (host %s, guest sees %s): net update forced", d, fmt(me:K2_GetActorLocation()), hs)
        end
    end
end)

LoopInGameThreadWithDelay(500, function()
    if not M.enabled or not safety.guest() or not safety.active() then return end
    local ok, err = pcall(guestTick)
    if not ok then log("PT|error desync %s", tostring(err)) end
end)
RegisterLoadMapPostHook(function() bad, badHost = 0, 0 end)

return M
