-- M4 shared items (W1, W2, C6, G1, P2, P3). The host's world is the truth; the guest's own loot is replaced by copies of it.
--   L lootable containers, W world pickups, I the game's single containers (car trunk, garage storage).
-- Host: finds them, gives each an id, tells the guest (A add, S contents, D gone). Guest: spawns or claims a local copy
-- per id and removes its own random loot; its own changes go back as intents (S contents, T "I picked this up") and the
-- host applies them. The guest's backpack stays its own: a pickup lands there through the game's own code.
-- Messages (net.lua kind g.loot.b): lines "A|id|class-or-archetype|x|y|z|yaw|state", "S|id|state", "D|id", "T|id", "F" (end of
-- the full dump), "H" (guest asks for the full dump). state = "<rolled>;<contents>" (ids.lua).
-- Inert in single player: nothing runs without a listening host with a guest, or a guest.
local UEHelpers = require("UEHelpers")
local common = require("common")
local net = require("net")
local ids = require("ids")
local log = common.log
local alive = ids.alive

-- tests only (a mutation that makes this module send and apply nothing); players never set PT_MUTATE
local DEAF = os.getenv("PT_MUTATE") == "nointent"

local INV = { "Inventory_Trunk", "Inventory_LargeTrunk", "Inventory_Garage", "Inventory_GarageLarge", "Inventory_GarageExpansion1",
              "Inventory_GarageExpansion1_Large", "Inventory_Garage_BackRoom" }
local DROP = 500 -- uu: an unknown pickup this close to the guest is its own drop
local MATCH = 60 -- uu: a local actor this close to the host's, same class, is the same thing

local ents, byName, nextId = {}, {}, 1 -- id -> entity; actor full name -> id (host)
local reported = {} -- guest: dropped items already told to the host
local claimed = {} -- guest: local actors that are some entity's copy
local out = {} -- lines for the other side, sent at the end of the tick
local gotAny, tickN = false, 0

