-- M4 shared items (W1, W2, C6, G1, P2, P3). The host's world is the truth; the guest's own loot is replaced by copies of it.
--   L lootable containers, W world pickups, I the game's single containers (car trunk, garage storage).
-- Host: finds them, gives each an id, tells the guest (A add, S contents, D gone). Guest: spawns or claims a local copy
-- per id and removes its own random loot; its own changes go back as intents (S contents, T "I picked this up") and the
-- host applies them. The guest's backpack stays its own: a pickup lands there through the game's own code.
-- Messages (net.lua kind g.loot.b): lines "A|id|class-or-archetype|x|y|z|yaw|state", "S|id|state", "D|id", "T|id", "F" (end of
-- the full dump), "H" (guest asks for the full dump). state = "<flags>;<contents>" (ids.lua);
-- flags is one digit: 1 rolled on open, 2 was opened, 4 empty (the two visuals), "-" for non-lootables.
-- Inert in single player: nothing runs without a listening host with a guest, or a guest.
local UEHelpers = require("UEHelpers")
local common = require("common")
local net = require("net")
local ids = require("ids")
local log = common.log
local ov = require("overlay")
local alive = ids.alive

-- tests only (a mutation that makes this module send and apply nothing); players never set PT_MUTATE
local DEAF = os.getenv("PT_MUTATE") == "nointent"
-- tests only: no wreck parts and no lootable visuals (item state: ids.lua)
local NO2 = os.getenv("PT_MUTATE") == "nolootsync2"

-- tests only: a template part's own container (a wreck's trunk contents, a box truck's cargo) is not carried
local NOCAR = os.getenv("PT_MUTATE") == "nocarloot"

local INV = { "Inventory_Trunk", "Inventory_LargeTrunk", "Inventory_Garage", "Inventory_GarageLarge", "Inventory_GarageExpansion1",
              "Inventory_GarageExpansion1_Large", "Inventory_Garage_BackRoom" }
local DROP = 500 -- uu: an unknown pickup this close to the guest is its own drop
local MATCH = 60 -- uu: a local actor this close to the host's, same class, is the same thing

local ents, byName, nextId = {}, {}, 1 -- id -> entity; actor full name -> id (host)
local reported = {} -- guest: dropped items already told to the host
local claimed = {} -- guest: local actors that are some entity's copy
local out = {} -- lines for the other side, sent at the end of the tick
local gotAny, tickN = false, 0

