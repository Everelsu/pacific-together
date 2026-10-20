-- X12: the guest's backpack (items, stack counts, grid position, rotation, durability, hand, quick slots) as a small
-- text record. The guest fills its own backpack, sends the record to the host (ServerExecRPC), the host rebuilds it
-- in a container of its own, writes it next to its save slot on SaveGame (odsave7.pt-<id>.txt), the guest leaves,
-- wipes its backpack and rejoins, the host sends the record back (ClientMessage) and the guest rebuilds it; then the
-- host reloads its save (LoadGame), reads the record from the file only, and the guest rejoins and rebuilds again.
-- -Mutate nosend: the host never sends the record back; nopersist: the host writes no file and forgets the record
-- before the reload; nodur: rebuilding skips durability (every comparison with durability changes fails); keepguest: the
-- guest character stays in the world through the host's LoadGame (expect the 0x20 BeginTearingDown crash).
local G = require("scenarios.guestchar")
local SLOT, GUEST_ID = 7, "76561190000000002" -- stand-in SteamID; the real one must come from the handshake (S4)
local DUR_FIELD = "Durability_5_448CDA0B4D9935979EBC4AA6A500ADAF"
local ITEMS = "/Game/Gameplay/Inventory/Items/"
local GIVE = { -- archetype, count, durability (nil = keep)
    { ITEMS .. "Resources/Basic/RawSteel/IA_Resource_Raw_Scrap_Steel.IA_Resource_Raw_Scrap_Steel", 7 },
    { ITEMS .. "Tools/Scrapper/IA_Tool_Target_ItemHarvest_Scrapper.IA_Tool_Target_ItemHarvest_Scrapper", 1, 123 },
    { ITEMS .. "Tools/FuelCan/FuelCan5G/IA_Tool_Target_FuelCan_5Gal.IA_Tool_Target_FuelCan_5Gal", 1 },
    { ITEMS .. "Tools/Cutter/IA_Tool_Target_ItemHarvest_Cutter_T1.IA_Tool_Target_ItemHarvest_Cutter_T1", 1, 4 },
}

