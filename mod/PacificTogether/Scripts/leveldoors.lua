-- Doors placed in the map (BP_Door_* with RF_WasLoaded: the garage's back room, store and basement doors, a zone map's own doors).
-- Both games have them under the same names, but the guest never loaded the host's save: its padlocks were still on and its doors
-- shut where the host had broken and opened them, and the collision that counts is the host's (hand playtest 2026-10-24).
-- visual.lua copies the run-time doors of a zone; these are the rest.
--   host   "g.ldoor.s"  key \t state \t locked (1/0), one line per door, sent when it changes and to a new guest
--   guest  applies them: ForceUnlockDoor where the host's lock is gone, "Set Door from State" where the state differs
--   guest  "g.ldoor.set" key \t state: its E swings its own door and the host swings its door to the same state (a press passed
--          on to the host opened the host's door the other way, the side is picked from the host's own character: the guest's door
--          went one way, then back the other, playtest 2026-10-24)
--   guest  "g.ldoor.unlock" key: it broke a padlock the host still has (its prybar works on its own copy); the host unlocks it
-- Inert outside a session (Q7).
local common = require("common")
local safety = require("safety")
local net = require("net")
local log = common.log

local M = { enabled = os.getenv("PT_MUTATE") ~= "noleveldoors" }

local RF_WasLoaded = 0x00080000
local CLASSES = { "BP_Door_Single_C", "BP_Door_Sliding_Single_C" } -- FindAllOf includes their children (double, T1/T2, ...)
local INTERACT = "BndEvt__Highlight_K2Node_ComponentBoundEvent_0_OnHighlightInteract__DelegateSignature"
local HOLD_S = 1.5 -- the guest's own press is not overridden by the host's state for this long (the press needs a round trip)