-- a big container (a garage's storage can hold hundreds of stacks) does not fit one message (32 KB): its state goes as numbered pieces
-- "P|id|i|n|keys", put together again on the other side
local PIECE = 5000
local function say(line)
    if #line > PIECE * 1.5 and line:sub(1, 2) == "S|" then
        local id, s = line:match("^S|([^|]*)|(.*)$")
        local pieces, cur, size = {}, {}, 0
        for k in s:gmatch("[^,]+") do
            if size > PIECE then pieces[#pieces + 1] = table.concat(cur, ","); cur, size = {}, 0 end
            cur[#cur + 1] = k
            size = size + #k + 1
        end
        pieces[#pieces + 1] = table.concat(cur, ",")
        for i, p in ipairs(pieces) do out[#out + 1] = string.format("P|%s|%d|%d|%s", id, i, #pieces, p) end
        return
    end
    out[#out + 1] = line
end
local partial = {} -- id -> { piece index -> text } (guest and host)
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

local function flagsOf(e)
    local a = e.actor
    if e.kind ~= "L" or not alive(a) then return nil end
    if NO2 then return a.RolledOnOpenItems and 1 or 0 end
    return (a.RolledOnOpenItems and 1 or 0) + (a.DataBlock_WasOpened and 2 or 0) + (a.Empty and 4 or 0)
end

local function stateOf(e)
    local c = e.get()
    if not alive(c) then return nil end
    return (flagsOf(e) or "-") .. ";" .. ids.encode(ids.count(c))
end

-- opened and emptied look: the game's own visual switches
local function applyFlags(a, f)
    a.RolledOnOpenItems = f & 1 ~= 0
    if f & 2 ~= 0 and not a.DataBlock_WasOpened then
        a.DataBlock_WasOpened = true
        pcall(function() a:SwitchToOpenedVisuals() end)
    end
    if f & 4 ~= 0 and not a.Empty then
        a.Empty = true
        pcall(function() a:UpdateVisualsForEmpty() end)
    end
end

-- a template part (abandoned-car door, wheel, gas cap): "pitch,roll,item spec,mesh"
-- some parts hold items (their ItemInstance has a container): "spec;contents", contents "-" when there is none
local function partBox(a)
    if NOCAR then return nil end
    local ok, c = pcall(function()
        local o = {}
        ids.bfl():GetInstanceContainer(a.ItemInstance, a, o)
        return o.Container
    end)
    return ok and alive(c) and c or nil
end
local function partContents(a)
    local c = partBox(a)
    return c and ids.encode(ids.count(c)) or "-"
end
local function partKey(a) return ids.spec(a.ItemInstance) .. ";" .. partContents(a) end
local function partState(a)
    local r = a:K2_GetActorRotation()
    return string.format("%.1f,%.1f,%s,%s;%s", r.Pitch, r.Roll, ids.spec(a.ItemInstance), alive(a.RequestedMesh) and ids.path2(a.RequestedMesh) or "-", partContents(a))
end

local function applyState(e, s)
    if e.kind == "P" then
        local spec = s:match("^[^,]*,[^,]*,([^,]*),")
        if alive(e.actor) and alive(e.actor.ItemInstance) and spec then
            ids.setProps(e.actor.ItemInstance, spec)
            local body, box = s:match(";(.*)$"), partBox(e.actor)
            if box and body and body ~= "-" then ids.apply(box, ids.decode(body)) end
            e.last = partKey(e.actor)
        end
        return
    end
    local c = e.get()
    if not alive(c) then e.pending = s; return end
    e.pending = nil
    local flags, body = s:match("^(.);(.*)$")
    ids.apply(c, ids.decode(body))
    if e.kind == "L" and flags ~= "-" then applyFlags(e.actor, tonumber(flags)) end
    e.last, e.n, e.rolled = stateOf(e), c:GetNumItems(), flagsOf(e)
end

local function register(id, kind, actor, invName)
    local e = { id = id, kind = kind, actor = actor, name = actor and actor:GetFullName() }
    if kind == "L" then e.get = function() return alive(e.actor) and e.actor.InventoryContainer or nil end
    elseif kind == "I" and invName:find("^Stations%.") then
        -- garage storage and lockers: the manager's tag map
        e.get = function()
            if alive(e.cache) then return e.cache end
            local m = inventoryManager()
            if not m then return nil end
            pcall(function() m.Inventories_Garage:ForEach(function(k, v) if k:get().TagName:ToString() == invName then e.cache = v:get() end end) end)
            return alive(e.cache) and e.cache or nil
        end
    elseif kind == "I" then e.get = function() local m = inventoryManager(); return m and m[invName] or nil end
    else e.get = function() return nil end end
    e.rolled = flagsOf(e)
    ents[id] = e
    return e
end

-- UE's FRotator -> quaternion
local function xform(x, y, z, yaw, pitch, roll)
    local sp, cp = math.sin(math.rad(pitch or 0) / 2), math.cos(math.rad(pitch or 0) / 2)
    local sy, cy = math.sin(math.rad(yaw) / 2), math.cos(math.rad(yaw) / 2)
    local sr, cr = math.sin(math.rad(roll or 0) / 2), math.cos(math.rad(roll or 0) / 2)
    return { Rotation = { X = cr * sp * sy - sr * cp * cy, Y = -cr * sp * cy - sr * cp * sy, Z = cr * cp * sy - sr * sp * cy, W = cr * cp * cy + sr * sp * sy },
             Translation = { X = x, Y = y, Z = z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
end

local function line(e)
    local a = e.actor
    local l, r = a:K2_GetActorLocation(), a:K2_GetActorRotation()
    local what, state
    if e.kind == "L" then what, state = ids.path2(a:GetClass()), stateOf(e)
    elseif e.kind == "B" then what, state = ids.path2(a:GetClass()), "-"
    elseif e.kind == "P" then what, state = ids.path2(a:GetClass()), partState(a)
    else what, state = ids.path(a.Instance.Archetype), "-;" end
    return string.format("A|%s|%s|%.0f|%.0f|%.0f|%.0f|%s", e.id, what, l.X, l.Y, l.Z, r.Yaw, state)
end

-- host ------------------------------------------------------------------------------------------------------------

local function scanHost()
    for _, a in ipairs(FindAllOf("BP_Lootable_Base_C") or {}) do
        local n = alive(a) and alive(a.InventoryContainer) and a:GetFullName()
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
    -- abandoned cars: the body (B) and each part still on it (P); the guest has neither
    for _, a in ipairs(not NO2 and FindAllOf("LootableTemplate") or {}) do
        local n = alive(a) and a:GetFullName()
        if n and not n:find("/Engine/Transient", 1, true) and not byName[n] then
            local e = register("B" .. nextId, "B", a)
            nextId, byName[n] = nextId + 1, e.id
            say(line(e))
        end
    end
    for _, a in ipairs(not NO2 and FindAllOf("LootableTemplatePart") or {}) do
        local n = alive(a) and alive(a.ItemInstance) and a:GetFullName()
        if n and not n:find("/Engine/Transient", 1, true) and not byName[n] then
            local e = register("P" .. nextId, "P", a)
            nextId, byName[n] = nextId + 1, e.id
            e.last = partKey(a)
            say(line(e))
        end
    end
    local names = { table.unpack(INV) }
    local m = inventoryManager()
    if m then
        pcall(function()
            m.Inventories_Garage:ForEach(function(k)
                local tag = k:get().TagName:ToString()
                -- the Toolbox locker is a lootable's container (synced as that lootable); the guest has no container under its tag
                if tag:find("^Stations%.Install%.Inventory%.") and not tag:find("Toolbox", 1, true) then names[#names + 1] = tag end
            end)
        end)
    end
    for _, p in ipairs(names) do
        local id = "I:" .. p
        if not ents[id] then
            local e = register(id, "I", nil, p)
            local c = e.get()
            if alive(c) then
                e.last, e.n = stateOf(e), c:GetNumItems()
                log("PT|loot container %s items=%d state=%d bytes", id, e.n, #e.last)
                say("S|" .. id .. "|" .. e.last)
            else ents[id] = nil end
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

local function spawnPart(class, x, y, z, yaw, state)
    local pitch, roll, spec, mesh = state:match("^([^,]*),([^,]*),([^,]*),([^;]*)")
    local cls, arch = ids.asset(class), spec and ids.archetype(spec:match("^[^:]+"))
    if not cls or not arch then log("PT|loot no part class/archetype %s %s", class, tostring(spec)); return nil end
    local inst = ids.system() and StaticFindObject("/Script/PenDriverInventory.Default__InventoryBlueprintLibrary"):CreateItemInstance(UEHelpers.GetWorld(), arch, 0)
    ids.setProps(inst, spec)
    local gs = UEHelpers.GetGameplayStatics()
    local xf = xform(x, y, z, yaw, tonumber(pitch), tonumber(roll))
    local a = gs:BeginDeferredActorSpawnFromClass(UEHelpers.GetWorld(), cls, xf, 1, nil)
    a.ItemInstance = inst
    local m = mesh ~= "-" and ids.asset(mesh)
    if m then a.RequestedMesh = m end
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
    elseif kind == "B" then
        a = claim("LootableTemplate", function(o) return ids.path2(o:GetClass()) == what and near(o, x, y, z) end)
            or spawnLootable(what, x, y, z, yaw)
    elseif kind == "P" then
        a = claim("LootableTemplatePart", function(o) return alive(o.ItemInstance) and ids.path2(o:GetClass()) == what and near(o, x, y, z) end)
            or spawnPart(what, x, y, z, yaw, state)
        if a then local e = register(id, kind, a); applyState(e, state); e.last = partKey(a); return end
    else
        a = claim("BP_WorldItem_C", function(o) return alive(o.Instance) and ids.path(o.Instance.Archetype) == what and near(o, x, y, z) end)
            or spawnItem(what, x, y, z, yaw)
    end
    if not a then log("PT|loot could not make %s %s", id, what); return end
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
    for _, c in ipairs({ "LootableTemplatePart", "LootableTemplate" }) do
        for _, a in ipairs(FindAllOf(c) or {}) do
            if alive(a) and not claimed[a:GetFullName()] then a:K2_DestroyActor(); n = n + 1 end
        end
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
        elseif e.kind == "P" and not alive(e.actor) then
            -- scrapped or taken here: the host removes its part
            say("T|" .. id)
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
    for _, c in ipairs({ "LootableTemplatePart", "LootableTemplate" }) do
        for _, a in ipairs(FindAllOf(c) or {}) do
            if alive(a) and not claimed[a:GetFullName()] then a:K2_DestroyActor() end
        end
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
        local c = e.get()
        if e.kind == "P" and alive(e.actor) and alive(e.actor.ItemInstance) then
            -- siphoned fuel, worn durability: the part's item state
            local s = partKey(e.actor)
            if s ~= e.last then
                e.last = s
                say("S|" .. id .. "|" .. partState(e.actor))
            end
        elseif alive(c) then
            local r = flagsOf(e)
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

-- overlay: what the other player took from or put into a container
local function announce(e, before)
    local d = (e.n or 0) - (before or 0)
    if d ~= 0 then log("PT|loot overlay %s %s -> %s settled=%s", e.id, tostring(before), tostring(e.n), tostring(ov.settled())) end
    if d == 0 or not ov.settled() then return end
    local what = "a container"
    pcall(function()
        what = e.kind == "I" and e.id:match("^I:Inventory_(.+)$"):gsub("_", " "):lower()
            or e.actor:GetClass():GetFName():ToString():gsub("^BP_Lootable_", ""):gsub("_C$", ""):gsub("_", " "):lower()
    end)
    if d < 0 then ov.post("%d item{s} taken from " .. what, "info", "loot.out." .. e.id, -d)
    else ov.post("%d item{s} put into " .. what, "info", "loot.in." .. e.id, d) end
end

-- messages --------------------------------------------------------------------------------------------------------

local function handle(pc, data)
    if DEAF then return end
    local guest = common.netMode() == "client"
    for l in data:gmatch("[^\n]+") do
        local f = {}
        for p in (l .. "|"):gmatch("([^|]*)|") do f[#f + 1] = p end
        local op, id = f[1], f[2]
        if op == "P" then
            local buf = partial[id] or {}
            partial[id] = buf
            buf[tonumber(f[3])] = f[5] or ""
            local n = 0
            for _ in pairs(buf) do n = n + 1 end
            if n < tonumber(f[4]) then op = nil
            else
                partial[id] = nil
                local s = table.concat(buf, ",")
                op, f, l = "S", { "S", id, s }, "S|" .. id .. "|" .. s
            end
        end
        if op == nil then
        elseif op == "H" and not guest then
            sendAll()
        elseif guest and op == "A" then
            gotAny = true
            onAdd(id, f[3], tonumber(f[4]), tonumber(f[5]), tonumber(f[6]), tonumber(f[7]), f[8])
        elseif guest and op == "F" then
            gotAny = true
            purge()
        elseif op == "S" and ents[id] then
            log("PT|loot got S %s (%s)", id, f[3]:sub(1, 80))
            local before = ents[id].n
            applyState(ents[id], f[3])
            announce(ents[id], before)
            -- the guest's change: the host applies it and the other players see it
            if not guest then say(l) end
        elseif op == "S" and guest then
            gotAny = true
            -- a container of the game's that the guest has not registered yet
            local name = id:match("^I:(.+)$")
            log("PT|loot got new container %s (%d bytes)", id, #f[3])
            if name then applyState(register(id, "I", nil, name), f[3]) end
        elseif op == "D" and guest and ents[id] then
            local e = ents[id]
            ents[id] = nil
            if alive(e.actor) then e.actor:K2_DestroyActor() end
            if e.kind == "W" and ov.settled() then ov.post(ov.other() .. " picked up an item", "info", "pick") end
        elseif op == "N" and not guest then
            spawnItem(f[2], tonumber(f[3]), tonumber(f[4]), tonumber(f[5]), tonumber(f[6]))
        elseif op == "T" and not guest and ents[id] then
            local e = ents[id]
            ents[id], byName[e.name] = nil, nil
            if alive(e.actor) then e.actor:K2_DestroyActor() end
            if e.kind == "W" then ov.post(ov.other() .. " picked up an item", "info", "pick") end
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
    ents, byName, claimed, reported, out, gotAny, partial = {}, {}, {}, {}, {}, false, {}
end)

LoopInGameThreadWithDelay(500, function()
    local ok, err = pcall(tick)
    if not ok then log("PT|error loot %s", tostring(err)) end
end)
