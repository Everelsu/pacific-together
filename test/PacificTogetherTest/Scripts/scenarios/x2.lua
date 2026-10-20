-- X2 world and loot (run as x2garage / x2zone). The host listens on MAP and gives the guest a character next to its
-- own. Both sides list every actor; the client's list reaches the host through a file in %TEMP% and the host diffs
-- names and spots (Q1). The host then replicates at runtime (Q2): L = a level-placed actor both sides have under the
-- same path (garage), A = a runtime-spawned loot actor both sides have, C = a lootable (zone), B = a host-only
-- world item. Its bot opens C and takes the loot, picks B up (Q3) while hooks log the game's calls on both sides.
-- Mutations: x2rename (client renames a loaded actor in its list), x2move (client shifts its loot spots), norep (no
-- SetReplicates), nointeract (the bot never presses interact or takes), nodestroy (the host never destroys a target).
local UEHelpers = require("UEHelpers")

return function(T, MAP, TAG)
    MAP, TAG = MAP or T.GARAGE, TAG or "garage"
    local ROLE, MUTATE, log, name, cls, get = T.ROLE, T.MUTATE, T.log, T.name, T.cls, T.get
    local SHORT = MAP:match("[^/]+$")
    local port = T.HOST:match(":(%d+)$") or "7777"
    local function idFile(side) return string.format("%s\\pt-x2-%s-%s-%s.txt", os.getenv("TEMP"), port, TAG, side) end

    local LOOT = { "Lootable", "WorldItem", "Spawn_Resource", "Spawn_Anchor", "Storage", "Garage_Inventory", "Container",
                   "TemplatePart", "Template_", "ItemSpawner", "SpawnPoint", "LuckyJunkHeap", "GasBarrel", "Lockbox" }
    local function isLoot(c) for _, p in ipairs(LOOT) do if c:find(p, 1, true) then return true end end return false end
    local function loc(a) local l = a:K2_GetActorLocation(); return { X = l.X, Y = l.Y, Z = l.Z } end
    local function d3(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end
    local function path(a) return a:GetFullName():match("^%S+ (.+)$") end
    -- IsValid stays true until GC (17-33 s after a destroy here) and IsActorBeingDestroyed always read false: use PendingKill
    local PENDING_KILL = 0x20000000
    local function alive(a) local ok, r = pcall(function() return a and a:IsValid() and not a:HasAnyInternalFlags(PENDING_KILL) end); return ok and r end

    -- a container's items as "n:Archetype,Archetype"
    local function contents(c)
        if not (c and c:IsValid()) then return "none" end
        local r = {}
        for i = 0, c:GetNumSlots() - 1 do
            local s = c:GetSlot(i)
            for j = 0, s:GetNumItems() - 1 do
                local it = s:GetItem(j)
                r[#r + 1] = it:IsValid() and name(get(it, "Archetype")):match("([^%.]+)$") or "?"
            end
        end
        return #r .. ":" .. table.concat(r, ",")
    end
    local function count(c) return tonumber(contents(c):match("^(%d+)")) or -1 end
    local function lootState(a)
        local c = get(a, "InventoryContainer")
        local ok, valid = pcall(function() return c:IsValid() end)
        if not (ok and valid) then return "" end
        return string.format(" populated=%s rolledOnOpen=%s empty=%s items=%s", tostring(get(a, "Container Populated")),
            tostring(get(a, "RolledOnOpenItems")), tostring(get(a, "Empty")), contents(c))
    end

    -- every actor of the current world: class, path, location, loaded-from-map, role
    local RF_WasLoaded = 0x00080000
    local function actorList()
        local wn, r = T.world():GetFullName(), {}
        for _, a in ipairs(FindAllOf("Actor") or {}) do
            pcall(function()
                if not a:IsValid() or a:GetWorld():GetFullName() ~= wn then return end
                local l = loc(a)
                r[#r + 1] = { class = cls(a), path = path(a), x = l.X, y = l.Y, z = l.Z, loaded = a:HasAnyFlags(RF_WasLoaded) and 1 or 0,
                              role = tostring(a.Role), pk = a:HasAnyInternalFlags(PENDING_KILL) and 1 or 0, actor = a }
            end)
        end
        return r
    end
    local function logList(list)
        local pk = 0
        for _, e in ipairs(list) do
            pk = pk + e.pk
            if isLoot(e.class) then
                log("PT|id side=%s tag=%s class=%s path=%s loaded=%d role=%s pendingKill=%d loc=%.0f,%.0f,%.0f%s", ROLE, TAG, e.class, e.path,
                    e.loaded, e.role, e.pk, e.x, e.y, e.z, lootState(e.actor))
            end
        end
        log("PT|info idlist %s: %d actors, %d of them pending kill", TAG, #list, pk)
    end
    local function writeList(list, file)
        local f, renamed = assert(io.open(file .. ".tmp", "w")), false
        for _, e in ipairs(list) do if e.pk == 0 then
            local p, x = e.path, e.x
            if MUTATE == "x2rename" and e.loaded == 1 and not renamed then p = p .. "_renamed"; renamed = true end
            if MUTATE == "x2move" and e.loaded == 0 and isLoot(e.class) then x = x + 500 end
            f:write(string.format("%s\t%s\t%.0f\t%.0f\t%.0f\t%d\n", e.class, p, x, e.y, e.z, e.loaded))
        end end
        f:close()
        os.remove(file)
        assert(os.rename(file .. ".tmp", file))
    end
    local function readList(file)
        local f = io.open(file, "r")
        if not f then return nil end
        local r = {}
        for line in f:lines() do
            local c, p, x, y, z, ld = line:match("^(.-)\t(.-)\t(%S+)\t(%S+)\t(%S+)\t(%d)$")
            if c then r[#r + 1] = { class = c, path = p, x = tonumber(x), y = tonumber(y), z = tonumber(z), loaded = tonumber(ld) } end
        end
        f:close()
        return r
    end

    -- Q1. Per class: same path at the same spot, same path moved, and of the one-sided ones how many have a same-class
    -- partner on the other side within 50 uu (= the same object under another name)
    local diff = { partner = {}, same = {} }
    local function pt(e) return { X = e.x, Y = e.y, Z = e.z } end
    -- only live actors: a destroyed one stays listed until GC, at a spot it may no longer have (both sides, 125124)
    local function compare(hostAll, clientL)
        local hostL = {}
        for _, e in ipairs(hostAll) do
            if e.pk == 0 then hostL[#hostL + 1] = e
            elseif e.loaded == 1 then log("PT|iddiff dead loaded class=%s path=%s loc=%.0f,%.0f,%.0f", e.class, e.path, e.x, e.y, e.z) end
        end
        local st, byPath, seen, hOnly, cOnly = {}, {}, {}, {}, {}
        local Z = function() return { same = 0, moved = 0, renamed = 0, host = 0, client = 0 } end
        local tot, loot, loaded, spawned = Z(), Z(), Z(), Z()
        local function add(e, f)
            st[e.class] = st[e.class] or Z()
            local ts = { st[e.class], tot, e.loaded == 1 and loaded or spawned }
            if isLoot(e.class) then ts[#ts + 1] = loot end
            for _, t in ipairs(ts) do t[f] = t[f] + 1 end
        end
        for _, e in ipairs(hostL) do byPath[e.path] = e end
        for _, e in ipairs(clientL) do
            local h = byPath[e.path]
            if h and h.class == e.class then
                seen[e.path] = true
                diff.same[e.path] = true
                add(h, d3(pt(h), pt(e)) < 50 and "same" or "moved")
            else
                cOnly[#cOnly + 1] = e
            end
        end
        for _, e in ipairs(hostL) do if not seen[e.path] then hOnly[#hOnly + 1] = e end end
        for _, c in ipairs(cOnly) do
            local best
            for i, h in ipairs(hOnly) do
                if not h.used and h.class == c.class and d3(pt(h), pt(c)) < 50 then best = i; break end
            end
            if best then
                local h = hOnly[best]
                h.used = true
                diff.partner[h.path] = c.path
                add(h, "renamed")
                if isLoot(c.class) then log("PT|iddiff renamed class=%s loaded=%d host=%s client=%s", c.class, h.loaded, h.path, c.path) end
            else
                add(c, "client")
            end
        end
        for _, h in ipairs(hOnly) do if not h.used then add(h, "host") end end
        local keys = {}
        for k in pairs(st) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local v = st[k]
            log("PT|iddiff tag=%s class=%s loot=%d same=%d moved=%d renamed=%d hostOnly=%d clientOnly=%d", TAG, k, isLoot(k) and 1 or 0,
                v.same, v.moved, v.renamed, v.host, v.client)
        end
        for n, v in pairs({ all = tot, loot = loot, loaded = loaded, spawned = spawned }) do
            log("PT|info iddiff %s %s: same=%d moved=%d renamed=%d hostOnly=%d clientOnly=%d", TAG, n, v.same, v.moved, v.renamed, v.host, v.client)
        end
        diff.loot, diff.loaded, diff.spawned = loot, loaded, spawned
        diff.clientPaths = {}
        for _, e in ipairs(clientL) do diff.clientPaths[e.path] = true end
    end

    -- Q3: log the game's interaction and inventory calls (first 4 of each with arguments, then a count)
    local calls, hooked = {}, false
    local function argStr(p)
        local ok, v = pcall(function() return p:get() end)
        if not ok then return "?" end
        if type(v) == "userdata" then
            local okn, n = pcall(function() return v:IsValid() and v:GetFullName():match("([^%.:]+)$") .. "<" .. cls(v) .. ">" or "none" end)
            if okn then return n end
            local okt, t = pcall(function() return v:ToString() end)
            return okt and t or "ud"
        end
        return tostring(v)
    end
    local function onCall(fn, self, ...)
        calls[fn] = (calls[fn] or 0) + 1
        if calls[fn] <= 4 then
            local a = {}
            for i, p in ipairs({ ... }) do if i <= 3 then a[#a + 1] = argStr(p) end end
            log("PT|call side=%s fn=%s n=%d self=%s args=%s", ROLE, fn, calls[fn], argStr(self), table.concat(a, " | "))
        end
    end
    local NATIVE = {
        ["/Script/PenDriverPro.HighlightComponent"] = { "InteractPressed", "InteractReleased", "OnInteractTimeComplete", "OnShortInteractTimeComplete" },
        ["/Script/PenDriverInventory.ItemContainer"] = { "AddItem", "RemoveItem", "RemoveItems", "RemoveAllItems" },
        ["/Script/PenDriverInventory.ItemSlot"] = { "AddItem", "AddItems", "RemoveItem", "SetItem", "TransferStackIntoContainer", "TransferSingleIntoContainer", "TransferStackIntoSlot", "TransferSwapIntoSlot", "TransferSingleIntoSlot" },
        ["/Script/PenDriverInventory.ContainerCursor"] = { "TransferSlot", "TransferHovered", "TransferContainerWithLinkage", "TransferSlotWithLinkage" },
        ["/Script/PenDriverInventory.InventorySystem"] = { "SpawnItemActor", "SpawnItemInstanceActor" },
        ["/Script/PenDriverInventory.ItemActorManifestation"] = { "MarkAsWorldOwned" },
        ["/Script/PenDriverPro.BaseInventoryManager"] = { "MarkCriticalitemPickedUp", "BindItemInstanceToSpawningActor", "GiveItemToPlayer" },
        ["/Script/PenDriverUtils.PooledActor"] = { "OnReturnToPool", "OnCreatedFromPool" },
        -- Actor:K2_DestroyActor left out: hooking it caught every engine destroy for no answer (spike X2 notes)
    }
    local BP = {
        PDP_MainCharacter_C = { "Command Interact", "Interact_WorldInteraction", "Pickup Actor", "Interaction_InventoryAction", "LongInventoryInteract", "Interaction_Deposit" },
        BP_HighlightManager_C = { "HighlightPress", "SetHighlight" },
        BP_InventoryManager_C = { "OpenInventoryContainer", "AddToContainers", "AddToContainer", "AddToAnySlot", "AddToAnySlotInventory", "RemoveInstanceOrActor", "RemoveInstance", "CreateItemInPlayerInventory", "PlayerDropHandItem", "DepositAnchorsAfterRun", "OpenPlayerInventory", "RequestPlayerMenuClose" },
        BP_Lootable_Base_C = { "OnInteractedWith", "Populate Container", "Initialize Container", "OnRollForOpenItems", "SwitchToOpenedVisuals", "UpdateVisualsForEmpty", "UpdateInteractionOpened", "BoundOnEventItemCountChanged", "HighlightInteract", "HighlightInteractStart", "EvalChanceToLive" },
        BP_WorldItem_C = { "OnWorldItemInteracted", "GetVacuumed", "Set World Item Interactable" },
        BP_Spawn_Resource_GrabBase_C = { "ShortGrabComplete", "Long Grab Complete" },
        BP_Spawn_Anchor_Base_01_C = { "AnchorTaken", "AddAnchorPulledTag", "Long Grab Complete" },
        BP_ItemHarvestableComponent_C = { "DoSmash", "DoCut", "DoStrip", "DoBreak", "DoExtract", "DoGrind", "DoSeparate", "SpawnItems", "FinishHarvestingLoop" },
    }
    -- the Blueprint class named c: walk up from a live instance (managers are not found by FindObject), else FindObject
    local function bpClass(c)
        local inst = FindFirstOf(c)
        local k = inst and inst:IsValid() and inst:GetClass() or nil
        while k and k:IsValid() and k:GetFName():ToString() ~= c do k = k:GetSuperStruct() end
        if k and k:IsValid() then return k end
        k = FindObject("BlueprintGeneratedClass", c)
        return k and k:IsValid() and k or nil
    end
    local function hookAll()
        if hooked then return end
        hooked = true
        local ok, failed = 0, {}
        local function try(full, fn)
            local okh, err = pcall(RegisterHook, full, function(self, ...) onCall(fn, self, ...) end)
            if okh then ok = ok + 1 else failed[#failed + 1] = fn .. "(" .. tostring(err):sub(1, 50) .. ")" end
        end
        for owner, fns in pairs(NATIVE) do
            local short = owner:match("%.(%w+)$")
            for _, f in ipairs(fns) do try(owner .. ":" .. f, short .. ":" .. f) end
        end
        for c, fns in pairs(BP) do
            local k = bpClass(c)
            if k then
                local p = k:GetFullName():match("^%S+ (.+)$")
                for _, f in ipairs(fns) do try(p .. ":" .. f, c .. ":" .. f) end
            else
                failed[#failed + 1] = c .. "(class not loaded)"
            end
        end
        log("PT|info hooks side=%s ok=%d failed=%d %s", ROLE, ok, #failed, table.concat(failed, " "))
    end
    local function callSummary(tag)
        local keys = {}
        for k in pairs(calls) do keys[#keys + 1] = k end
        table.sort(keys)
        local r = {}
        for _, k in ipairs(keys) do r[#r + 1] = k .. "=" .. calls[k] end
        log("PT|calls side=%s tag=%s %s", ROLE, tag, table.concat(r, " "))
    end
    local function snapshotCalls() local c = {}; for k, v in pairs(calls) do c[k] = v end; return c end
    local function newCalls(since)
        local r = {}
        for k, v in pairs(calls) do if v > ((since or {})[k] or 0) then r[#r + 1] = k end end
        table.sort(r)
        return r
    end
    local function calledAny(since, prefixes)
        for _, k in ipairs(newCalls(since)) do
            for _, p in ipairs(prefixes) do if k:find(p, 1, true) == 1 then return true end end
        end
        return false
    end

    -- the guest's character, spawned by the host (as in "body")
    local function spawnGuest()
        local hostChar, made = T.myPawn(), nil
        assert(hostChar and cls(hostChar) == T.CHAR, "host pawn " .. cls(hostChar))
        for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
            if T.inWorld(pc) and not pc:IsLocalController() then
                local cm = T.first("BP_MainCharacterManager_C")
                local before = cm and cm.CharacterActor
                local l = hostChar:K2_GetActorLocation()
                local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X + 150, Y = l.Y, Z = l.Z + 60 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
                local gs = UEHelpers.GetGameplayStatics()
                made = gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(T.world(), hostChar:GetClass(), xf, 2, nil), xf)
                pc:Possess(made)
                if cm and before and before:IsValid() and cm.CharacterActor:GetFullName() ~= before:GetFullName() then cm.CharacterActor = before end
                log("PT|info spawned %s for %s d=%.0f", name(made), name(pc), T.dist(hostChar, made))
            end
        end
        return made
    end

    -- move the host to stand ~140 uu from target, and the guest a bit behind it, both facing it
    local guest
    local function approach(target)
        if not alive(target) then return false end
        local me, tl = T.myPawn(), loc(target)
        for i = 0, 7 do
            local yaw = math.rad(45 * i)
            local to = { X = tl.X + math.cos(yaw) * 140, Y = tl.Y + math.sin(yaw) * 140, Z = tl.Z + 90 }
            if me:K2_TeleportTo(to, { Pitch = 0, Yaw = math.deg(yaw) + 180, Roll = 0 }) then
                if alive(guest) then guest:K2_TeleportTo({ X = tl.X + math.cos(yaw) * 280, Y = tl.Y + math.sin(yaw) * 280, Z = tl.Z + 90 }, { Pitch = 0, Yaw = math.deg(yaw) + 180, Roll = 0 }) end
                log("PT|info approached %s try=%d d=%.0f", name(target), i, d3(loc(me), tl))
                return true
            end
        end
        log("PT|info approach failed %s", name(target))
        return false
    end
    local function hlOf(a) local h = get(a, "Highlight"); return (h and h:IsValid()) and h or nil end
    local function aim(target)
        if not alive(target) then return end
        local pc, hl = T.localPC(), hlOf(target)
        local c = hl and hl:GetCollisionCenter() or target:K2_GetActorLocation()
        local cam = pc.PlayerCameraManager:GetCameraLocation()
        local dx, dy, dz = c.X - cam.X, c.Y - cam.Y, c.Z - cam.Z
        pc:SetControlRotation({ Pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = 0 })
    end
    local function hlMgr() return T.first("BP_HighlightManager_C") end
    local function hlInfo(a)
        local hl = hlOf(a)
        if not hl then return "no Highlight" end
        return string.format("hold=%.2f short=%.2f long=%.2f", hl.HoldTime, hl:GetShortDuration(), hl:GetLongDuration())
    end
    -- press interact the player's way. The highlight manager's own trace must point at the target; when it does not
    -- (logged traced=false), the target's highlight is set on the manager every frame while the button is held.
    local function interact(target, holdMs)
        if not alive(target) then return end
        local me, m, hl = T.myPawn(), hlMgr(), hlOf(target)
        local cur, cam = m and m.CurrentHighlight, T.localPC().PlayerCameraManager:GetCameraRotation()
        local traced = (cur and cur:IsValid() and hl and cur:GetFullName() == hl:GetFullName()) == true
        log("PT|info interact %s hold=%dms traced=%s current=%s camRot=(p%.0f y%.0f)", name(target), holdMs, tostring(traced), name(cur), cam.Pitch, cam.Yaw)
        if MUTATE == "nointeract" then return end
        local force
        if not traced and m and hl then
            force = LoopInGameThreadWithDelay(10, function() pcall(function()
                if m.CurrentHighlight:GetFullName() ~= hl:GetFullName() then m:SetHighlight(hl) end
            end) end)
            m:SetHighlight(hl)
        end
        me["Command Interact"](me, true)
        ExecuteInGameThreadWithDelay(holdMs, function()
            pcall(function() me["Command Interact"](me, false) end)
            ExecuteInGameThreadWithDelay(200, function() if force then CancelDelayedAction(force) end end)
        end)
    end
    local function nearest(pred)
        local me, best, bd = T.myPawn(), nil, math.huge
        for _, a in ipairs(FindAllOf("Actor") or {}) do
            local ok, d = pcall(function()
                if not (T.inWorld(a) and alive(a) and pred(a)) then return nil end
                return T.dist(me, a)
            end)
            if ok and d and d < bd then best, bd = a, d end
        end
        return best
    end
    local function invMgr() return T.first("BP_InventoryManager_C") end
    local function backpack() local m = invMgr(); return m and m.Inventory_Player end
    local function hand() local m = invMgr(); return m and m.Inventory_PlayerHand end
    local function carried() return math.max(count(backpack()), 0) + math.max(count(hand()), 0) end
    local function takeInto() local b = backpack(); return (b and b:GetNumSlots() > 0) and b or hand() end
    local function replicate(a, tag)
        if alive(a) and MUTATE ~= "norep" then a:SetReplicates(true); a:SetReplicateMovement(true); a:ForceNetUpdate() end
        log("PT|info replicate %s %s: bReplicates=%s remoteRole=%s", tag, alive(a) and path(a) or "none", tostring(alive(a) and a.bReplicates), tostring(alive(a) and a.RemoteRole))
    end
    local function destroy(a, tag)
        if not alive(a) or MUTATE == "nodestroy" then return end
        a:K2_DestroyActor()
        log("PT|info destroy %s %s pendingKill=%s", tag, path(a), tostring(not alive(a)))
    end

    -- the host announces each target (tag, class, host path, the guest's own copy) in a second file
    local function announce(tag, a)
        local f = assert(io.open(idFile("targets"), "a"))
        local p = alive(a) and path(a)
        f:write(string.format("%s\t%s\t%s\t%s\n", tag, p and cls(a) or "none", p or "none", p and (diff.same[p] and p or diff.partner[p]) or "none"))
        f:close()
    end
    local function announced(tag)
        local f = io.open(idFile("targets"), "r")
        if not f then return nil end
        local r
        for line in f:lines() do
            local t, c, p, mine = line:match("^(.-)\t(.-)\t(.-)\t(.-)$")
            if t == tag then r = { class = c, path = p, mine = mine } end
        end
        f:close()
        return r
    end

    local function listStep()
        return { run = function()
            local list = actorList()
            logList(list)
            if ROLE == "client" then writeList(list, idFile("client")) else diff.host = list end
        end }
    end
    local function add(steps, more) for _, s in ipairs(more) do steps[#steps + 1] = s end end

    if ROLE == "host" then
        local L, A, C, B, since, before = nil, nil, nil, nil, nil, {}
        local hostOnly = function(a) local p = path(a); return not diff.same[p] and not diff.partner[p] end
        local function pick(pred) for _, e in ipairs(diff.host) do if alive(e.actor) and pred(e) then return e.actor end end end
        local function bagCount() return carried() end
        local steps = {
            { run = function() os.remove(idFile("client")); os.remove(idFile("targets")) end },
            T.onMap("RB_MainMenu", 90),
            { wait = 5 },
            { run = function() T.console("open " .. MAP .. "?listen") end },
            { check = "host_listen_" .. TAG, timeout = 180, cond = function() return T.netMode() == "listen" and T.map() == SHORT end },
            { check = "host_two_pcs", timeout = 180, cond = function() return T.pcs() == 2 end },
            { wait = 10 },
            { check = "host_spawned_guest", timeout = 30, cond = function() guest = spawnGuest(); return alive(guest) end },
            { run = hookAll },
            -- without a save the player's backpack has no slots, so nothing could be taken; give it some (test only)
            { run = function()
                local b = backpack()
                log("PT|info backpack slots=%s", tostring(b and b:GetNumSlots()))
                if b and b:GetNumSlots() == 0 then for _ = 1, 16 do b:AddSlot() end; log("PT|info backpack slots now %d", b:GetNumSlots()) end
            end },
            { wait = 25 },
            { run = function() T.survey(TAG) end },
            listStep(),
            { check = "x2_ids_compared", timeout = 120, cond = function()
                local c = readList(idFile("client"))
                if not c then return false end
                compare(diff.host, c)
                return true
            end },
            -- Q1: level-placed actors keep their path on both sides; runtime-spawned loot is the same object at the same spot
            -- one-sided loaded actors are allowed: the host's spawn pass consumes pre-placed ones (BP_ClumpedArea_*_PrePlaced)
            { check = "x2_loaded_ids_stable", timeout = 0, cond = function() return diff.loaded.same > 0 and diff.loaded.moved == 0 and diff.loaded.renamed == 0 end },
            -- garage stations and storage are spawned on both sides at the same spots under different names (zones roll their own loot)
            TAG == "garage" and { check = "x2_spawned_loot_matched_by_spot", timeout = 0, cond = function() return diff.loot.renamed >= 10 end } or { wait = 0 },
        }
        -- Q2: L, a visible level-placed actor with the same path on both sides, nearest of the first kind found.
        -- Garage only: in the zone the candidates (road endings) never arrived on the guest (spike X2 notes)
        if TAG == "garage" then add(steps, {
            { run = function()
                local me = loc(T.myPawn())
                for _, kind in ipairs({ "Destruct", "RoadObstruct", "RoadEnding", "StaticMeshActor", "FoliageStruc" }) do
                    local bd = math.huge
                    for _, e in ipairs(diff.host) do
                        if not L or bd < math.huge then
                            if e.loaded == 1 and diff.same[e.path] and e.class:find(kind, 1, true) and alive(e.actor) and not e.actor.bHidden then
                                local d = d3(me, pt(e))
                                if d < bd then L, bd = e.actor, d end
                            end
                        end
                    end
                end
                log("PT|info x2 target L (loaded, same path) = %s %s", cls(L), L and path(L) or "none")
                announce("L", L)
                approach(L)
            end },
            { check = "host_has_loaded_target", timeout = 0, cond = function() return alive(L) end },
            { wait = 2 },
            { run = function() replicate(L, "L"); log("PT|info L attachParent=%s", alive(L) and name(L:GetAttachParentActor()) or "-") end },
            { wait = 20 },
            { run = function() destroy(L, "L") end },
            { wait = 15 },
        }) end
        add(steps, {
            -- A, a runtime-spawned loot actor the guest also spawned (under another name)
            { run = function()
                -- spawned (not loaded) and on both sides: same name first (zone), else same spot (garage). Zone lootables
                -- match only when both sides kept the same variant, so the car's trunk storage (same spot, every run) is last
                local kinds = { "Lootable", "InventoryParts", "InventoryExpansion", "LuckyJunkHeap", "Spawn_Resource", "WorldItem", "Storage_Trunk" }
                for _, p in ipairs(kinds) do A = A or pick(function(e) return e.class:find(p, 1, true) and e.loaded == 0 and diff.same[e.path] end) end
                for _, p in ipairs(kinds) do A = A or pick(function(e) return e.class:find(p, 1, true) and diff.partner[e.path] end) end
                log("PT|info x2 target A (spawned, both sides) = %s %s partner=%s %s%s", cls(A), A and path(A) or "none", A and diff.partner[path(A)] or "-", A and hlInfo(A) or "", A and lootState(A) or "")
                announce("A", A)
                approach(A)
            end },
            { check = "host_has_shared_target", timeout = 0, cond = function() return alive(A) end },
            { wait = 2 },
            { run = function() replicate(A, "A"); if alive(A) then log("PT|info A attachParent=%s loc=%.0f,%.0f,%.0f", name(A:GetAttachParentActor()), loc(A).X, loc(A).Y, loc(A).Z) end end },
            { wait = 20 },
            { run = function() destroy(A, "A") end },
            { wait = 15 },
        })
        -- C, a lootable (host-only if there is one; the garage has none without a save); Q3: open and take everything
        if TAG == "zone" then add(steps, {
            { run = function()
                -- not A: with nodestroy A is still alive, and the client already counted it
                local notA = function(e) return not (A and alive(A) and e.path == path(A)) end
                C = pick(function(e) return e.class:find("^BP_Lootable") and hostOnly(e.actor) and notA(e) end) or pick(function(e) return e.class:find("^BP_Lootable") and notA(e) end)
                log("PT|info x2 target C (lootable) = %s %s hostOnly=%s %s%s", cls(C), C and path(C) or "none", tostring(C and hostOnly(C)), C and hlInfo(C) or "", C and lootState(C) or "")
                announce("C", C)
                approach(C)
            end },
            { check = "host_has_lootable", timeout = 0, cond = function() return alive(C) end },
            { wait = 2 },
            { run = function()
                local parent = alive(C) and C:GetAttachParentActor()
                local had = parent and parent:IsValid()
                if had then C:K2_DetachFromActor(1, 1, 1) end
                log("PT|info C attachParent=%s detached=%s loc=%.0f,%.0f,%.0f", name(parent), tostring(had), loc(C).X, loc(C).Y, loc(C).Z)
                replicate(C, "C"); aim(C)
            end },
            { wait = 15 },
            { run = function() aim(C); since = snapshotCalls(); before = { loot = alive(C) and contents(get(C, "InventoryContainer")) or "none", bag = bagCount() } end },
            { wait = 1 },
            { run = function() interact(C, 600) end },
            { wait = 3 },
            { run = function()
                log("PT|info after open C: calls=%s%s", table.concat(newCalls(since), ","), alive(C) and lootState(C) or "")
                if MUTATE == "nointeract" or not alive(C) then return end
                local c = get(C, "InventoryContainer")
                if not (c and c:IsValid()) then return end
                for i = c:GetNumSlots() - 1, 0, -1 do
                    local s = c:GetSlot(i)
                    if s:IsValid() and s:GetNumItems() > 0 then log("PT|info take slot %d -> %s", i, tostring(s:TransferStackIntoContainer(takeInto(), {}))) end
                end
            end },
            { wait = 2 },
            { run = function()
                log("PT|info took from C: loot %s -> %s, carried %d -> backpack %s hand %s; calls=%s", before.loot, alive(C) and contents(get(C, "InventoryContainer")) or "gone", before.bag,
                    contents(backpack()), contents(hand()), table.concat(newCalls(since), ","))
                callSummary("afterC")
            end },
            { check = "host_open_lootable_game_path", timeout = 0, cond = function() return calledAny(since, { "BP_Lootable_Base_C:", "BP_InventoryManager_C:OpenInventoryContainer" }) end },
            -- the bot's own TransferStackIntoContainer, not a UI or player transfer
            { check = "host_transfer_takes_loot", timeout = 0, cond = function() return bagCount() > before.bag end },
            { run = function() destroy(C, "C") end },
            { wait = 20 },
        }) end
        -- B, a world item only the host has (runtime spawned); Q3: pick it up the player's way
        add(steps, {
            { run = function()
                local free = function(a) return hostOnly(a) and not a.bHidden and not a:GetAttachParentActor():IsValid() end
                B = nearest(function(a) return cls(a) == "BP_WorldItem_C" and free(a) end)
                    or nearest(function(a) return cls(a):find("^BP_WorldItem") and free(a) end)
                    or nearest(function(a) return cls(a):find("^BP_WorldItem") and hostOnly(a) and not a.bHidden end)
                log("PT|info x2 target B (host-only item) = %s %s %s", cls(B), B and path(B) or "none", B and hlInfo(B) or "")
                announce("B", B)
                approach(B)
            end },
            { check = "host_has_world_item", timeout = 0, cond = function() return alive(B) end },
            { wait = 2 },
            { run = function() replicate(B, "B"); aim(B); if alive(B) then log("PT|info B attachParent=%s loc=%.0f,%.0f,%.0f", name(B:GetAttachParentActor()), loc(B).X, loc(B).Y, loc(B).Z) end end },
            { wait = 15 },
            { run = function() aim(B); since = snapshotCalls(); before.bag = bagCount() end },
            { wait = 1 },
            { run = function() interact(B, 600) end },
            { wait = 4 },
            -- if the player's path did not take it: the highlight component itself, then the character's Pickup Actor
            { run = function()
                local m, hand = invMgr(), nil
                hand = m and m.Inventory_PlayerHand
                log("PT|info after player-path pickup B: alive=%s hidden=%s calls=%s backpackSlots=%s handSlots=%s hand=%s", tostring(alive(B)), tostring(alive(B) and B.bHidden),
                    table.concat(newCalls(since), ","), tostring(backpack() and backpack():GetNumSlots()), tostring(hand and hand:GetNumSlots()), contents(hand))
                if MUTATE == "nointeract" or not alive(B) or B.bHidden then return end
                local hl, me = hlOf(B), T.myPawn()
                hl:InteractPressed(me)
                ExecuteInGameThreadWithDelay(600, function() pcall(function() hl:InteractReleased(me) end) end)
            end },
            { wait = 3 },
            { run = function()
                log("PT|info after component pickup B: alive=%s hidden=%s calls=%s", tostring(alive(B)), tostring(alive(B) and B.bHidden), table.concat(newCalls(since), ","))
                if MUTATE == "nointeract" or not alive(B) or B.bHidden then return end
                local me = T.myPawn()
                me["Pickup Actor"](me, B, false)
            end },
            { wait = 3 },
            -- the zone's balls (IA_Garage_*Ball_Item) did not go into the backpack, even an empty one: try to hands
            { run = function()
                if MUTATE == "nointeract" or not alive(B) or B.bHidden then return end
                log("PT|info Pickup Actor to backpack left B; to hands")
                local me = T.myPawn()
                me["Pickup Actor"](me, B, true)
            end },
            { wait = 3 },
            { run = function()
                log("PT|info after pickup B: alive=%s hidden=%s backpack %d -> %s calls=%s", tostring(alive(B)), tostring(alive(B) and B.bHidden),
                    before.bag, contents(backpack()), table.concat(newCalls(since), ","))
                callSummary("afterB")
            end },
            -- the pickup (ours or the game's) took B: the world actor is gone and we carry one more; we have not destroyed it yet
            { check = "host_pickup_completes", timeout = 0, cond = function() return not alive(B) and bagCount() > before.bag end },
            { run = function() log("PT|info pickup completed=%s carried %d -> %d", tostring(not alive(B)), before.bag, bagCount()); destroy(B, "B") end },
            { wait = 30 },
            { run = function() callSummary("end") end },
        })
        return steps
    end

    -- client ---------------------------------------------------------------------------------------------------------
    local own, preRep, taken, rep, tgt = {}, {}, {}, {}, {}
    local function find(t)
        for _, a in ipairs(FindAllOf(t.class) or {}) do
            local ok, hit = pcall(function()
                if not (T.inWorld(a) and alive(a) and a.Role == 1) then return false end
                local p = path(a)
                return not preRep[p] and not taken[p]
            end)
            if ok and hit then taken[path(a)] = true; return a end
        end
    end
    local function mineAlive(t)
        local o = t.mine ~= "none" and StaticFindObject(t.mine)
        return o and alive(o) and o or nil
    end
    local function report(tag, a)
        local t = tgt[tag]
        if not (t and alive(a)) then log("PT|info replicated %s none", tag); return end
        local mine, n = mineAlive(t), 0
        for _, o in ipairs(FindAllOf(t.class) or {}) do if T.inWorld(o) and alive(o) then n = n + 1 end end
        local l = loc(a)
        log("PT|info replicated %s %s role=%s samePathAsHost=%s boundToOwnCopy=%s ownCopy=%s(role=%s) sameClassNow=%d hidden=%s loc=%.0f,%.0f,%.0f ownObject=%s%s", tag, path(a),
            tostring(a.Role), tostring(path(a) == t.path), tostring(mine ~= nil and mine:GetFullName() == a:GetFullName()), mine and path(mine) or "none",
            tostring(mine and mine.Role), n, tostring(a.bHidden), l.X, l.Y, l.Z, tostring(t.mine ~= "none" and select(2, pcall(function() return StaticFindObject(t.mine):IsValid() end))), lootState(a))
    end
    -- told = the host announced the target; seen = it arrived replicated within 20 s; gone = destroyed / picked up
    local function phase(tag, nextTag)
        -- gone gets its 90 s only once seen; unseen it fails at once, so the client stays in step with the host. Once the
        -- host has announced the next target it walks away, and a removal after that is relevancy, not the host's destroy
        local gone
        gone = { check = "client_" .. tag .. "_gone", timeout = 0, cond = function()
            if rep[tag] == nil then return false end
            if nextTag and announced(nextTag) then gone.timeout = 0; return false end
            return not alive(rep[tag]) or rep[tag].bHidden == true
        end }
        local s = {
            { check = "client_told_" .. tag, timeout = 400, cond = function() tgt[tag] = announced(tag); return tgt[tag] ~= nil end },
            { check = "client_sees_replicated_" .. tag, timeout = 20, cond = function()
                rep[tag] = find(tgt[tag])
                if rep[tag] then report(tag, rep[tag]); gone.timeout = 90 end
                return rep[tag] ~= nil
            end },
            gone,
        }
        s[#s + 1] = { run = function()
            local m = mineAlive(tgt[tag])
            log("PT|info after %s: replicated alive=%s hidden=%s; own copy %s alive=%s", tag, tostring(alive(rep[tag])), tostring(alive(rep[tag]) and rep[tag].bHidden),
                tgt[tag].mine, tostring(m ~= nil))
        end }
        return s
    end
    local steps = {
        T.onMap("RB_MainMenu", 90),
        { run = function() StaticFindObject("/Script/OnlineSubsystemUtils.Default__IpNetDriver").ResolutionConnectionTimeout = 120 end },
        T.join("client_connected_" .. TAG, SHORT, 240, 30),
        { check = "client_possessed", timeout = 90, cond = function() return cls(T.myPawn()) == T.CHAR end },
        { run = hookAll },
        { wait = 25 },
        { run = function() T.survey(TAG) end },
        listStep(),
        { run = function() for _, e in ipairs(actorList()) do own[e.path] = e.class; if e.role == "1" then preRep[e.path] = true end end end },
    }
    if TAG == "garage" then add(steps, phase("L", "A")) end
    add(steps, phase("A", TAG == "zone" and "C" or "B"))
    if TAG == "zone" then
        add(steps, phase("C", "B"))
    end
    add(steps, phase("B"))
    add(steps, { { run = function() callSummary("end") end }, { wait = 5 } })
    return steps
end