return function(T)
    local log, MUTATE = T.log, T.MUTATE
    local lib = StaticFindObject("/Script/PenDriverInventory.Default__InventoryBlueprintLibrary")
    local function bfl() return FindObject("BFL_ItemPropertyUtilityFns_C", "Default__BFL_ItemPropertyUtilityFns_C") end
    local function path(o) return o:GetFullName():match("^%S+ (.+)$") end
    local durProp = {} -- archetype path -> the IP_Durability struct asset, or false
    local function durOf(a)
        local p = path(a)
        if durProp[p] == nil then
            durProp[p] = false
            a.Properties:ForEach(function(_, e) local s = e:get(); if s:GetFName():ToString() == "IP_Durability" then durProp[p] = s end end)
        end
        return durProp[p]
    end
    local function containers()
        local im = T.first("BP_InventoryManager_C")
        return { bag = im.Inventory_Player, hand = im.Inventory_PlayerHand }
    end

    local function getDur(it)
        local o = { {}, {}, {}, {}, {} }
        bfl():GetDurability(it, T.world(), o[1], o[2], o[3], o[4], o[5])
        return o[3].Durability
    end
    local durName
    -- SetItemProperty takes the struct member name; which spelling the game matches is unknown, so try both once
    local function setDur(a, it, d)
        for _, n in ipairs(durName and { durName } or { DUR_FIELD, "Durability" }) do
            local ok = lib:SetItemProperty(durOf(a), it, FName(n), d)
            if getDur(it) == d then
                if not durName then log("PT|info SetItemProperty name=%s ret=%s works", n, tostring(ok)) end
                durName = n
                return true
            end
            log("PT|info SetItemProperty name=%s ret=%s durability still %s", n, tostring(ok), tostring(getDur(it)))
        end
        return false
    end
    -- record = { bag = {slot...}, hand = {slot...}, hot = { [i] = "bag@x,y" } }, slot = { a, n, x, y, r, d = {...} }
    local function readC(c)
        local r = {}
        for i = 0, c:GetNumSlots() - 1 do
            local s = c:GetSlot(i)
            local n = s:GetNumItems()
            if n > 0 then
                local a = s:GetCurrentArchetype()
                local e = { a = path(a), n = n, x = 0, y = 0, r = false, d = {} }
                pcall(function() e.x, e.y, e.r = s.Location.X, s.Location.Y, s.bRotated end)
                for k = 0, n - 1 do
                    local d = -1
                    if durOf(a) then d = getDur(s:GetItem(k)) end
                    e.d[#e.d + 1] = d
                end
                r[#r + 1] = e
            end
        end
        table.sort(r, function(p, q) if p.y ~= q.y then return p.y < q.y end; if p.x ~= q.x then return p.x < q.x end; return p.a < q.a end)
        return r
    end
    local function read()
        local cs, rec = containers(), { hot = {} }
        rec.bag, rec.hand = readC(cs.bag), readC(cs.hand)
        if T.ROLE == "client" then
            for i, sc in ipairs(T.first("BP_MainCharacterManager_C").HotbarShortcuts:GetShortcuts()) do
                -- a shortcut can still point at an item that left the backpack
                pcall(function()
                    local s = sc:get():GetShortcutItem():GetOuterSlot()
                    local where = s:GetContainer():GetFullName() == cs.hand:GetFullName() and "hand" or "bag"
                    local ok, x, y = pcall(function() return s.Location.X, s.Location.Y end)
                    rec.hot[i] = string.format("%s@%d,%d", where, ok and x or 0, ok and y or 0)
                end)
            end
        end
        return rec
    end

    -- one line: sec:a,n,x,y,r,d1/d2;...|sec:...|hot:i=where;...
    local function encode(rec)
        local parts = {}
        for _, sec in ipairs({ "bag", "hand" }) do
            local es = {}
            for _, e in ipairs(rec[sec]) do
                local ds = {}
                for _, d in ipairs(e.d) do ds[#ds + 1] = tostring(math.floor(d)) end
                es[#es + 1] = string.format("%s,%d,%d,%d,%d,%s", e.a, e.n, e.x, e.y, e.r and 1 or 0, table.concat(ds, "/"))
            end
            parts[#parts + 1] = sec .. ":" .. table.concat(es, ";")
        end
        local hs = {}
        for i = 1, 8 do if rec.hot[i] then hs[#hs + 1] = i .. "=" .. rec.hot[i] end end
        parts[#parts + 1] = "hot:" .. table.concat(hs, ";")
        return table.concat(parts, "|")
    end
    -- the record crosses a trust boundary (guest -> host), so it is parsed field by field, never load()ed
    local function decode(s)
        local rec = { bag = {}, hand = {}, hot = {} }
        for sec, body in s:gmatch("(%a+):([^|]*)") do
            for item in body:gmatch("[^;]+") do
                if sec == "hot" then
                    local i, where = item:match("^(%d)=(%a+@%-?%d+,%-?%d+)$")
                    if i then rec.hot[tonumber(i)] = where end
                elseif rec[sec] then
                    local a, n, x, y, r, ds = item:match("^([%w_/%.]+),(%d+),(%-?%d+),(%-?%d+),([01]),([%-%d/]*)$")
                    n = tonumber(n)
                    if a and n and n >= 1 and n <= 100 and a:sub(1, 1) == "/" then
                        local e = { a = a, n = n, x = tonumber(x), y = tonumber(y), r = r == "1", d = {} }
                        for d in ds:gmatch("%-?%d+") do e.d[#e.d + 1] = tonumber(d) end
                        rec[sec][#rec[sec] + 1] = e
                    end
                end
            end
        end
        return rec
    end
    local function count(rec) local n = 0; for _, sec in ipairs({ "bag", "hand" }) do for _, e in ipairs(rec[sec]) do n = n + e.n end end; return n end

    -- rebuild a record into containers with the game's own functions (items are new instances)
    local function writeC(c, list)
        c:RemoveAllItems()
        local placed = {}
        for _, e in ipairs(list) do
            local a = StaticFindObject(e.a)
            if not a:IsValid() then log("PT|error unknown archetype %s", e.a) else
                local slot
                for k = 1, e.n do
                    local it = lib:CreateItemInstance(T.world(), a, 0)
                    local d = e.d[k] or -1
                    if d >= 0 and durOf(a) and MUTATE ~= "nodur" then setDur(a, it, d) end
                    if not slot then
                        local ok, s = pcall(function() return c.Layout:EmplaceSlot(c, it, { X = e.x, Y = e.y }, e.r, false) end)
                        if ok and s:IsValid() then slot = s else c:AddItem(it, true); slot = it:GetOuterSlot() end
                    else
                        if not slot:AddItem(it) then c:AddItem(it, true) end
                    end
                end
                placed[string.format("@%d,%d", e.x, e.y)] = slot
            end
        end
        return placed
    end
    local function write(rec, cs)
        cs = cs or containers()
        local placed = { bag = writeC(cs.bag, rec.bag), hand = writeC(cs.hand, rec.hand) }
        if T.ROLE == "client" then
            local shortcuts = T.first("BP_MainCharacterManager_C").HotbarShortcuts:GetShortcuts()
            for i, where in pairs(rec.hot) do
                local sec, at = where:match("^(%a+)(@.+)$")
                local s = placed[sec] and placed[sec][at]
                if s and shortcuts[i] then shortcuts[i]:get():SetShortcutItem(s:GetItem(0)) end
            end
        end
    end

    if T.ROLE == "host" then
        local guest, stored, hostC, hostInv0, gcAt, gcName = nil, {}, nil, 0, 0, "none"
        local function file(id) return string.format("../../Saved/SaveGames/odsave%d.pt-%s.txt", SLOT, id) end
        local function guestPC()
            for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
                if T.inWorld(pc) and not pc:IsLocalController() and pc.Player:IsValid() then return pc end
            end
        end
        local function send()
            if MUTATE == "nosend" then return end
            local line = stored[GUEST_ID] and encode(stored[GUEST_ID]) or "bag:|hand:|hot:" -- a new guest starts empty
            guestPC():ClientMessage("PTBP|" .. GUEST_ID .. "|" .. line, FName("PT"), 0)
            log("PT|info sent backpack %d bytes", #line)
        end
        local hooked, loads, loads0 = false, 0, 0
        RegisterLoadMapPostHook(function() loads = loads + 1 end)
        local function hooks()
            if hooked then return end
            hooked = true
            RegisterHook("/Script/Engine.PlayerController:ServerExecRPC", function(self, msg)
                local s = msg:get():ToString()
                local id, line = s:match("^PTBP|(%d+)|(.*)$")
                if id then stored[id] = decode(line); log("PT|info got backpack from %s: %d items, %d bytes", id, count(stored[id]), #line) end
            end)
            -- persist every guest record with the host's own save, into a separate file next to the slot
            -- the post callback gets the return value where the first param was, so the slot comes from the pre callback
            local saving
            RegisterHook("/Script/PenDriverPro.BaseSaveGameManager:SaveGame", function(self, slot) saving = slot:get() end, function(self, ok)
                log("PT|info SaveGame slot=%s ok=%s", tostring(saving), tostring(ok:get()))
                if MUTATE == "nopersist" or saving ~= SLOT or not ok:get() then return end
                for id, rec in pairs(stored) do
                    local f = assert(io.open(file(id), "w"))
                    f:write(encode(rec), "\n"); f:close()
                    log("PT|info wrote %s", file(id))
                end
            end)
        end
        local function loadFile(id)
            local f = io.open(file(id), "r")
            if not f then return nil end
            local line = f:read("l"); f:close()
            return line and decode(line)
        end
        local function containersFor()
            local im = T.first("BP_InventoryManager_C")
            gcAt = os.time()
            return { bag = lib:CreateContainerWithLayout(im, FText("Guest backpack"), im.Inventory_Player.Layout),
                     hand = lib:CreateContainerWithLayout(im, FText("Guest hand"), im.Inventory_PlayerHand.Layout) }
        end
        local function spawnStep(id) return { check = id, timeout = 30, cond = function() guest = G.spawnGuest(T); return guest ~= nil and guest:IsValid() end } end
        return {
            T.onMap("RB_MainMenu", 90),
            { run = function()
                os.remove(file(GUEST_ID))
                log("PT|info keeplisten %s", tostring(PTNative_SetKeepListen and PTNative_SetKeepListen(true)))
            end },
            { wait = 5 },
            { run = function() T.console("open " .. T.GARAGE .. "?listen") end },
            { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
            { run = hooks },
            { check = "host_two_pcs", timeout = 180, cond = function() return T.pcs() == 2 end },
            { wait = 10 },
            spawnStep("host_spawned_guest"),
            { check = "host_saved_slot", timeout = 10, cond = function()
                local ok = T.saveMgr():SaveGame(SLOT, "", 1)
                local f = io.open(string.format("../../Saved/SaveGames/odsave%d.sav", SLOT), "rb")
                if f then f:close() end
                return ok and f ~= nil
            end },
            { run = function() hostInv0 = G.invCount(T); log("PT|info host inventory %d items", hostInv0) end },
            { check = "host_got_backpack", timeout = 120, cond = function() return stored[GUEST_ID] ~= nil and count(stored[GUEST_ID]) > 0 end },
            -- the host can hold the guest's backpack in real game containers of its own (not registered with the manager)
            -- created, filled and read in one tick: nothing roots these containers, a GC between steps frees them
            { check = "host_container_roundtrip", timeout = 5, cond = function()
                hostC = containersFor()
                gcName = T.name(hostC.bag)
                write(stored[GUEST_ID], hostC)
                local a, b = encode({ bag = readC(hostC.bag), hand = readC(hostC.hand), hot = {} }), encode({ bag = stored[GUEST_ID].bag, hand = stored[GUEST_ID].hand, hot = {} })
                if a ~= b then log("PT|info roundtrip differs:\n  got  %s\n  want %s", a, b) end
                return a == b
            end },
            { check = "host_inventory_untouched", timeout = 2, cond = function() return G.invCount(T) == hostInv0 end },
            { check = "host_file_written", timeout = 10, cond = function()
                T.saveMgr():SaveGame(SLOT, "", 1)
                local rec = loadFile(GUEST_ID)
                return rec ~= nil and encode(rec) == encode(stored[GUEST_ID])
            end },
            { check = "host_guest_left", timeout = 120, cond = function() return G.clients(T) == 0 end },
            { check = "host_guest_rejoined", timeout = 240, cond = function() return G.clients(T) == 1 end },
            { wait = 5 },
            spawnStep("host_spawned_guest_rejoin"),
            { wait = 8 },
            { run = send },
            { wait = 25 },
            { run = function()
                -- looked up by name, never through the old pointer: it may be freed
                log("PT|info host-side guest container %ds after creation: alive=%s", os.time() - gcAt, tostring(StaticFindObject(gcName:match("^%S+ (.+)$") or ""):IsValid()))
            end },
            -- reload the host's save: the record must come back from the file alone
            { run = function()
                stored = {}
                if MUTATE ~= "keepguest" then G.destroyGuests(T) end
                loads0 = loads
                log("PT|info LoadGame(%d) -> %s", SLOT, tostring(T.saveMgr():LoadGame(SLOT, 0, 1, 0)))
            end },
            { check = "host_reloaded", timeout = 240, cond = function()
                return loads > loads0 and T.map() == "RB_Garage" and T.netMode() == "listen" and T.listening()
            end },
            { check = "host_file_loaded", timeout = 5, cond = function()
                stored[GUEST_ID] = loadFile(GUEST_ID)
                return stored[GUEST_ID] ~= nil
            end },
            { check = "host_inventory_after_reload", timeout = 5, cond = function() return G.invCount(T) == hostInv0 end },
            { check = "host_guest_back_after_reload", timeout = 300, cond = function() return G.clients(T) == 1 end },
            { wait = 5 },
            spawnStep("host_spawned_guest_reload"),
            { wait = 8 },
            { run = send },
            { wait = 30 },
        }
    end

    local original, got = nil, nil
    local function hookMsg()
        RegisterHook("/Script/Engine.PlayerController:ClientMessage", function(self, s)
            local line = s:get():ToString():match("^PTBP|%d+|(.*)$")
            if line then got = line; log("PT|info received backpack %d bytes", #line) end
        end)
    end
    local function clear()
        local cs = containers()
        cs.bag:RemoveAllItems(); cs.hand:RemoveAllItems()
        for _, sc in ipairs(T.first("BP_MainCharacterManager_C").HotbarShortcuts:GetShortcuts()) do
            local ok, err = pcall(function() sc:get():SetShortcutItem(CreateInvalidObject()) end)
            if not ok then log("PT|info clear shortcut %s", tostring(err)) end
        end
        log("PT|info cleared: %s", encode(read()))
    end
    local function restoreStep(id)
        return { check = id, timeout = 60, cond = function()
            if not got then return false end
            write(decode(got))
            got = nil
            local now = encode(read())
            log("PT|info %s:\n  got  %s\n  want %s", id, now, encode(original))
            return now == encode(original)
        end }
    end
    local function possessed(id) return { check = id, timeout = 60, cond = function() return T.cls(T.myPawn()) == T.CHAR end } end
    return {
        T.onMap("RB_MainMenu", 90),
        { run = function() StaticFindObject("/Script/OnlineSubsystemUtils.Default__IpNetDriver").ResolutionConnectionTimeout = 120; hookMsg() end },
        T.join("client_connected_garage", "RB_Garage", 210, 30),
        possessed("client_possessed"),
        { wait = 5 },
        { run = function()
            local bag = containers().bag
            for _, g in ipairs(GIVE) do
                local a = StaticFindObject(g[1])
                for _ = 1, g[2] do
                    local it = lib:CreateItemInstance(T.world(), a, 0)
                    if g[3] then setDur(a, it, g[3]) end
                    bag:AddItem(it, false)
                end
            end
            -- quick slots 1 and 2: the scrapper and the cutter
            local cm = T.first("BP_MainCharacterManager_C")
            for i = 0, bag:GetNumSlots() - 1 do
                local s = bag:GetSlot(i)
                local n = s:GetCurrentArchetype():GetFName():ToString()
                if n:find("Scrapper") then cm:BindHotbarSlotIndex(s:GetItem(0), 0, false, false, {}, {}) end
                if n:find("Cutter") then cm:BindHotbarSlotIndex(s:GetItem(0), 1, false, false, {}, {}) end
            end
            original = read()
            log("PT|info original %s", encode(original))
        end },
        { check = "guest_filled_backpack", timeout = 2, cond = function()
            local hot = 0
            for _ in pairs(original.hot) do hot = hot + 1 end
            return count(original) == 10 and hot == 2
        end },
        { check = "guest_durability_read", timeout = 2, cond = function()
            local line = encode(original)
            return line:find("Scrapper,1,%-?%d+,%-?%d+,[01],123") ~= nil and line:find("Cutter_T1,1,%-?%d+,%-?%d+,[01],4") ~= nil
        end },
        { run = function() T.localPC():ServerExecRPC("PTBP|" .. GUEST_ID .. "|" .. encode(original)) end },
        { wait = 25 },
        { run = function() T.console("disconnect") end },
        T.onMap("RB_MainMenu", 60),
        { check = "guest_wiped", timeout = 5, cond = function() clear(); return count(read()) == 0 end },
        T.join("client_rejoined", "RB_Garage", 240, 30),
        possessed("client_possessed_rejoin"),
        restoreStep("guest_restored_after_rejoin"),
        -- the host reloads its save: this connection drops
        { check = "guest_dropped_by_reload", timeout = 240, cond = function() return T.map() == "RB_MainMenu" end },
        { check = "guest_wiped_again", timeout = 5, cond = function() clear(); return count(read()) == 0 end },
        T.join("client_rejoined_after_reload", "RB_Garage", 300, 30),
        possessed("client_possessed_reload"),
        restoreStep("guest_restored_after_reload"),
    }
end