local function say(line) out[#out + 1] = line end
local function flush()
    if #out == 0 then return end
    local buf, size = {}, 0
    local function send()
        if #buf == 0 then return end
        local data = table.concat(buf, "\n")
        if common.netMode() == "client" then net.toHost("g.loot.b", data) else net.toGuests("g.loot.b", data) end
        buf, size = {}, 0
    end
    for _, l in ipairs(out) do
        if size + #l > 8000 then send() end
        buf[#buf + 1] = l
        size = size + #l + 1
    end
    send()
    out = {}
end

local function inventoryManager()
    local m = FindFirstOf("BP_InventoryManager_C")
    return alive(m) and m or nil
end

local function stateOf(e)
    local c = e.get()
    if not alive(c) then return nil end
    local rolled = "-"
    if e.kind == "L" then rolled = e.actor.RolledOnOpenItems and "1" or "0" end
    return rolled .. ";" .. ids.encode(ids.count(c))
end

local function applyState(e, s)
    local c = e.get()
    if not alive(c) then e.pending = s; return end
    e.pending = nil
    local rolled, body = s:match("^(.);(.*)$")
    if e.kind == "L" and rolled ~= "-" then e.actor.RolledOnOpenItems = rolled == "1" end
    ids.apply(c, ids.decode(body))
    e.last, e.n = stateOf(e), c:GetNumItems()
    e.rolled = e.kind == "L" and e.actor.RolledOnOpenItems
end

local function register(id, kind, actor, invName)
    local e = { id = id, kind = kind, actor = actor, name = actor and actor:GetFullName() }
    if kind == "L" then e.get = function() return alive(e.actor) and e.actor.InventoryContainer or nil end
    elseif kind == "I" then e.get = function() local m = inventoryManager(); return m and m[invName] or nil end
    else e.get = function() return nil end end
    e.rolled = kind == "L" and actor.RolledOnOpenItems
    ents[id] = e
    return e
end

local function xform(x, y, z, yaw)
    local h = math.rad(yaw) / 2
    return { Rotation = { X = 0, Y = 0, Z = math.sin(h), W = math.cos(h) }, Translation = { X = x, Y = y, Z = z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
end

local function line(e)
    local a = e.actor
    local l, r = a:K2_GetActorLocation(), a:K2_GetActorRotation()
    local what = e.kind == "L" and ids.path2(a:GetClass()) or ids.path(a.Instance.Archetype)
    return string.format("A|%s|%s|%.0f|%.0f|%.0f|%.0f|%s", e.id, what, l.X, l.Y, l.Z, r.Yaw, e.kind == "L" and stateOf(e) or "-;")
end

-- host ------------------------------------------------------------------------------------------------------------

local function scanHost()
    for _, a in ipairs(FindAllOf("BP_Lootable_Base_C") or {}) do
        local n = alive(a) and a:GetFullName()
        if n and not byName[n] then
            local e = register("L" .. nextId, "L", a)
            nextId, byName[n] = nextId + 1, e.id
            e.last, e.n = stateOf(e), e.get():GetNumItems()
            say(line(e))
        end
    end
    for _, a in ipairs(FindAllOf("BP_WorldItem_C") or {}) do
        local n = alive(a) and alive(a.Instance) and not a:GetAttachParentActor():IsValid() and a:GetFullName()
        if n and not byName[n] then
            local e = register("W" .. nextId, "W", a)
            nextId, byName[n] = nextId + 1, e.id
            say(line(e))
        end
    end
    for _, p in ipairs(INV) do
        local id = "I:" .. p
        if not ents[id] then
            local e = register(id, "I", nil, p)
            local c = e.get()
            if alive(c) then e.last, e.n = stateOf(e), c:GetNumItems(); say("S|" .. id .. "|" .. e.last) else ents[id] = nil end
        end
    end
    for id, e in pairs(ents) do
        if e.kind ~= "I" and not alive(e.actor) then
            say("D|" .. id)
            byName[e.name], ents[id] = nil, nil
        end
    end
end

local function sendAll()
    for id, e in pairs(ents) do
        if e.kind == "I" then say("S|" .. id .. "|" .. (stateOf(e) or "-;"))
        elseif alive(e.actor) then say(line(e)) end
    end
    say("F")
end

-- guest -----------------------------------------------------------------------------------------------------------

local function near(a, x, y, z)
    local l = a:K2_GetActorLocation()
    return (l.X - x) ^ 2 + (l.Y - y) ^ 2 + (l.Z - z) ^ 2 < MATCH ^ 2
end

local function claim(actors, test)
    for _, a in ipairs(FindAllOf(actors) or {}) do
        if alive(a) and not claimed[a:GetFullName()] and test(a) then claimed[a:GetFullName()] = true; return a end
    end
end

local function spawnLootable(class, x, y, z, yaw)
    local cls = StaticFindObject(class)
    if not cls:IsValid() then pcall(LoadAsset, class); cls = StaticFindObject(class) end
    if not cls:IsValid() then log("PT|loot no class %s", class); return nil end
    local gs = UEHelpers.GetGameplayStatics()
    local xf = xform(x, y, z, yaw)
    local a = gs:BeginDeferredActorSpawnFromClass(UEHelpers.GetWorld(), cls, xf, 1, nil)
    pcall(function() a.ForceSpawnEvenifFailedChanceToLive = true end)
    a = gs:FinishSpawningActor(a, xf)
    if alive(a) then claimed[a:GetFullName()] = true end
    return alive(a) and a or nil
end

local function spawnItem(arch, x, y, z, yaw)
    local a = ids.archetype(arch)
    if not a then log("PT|loot no archetype %s", arch); return nil end
    local w = ids.system():SpawnItemActor(UEHelpers.GetWorld(), xform(x, y, z, yaw), a, 0, 0)
    if alive(w) then claimed[w:GetFullName()] = true end
    return alive(w) and w or nil
end

local function onAdd(id, what, x, y, z, yaw, state)
    local e = ents[id]
    if e then return end
    local kind = id:sub(1, 1)
    local a
    if kind == "L" then
        a = claim("BP_Lootable_Base_C", function(o) return ids.path2(o:GetClass()) == what and near(o, x, y, z) end)
            or spawnLootable(what, x, y, z, yaw)
    else
        a = claim("BP_WorldItem_C", function(o) return alive(o.Instance) and ids.path(o.Instance.Archetype) == what and near(o, x, y, z) end)
            or spawnItem(what, x, y, z, yaw)
    end
    if not a then return end
    e = register(id, kind, a)
    if kind == "L" then applyState(e, state) end
end

-- the guest's own random loot is not part of the host's world
local function purge()
    local n = 0
    for _, a in ipairs(FindAllOf("BP_Lootable_Base_C") or {}) do
        if alive(a) and not claimed[a:GetFullName()] then a:K2_DestroyActor(); n = n + 1 end
    end
    for _, a in ipairs(FindAllOf("BP_WorldItem_C") or {}) do
        if alive(a) and not claimed[a:GetFullName()] and not a:GetAttachParentActor():IsValid() then a:K2_DestroyActor(); n = n + 1 end
    end
    log("PT|loot guest purged %d own actors, %d host actors", n, (function() local c = 0; for _ in pairs(ents) do c = c + 1 end; return c end)())
end

local function scanGuest()
    for id, e in pairs(ents) do
        if e.kind == "W" and not alive(e.actor) then
            -- picked up here (the item sits in a slot now): tell the host once
            local ok, slot = pcall(function() return e.actor.Instance:GetOuterSlot() end)
            if ok and slot and slot:IsValid() then say("T|" .. id) end
            ents[id] = nil
        elseif e.pending then applyState(e, e.pending) end
    end
    if not gotAny then
        if tickN % 6 == 0 then say("H") end
        return
    end
    -- pickups the guest's own game makes now (spawners): not the host's. Items the guest dropped lie next to it: they become the host's.
    local pawn = UEHelpers.GetPlayerController().Pawn
    local p = alive(pawn) and pawn:K2_GetActorLocation()
    -- its own random lootables keep appearing for a while after the join
    for _, a in ipairs(FindAllOf("BP_Lootable_Base_C") or {}) do
        if alive(a) and not claimed[a:GetFullName()] then a:K2_DestroyActor() end
    end
    for _, a in ipairs(FindAllOf("BP_WorldItem_C") or {}) do
        local n = alive(a) and alive(a.Instance) and not claimed[a:GetFullName()] and not a:GetAttachParentActor():IsValid() and a:GetFullName()
        if n and not reported[n] then
            local l = a:K2_GetActorLocation()
            if p and (l.X - p.X) ^ 2 + (l.Y - p.Y) ^ 2 + (l.Z - p.Z) ^ 2 < DROP ^ 2 then
                reported[n] = true
                say(string.format("N|%s|%.0f|%.0f|%.0f|%.0f", ids.path(a.Instance.Archetype), l.X, l.Y, l.Z, a:K2_GetActorRotation().Yaw))
            else
                a:K2_DestroyActor()
            end
        end
    end
end

-- both: contents changed here since we last looked (the game moved items in or out)
local function scanChanges()
    for id, e in pairs(ents) do
        local c = e.kind ~= "W" and e.get()
        if alive(c) then
            local r = e.kind == "L" and alive(e.actor) and e.actor.RolledOnOpenItems
            if c:GetNumItems() ~= e.n or r ~= e.rolled then
                e.n, e.rolled = c:GetNumItems(), r
                local s = stateOf(e)
                if s and s ~= e.last then
                    e.last = s
                    log("PT|loot send S %s", id)
                    say("S|" .. id .. "|" .. s)
                end
            end
        end
    end
end

-- messages --------------------------------------------------------------------------------------------------------

local function handle(pc, data)
    if DEAF then return end
    local guest = common.netMode() == "client"
    for l in data:gmatch("[^\n]+") do
        local f = {}
        for p in (l .. "|"):gmatch("([^|]*)|") do f[#f + 1] = p end
        local op, id = f[1], f[2]
        if op == "H" and not guest then
            sendAll()
        elseif guest and op == "A" then
            gotAny = true
            onAdd(id, f[3], tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), f[8])
        elseif guest and op == "F" then
            gotAny = true
            purge()
        elseif op == "S" and ents[id] then
            log("PT|loot got S %s (%s)", id, f[3]:sub(1, 80))
            applyState(ents[id], f[3])
            -- the guest's change: the host applies it and the other players see it
            if not guest then say(l) end
        elseif op == "S" and guest then
            gotAny = true
            -- a container of the game's that the guest has not registered yet
            local name = id:match("^I:(.+)$")
            if name then applyState(register(id, "I", nil, name), f[3]) end
        elseif op == "D" and guest and ents[id] then
            local e = ents[id]
            ents[id] = nil
            if alive(e.actor) then e.actor:K2_DestroyActor() end
        elseif op == "N" and not guest then
            spawnItem(f[2], tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]))
        elseif op == "T" and not guest and ents[id] then
            local e = ents[id]
            ents[id], byName[e.name] = nil, nil
            if alive(e.actor) then e.actor:K2_DestroyActor() end
            say("D|" .. id)
        end
    end
end
net.on("g.loot.b", handle)

local function tick()
    tickN = tickN + 1
    local mode = common.netMode()
    if mode == "listen" then
        if #net.guests() == 0 then return end
        scanHost()
    elseif mode == "client" then
        if not ids.alive(UEHelpers.GetPlayerController()) then return end
        scanGuest()
    else
        return
    end
    scanChanges()
    if not DEAF then flush() else out = {} end
end

RegisterLoadMapPostHook(function()
    ents, byName, claimed, reported, out, gotAny = {}, {}, {}, {}, {}, false
end)

LoopInGameThreadWithDelay(500, function()
    local ok, err = pcall(tick)
    if not ok then log("PT|error loot %s", tostring(err)) end
end)