local function live(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function try(what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then log("PT|error leveldoors %s %s", what, tostring(err)) end
end

-- "Garage_Art:BP_Door_Single_GarageToStore": the level's name keeps two sublevels' doors apart
local function keyOf(d) return d:GetOuter():GetOuter():GetFName():ToString() .. ":" .. d:GetFName():ToString() end

-- the map's doors by key; read again every 2 s (an /Engine/Transient template of each door has the same name: skipped)
local doors, doorsAt = {}, -math.huge
local quietUntil = 0
RegisterLoadMapPreHook(function() quietUntil, doors, doorsAt = math.huge, {}, -math.huge end)
RegisterLoadMapPostHook(function() quietUntil = os.clock() + 3 end)
local function mapDoors()
    if os.clock() - doorsAt > 2 then
        doors, doorsAt = {}, os.clock()
        for _, c in ipairs(CLASSES) do
            for _, d in ipairs(FindAllOf(c) or {}) do
                if live(d) and d:HasAnyFlags(RF_WasLoaded) and not d:GetFullName():find("/Engine/Transient", 1, true) then doors[keyOf(d)] = d end
            end
        end
    end
    return doors
end

-- 1 while the padlock hangs (the door's LockStrength is only its setting: it stays after the lock is broken)
local function lockLeft(d)
    local r = {}
    local ok = pcall(function() d.BP_LockedComponent:IsLocked(r) end)
    return (ok and r.Locked) and 1 or 0
end

-- A state from the other side, swung to: "Set Door from State" alone snapped the guest's door (hand playtest 2026-10-24: "open, then bang,
-- closed"). The door's meshes are read before and after the set, put back, and turned to the new pose over SWING_S.
local SMC = StaticFindObject("/Script/Engine.StaticMeshComponent")
local SWING_S = 0.35
local swings = {} -- key -> running loop
local function swing(k, d, st)
    pcall(function() d.AnimTimeline:Stop() end) -- the door's own swing (a local press) would fight this one
    local meshes, from = {}, {}
    for _, e in ipairs(d:K2_GetComponentsByClass(SMC)) do
        local m = e:get()
        local r = m.RelativeRotation
        meshes[#meshes + 1], from[#from + 1] = m, { r.Pitch, r.Yaw, r.Roll }
    end
    d["Set Door from State"](d, st) -- 0 closed, 1 and 2 open (either way), 3 and up shut
    local moves = {}
    for i, m in ipairs(meshes) do
        local r = m.RelativeRotation
        local to = { r.Pitch, r.Yaw, r.Roll }
        if math.abs(to[1] - from[i][1]) + math.abs(to[2] - from[i][2]) + math.abs(to[3] - from[i][3]) > 0.5 then
            moves[#moves + 1] = { m = m, from = from[i], to = to }
            m:K2_SetRelativeRotation({ Pitch = from[i][1], Yaw = from[i][2], Roll = from[i][3] }, false, {}, true)
        end
    end
    if #moves == 0 then return end
    if swings[k] then CancelDelayedAction(swings[k]) end
    local t0, loop = os.clock(), nil
    loop = LoopInGameThreadWithDelay(16, function()
        local a = math.min(1, (os.clock() - t0) / SWING_S)
        a = a * a * (3 - 2 * a) -- ease in and out
        local ok = pcall(function()
            for _, v in ipairs(moves) do
                local function lerp(i) return v.from[i] + ((v.to[i] - v.from[i] + 540) % 360 - 180) * a end
                v.m:K2_SetRelativeRotation({ Pitch = lerp(1), Yaw = lerp(2), Roll = lerp(3) }, false, {}, true)
            end
        end)
        if a >= 1 or not ok then CancelDelayedAction(loop); swings[k] = nil end
    end)
    swings[k] = loop
end

-- host ---------------------------------------------------------------------------------------------------------------------

local lastSent, lastGuests = nil, 0
local function hostTick()
    local guests = #net.guests()
    if guests == 0 then lastSent, lastGuests = nil, 0 return end
    local lines = {}
    for k, d in pairs(mapDoors()) do
        if live(d) then lines[#lines + 1] = string.format("%s\t%d\t%d", k, tonumber(d.CurrentState) or 0, lockLeft(d)) end
    end
    table.sort(lines)
    local s = table.concat(lines, "\n")
    if s ~= lastSent or guests ~= lastGuests then
        net.toGuests("g.ldoor.s", s)
        lastSent, lastGuests = s, guests
    end
end
net.on("g.ldoor.hello", function() lastSent = nil end)

net.on("g.ldoor.set", function(_, data)
    local key, st = data:match("^(.-)\t(%d+)$")
    local d = M.enabled and key and mapDoors()[key]
    if not live(d) then log("PT|leveldoors guest used %s: not on the host", tostring(key)) return end
    swing(key, d, tonumber(st))
    log("PT|leveldoors guest used %s: state %s on the host", key, st)
end)

net.on("g.ldoor.unlock", function(_, key)
    local d = M.enabled and mapDoors()[key]
    if not live(d) or lockLeft(d) == 0 then return end
    d:ForceUnlockDoor()
    log("PT|leveldoors guest broke the lock of %s: unlocked on the host", key)
end)

-- guest --------------------------------------------------------------------------------------------------------------------

local want = {} -- key -> { st, lock }
local held = {} -- key -> os.clock() until which the guest's own press stands
local unlockSent, unlocking = {}, {}
net.on("g.ldoor.s", function(_, data)
    want = {}
    for k, st, lock in data:gmatch("([^\t\n]+)\t(%d+)\t(%d+)") do want[k] = { st = tonumber(st), lock = tonumber(lock) } end
end)

local helloSent = false
RegisterLoadMapPostHook(function()
    for _, l in pairs(swings) do CancelDelayedAction(l) end
    helloSent, unlockSent, unlocking, held, swings = false, {}, {}, {}, {}
end)
local function guestTick()
    if not helloSent then helloSent = net.toHost("g.ldoor.hello", "") and true or false end -- a loading guest can miss the first list
    local now = os.clock()
    for k, d in pairs(mapDoors()) do
        local w = want[k]
        if w and live(d) then
            local mine = lockLeft(d)
            if w.lock == 0 and mine > 0 and not unlocking[k] then
                -- ForceUnlockDoor drops the padlock mesh but leaves a guest's lock strength (its IsLocked stayed true, so the game
                -- kept the door's highlight off); SetLockStrength(0) clears it at once (live, 2026-10-24). Once per door and map.
                unlocking[k] = true
                d:ForceUnlockDoor()
                d.BP_LockedComponent:SetLockStrength(0)
                log("PT|leveldoors %s unlocked as on the host (locked now: %d)", k, lockLeft(d))
            elseif w.lock > 0 and mine == 0 and not unlockSent[k] then
                unlockSent[k] = true
                net.toHost("g.ldoor.unlock", k)
                log("PT|leveldoors guest broke the lock of %s: sent", k)
            end
            if not (held[k] and held[k] > now) and d.CurrentState ~= w.st then swing(k, d, w.st) end
        end
    end
end

-- the guest's E on a map door (the event is declared on BP_Door_Single_C / BP_Door_Sliding_Single_C)
local hooked = {}
local function hookDoors()
    for _, c in ipairs(CLASSES) do
        local any = not hooked[c] and FindFirstOf(c)
        if any and live(any) then
            hooked[c] = true
            local at = any:GetClass():GetFullName():match("^%S+ (.+)$")
            -- only the declaring class has the event; children (doubles, T1/T2) reach it through their parent
            while at and not StaticFindObject(at .. ":" .. INTERACT):IsValid() do
                local sup = StaticFindObject(at):GetSuperStruct()
                at = sup:IsValid() and sup:GetFullName():match("^%S+ (.+)$") or nil
            end
            if at then
                local ok, err = pcall(RegisterHook, at .. ":" .. INTERACT, function(self)
                    if not (M.enabled and safety.guest()) then return end
                    local d = self:get()
                    if not (live(d) and d:HasAnyFlags(RF_WasLoaded)) then return end -- visual.lua's copies send their own
                    local k = keyOf(d)
                    held[k] = os.clock() + HOLD_S
                    ExecuteInGameThreadWithDelay(150, function() -- the press has picked its state by then
                        if live(d) then net.toHost("g.ldoor.set", k .. "\t" .. tostring(d.CurrentState)) end
                    end)
                    log("PT|leveldoors guest used %s", k)
                end)
                log("PT|leveldoors hook %s %s", at, ok and "ok" or tostring(err))
            end
        end
    end
end

-- 5 times a second: the host's swing reaches the guest soon enough to look like the same push (16 doors in the garage: cheap)
LoopInGameThreadWithDelay(200, function()
    if not M.enabled or os.clock() < quietUntil then return end
    if safety.guest() then
        try("hook", hookDoors)
        try("guest", guestTick)
    elseif safety.active() then
        try("host", hostTick)
    end
end)

M.keyOf, M.mapDoors = keyOf, mapDoors
return M
