-- Shared ambient scares (owner request 2026-10-30). BP_AmbienceManager picks its spooky events on each side by itself (whispers,
-- the static ghost, drones, startled birds, Bigfoot ...), so one player heard what the other did not. The host's manager decides:
-- every event it spawns ("Spawn Ambient Event Actor", class + spot) goes to the guest, whose own picking is off and which spawns
-- the same event at the same spot. Inert outside a session (Q7). Mutation noambsync: off (each side its own events again).
local common = require("common")
local safety = require("safety")
local net = require("net")
local log = common.log

local M = {}
if os.getenv("PT_MUTATE") == "noambsync" then return M end

local AM = "/Game/Systems/Managers/BP_AmbienceManager.BP_AmbienceManager_C"
local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function manager() local a = FindFirstOf("BP_AmbienceManager_C") return valid(a) and a or nil end
local applying = false -- the guest spawning the host's event: not sent back

local hooked = false
local function hook()
    hooked = pcall(RegisterHook, AM .. ":Spawn Ambient Event Actor", function(_, cls, pos)
        if applying or not safety.active() or safety.guest() then return end
        local c, p = cls:get(), pos:get()
        if not valid(c) then return end
        local path = c:GetFullName():gsub("^%S+ ", "")
        net.toGuests("g.amb.ev", string.format("%s|%.0f|%.0f|%.0f", path, p.X, p.Y, p.Z))
        log("PT|ambient host event %s", path:match("[^.]+$"))
    end)
end

net.on("g.amb.ev", function(_, data)
    if not safety.guest() then return end
    local path, x, y, z = data:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
    local am = manager()
    if not (path and am) then return end
    local c = StaticFindObject(path)
    if not valid(c) then pcall(LoadAsset, path); c = StaticFindObject(path) end
    if not valid(c) then log("PT|error ambient no class %s", path); return end
    applying = true
    local ok, err = pcall(function() am["Spawn Ambient Event Actor"](am, c, { X = tonumber(x), Y = tonumber(y), Z = tonumber(z) }) end)
    applying = false
    log("PT|ambient guest event %s ok=%s %s", path:match("[^.]+$"), tostring(ok), tostring(err or ""))
end)

-- the guest's own picking off while it is a guest, back on after (the flag is the manager's own debug switch)
local guestOff = false
LoopInGameThreadWithDelay(1000, function()
    if not hooked then hook() end
    local am = manager()
    if not am then return end
    local g = safety.active() and safety.guest()
    if g then
        if am.AmbientEventsEnabled then am.AmbientEventsEnabled = false end
        guestOff = true
    elseif guestOff then
        am.AmbientEventsEnabled = true
        guestOff = false
    end
end)

return M
