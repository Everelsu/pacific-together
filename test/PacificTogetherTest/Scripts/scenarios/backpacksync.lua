-- P5/D7/D6: the guest's backpack in a co-op session (zone). The guest fills its backpack; the host keeps it next to its save slot
-- (odsave<slot>.pt-<guest>.txt); the guest leaves, its backpack is wiped, it rejoins and gets everything back (items, durability,
-- quick slots); then the guest dies: its backpack is empty, the host has a bag with the items at the death spot, the guest sees
-- that bag too, the guest takes from it and the host's bag loses it; the stored record is empty.
-- Run: tools/run-test.ps1 -Scenario backpacksync -Fixture zone -Headless
-- Mutation nobackpack: backpack.lua is inert: no file, nothing restored, no bag.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local G = require("scenarios.guestchar")
    local mapName = "Rural_Forest_Radio_Scylla_02"
    local ITEMS = "/Game/Gameplay/Inventory/Items/"
    local GIVE = { -- archetype, count, durability (nil = keep)
        { ITEMS .. "Resources/Basic/RawSteel/IA_Resource_Raw_Scrap_Steel.IA_Resource_Raw_Scrap_Steel", 7 },
        { ITEMS .. "Tools/Scrapper/IA_Tool_Target_ItemHarvest_Scrapper.IA_Tool_Target_ItemHarvest_Scrapper", 1, 123 },
        { ITEMS .. "Tools/FuelCan/FuelCan5G/IA_Tool_Target_FuelCan_5Gal.IA_Tool_Target_FuelCan_5Gal", 1 },
        { ITEMS .. "Tools/Cutter/IA_Tool_Target_ItemHarvest_Cutter_T1.IA_Tool_Target_ItemHarvest_Cutter_T1", 1, 4 },
    }
    local function alive(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
    local function im() return T.first("BP_InventoryManager_C") end
    local function lib() return StaticFindObject("/Script/PenDriverInventory.Default__InventoryBlueprintLibrary") end
    local function carried() return G.invCount(T) end
    local function bags() -- every lootable bag in the world with its item count
        local r = {}
        for _, a in ipairs(FindAllOf("BP_Lootable_Base_C") or {}) do
            if alive(a) and a:GetClass():GetFName():ToString():find("Crate_Large", 1, true) then r[#r + 1] = { a = a, n = a.InventoryContainer:GetNumItems() } end
        end
        return r
    end
    local seen = 0
    local function bagWith(n)
        local list, t = bags(), {}
        for _, b in ipairs(list) do t[#t + 1] = b.n; if b.n == n then return b end end
        if os.time() - seen >= 10 then seen = os.time(); T.log("PT|info bags: %s", table.concat(t, ",")) end
    end
    local function health()
        local h = T.first("BP_ResourceManager_C").PlayerHealth
        return h, h.Maximum
    end
    local function durs() -- name fragment -> durability of the first such item
        local r = {}
        local o = { {}, {}, {}, {}, {} }
        local bfl = FindObject("BFL_ItemPropertyUtilityFns_C", "Default__BFL_ItemPropertyUtilityFns_C")
        local c = im().Inventory_Player
        for i = 0, c:GetNumSlots() - 1 do
            local s = c:GetSlot(i)
            if s:GetNumItems() > 0 then
                local n = s:GetCurrentArchetype():GetFName():ToString()
                for _, k in ipairs({ "Scrapper", "Cutter" }) do
                    if n:find(k, 1, true) then bfl:GetDurability(s:GetItem(0), T.world(), o[1], o[2], o[3], o[4], o[5]); r[k] = o[3].Durability end
                end
            end
        end
        return r
    end
    local function hotCount()
        local n = 0
        for _, sc in ipairs(T.first("BP_MainCharacterManager_C").HotbarShortcuts:GetShortcuts()) do
            local ok, it = pcall(function() return sc:get():GetShortcutItem() end)
            if ok and alive(it) then n = n + 1 end
        end
        return n
    end

    -- messages between the two test processes ("t." kind, latest data per kind)
    local got = {}
    local function has(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind] ~= nil
    end
    local function sendGuest(kind) PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), kind, "") end
    local function sendHost(kind) PTNative_MsgToHost(T.localPC():GetAddress(), kind, "") end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local name, filePath, own0, deathBag
        local function line()
            local f = io.open(filePath, "r")
            if not f then return nil end
            local l = f:read("l"); f:close()
            return l
        end
        for _, s in ipairs(T.loadFixture("zone")) do add(s) end
        add({ check = "host_listen", timeout = 120, cond = function() return T.netMode() == "listen" and T.listening() and T.map() == mapName end })
        add({ check = "host_guest_in", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ run = function()
            own0 = carried()
            name = L.guestName():gsub("[^%w_%-]", "_")
            filePath = string.format("../../Saved/SaveGames/odsave%d.pt-%s.txt", T.saveMgr():GetCurrentSlot(), name)
            os.remove(filePath)
            T.log("PT|info guest id %s file %s", name, filePath)
        end })
        add({ check = "host_file_has_guest_backpack", timeout = 120, cond = function()
            local l = line()
            return l ~= nil and l:find("Scrap_Steel,7,", 1, true) ~= nil and l:find("Scrapper,1,%-?%d+,%-?%d+,[01],123") ~= nil
                and l:find("Cutter_T1,1,%-?%d+,%-?%d+,[01],4") ~= nil and l:find("hot:%d=") ~= nil
        end })
        add({ check = "host_own_backpack_untouched", timeout = 2, cond = function() return carried() == own0 end })
        add({ check = "host_guest_left", timeout = 120, cond = function() return G.clients(T) == 0 end })
        add({ check = "host_guest_back", timeout = 240, cond = function() return G.clients(T) == 1 and L.guestChar() ~= nil end })
        add({ check = "host_restored_guest_ack", timeout = 120, cond = function() return has("t.restored") end })
        -- the guest dies: its items are a bag of the host's at the death spot, the record is empty
        add({ check = "host_death_bag_with_items", timeout = 90, cond = function() deathBag = bagWith(10); return deathBag ~= nil end })
        add({ check = "host_file_empty_after_death", timeout = 30, cond = function()
            local l = line()
            return l == "bag:|hand:|hot:"
        end })
        add({ run = function() sendGuest("t.take") end })
        add({ check = "host_bag_lost_guest_take", timeout = 60, cond = function() return alive(deathBag.a) and deathBag.a.InventoryContainer:GetNumItems() < 10 end })
        add({ wait = 3 })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    local function clientIn(id) return { check = id, timeout = 400, cond = function() return T.netMode() == "client" and T.map() == mapName and T.cls(T.myPawn()) == T.CHAR end } end
    add(clientIn("client_in_zone"))
    add({ wait = 12 }) -- the handshake: the host answers "new guest" and the guest keeps its own backpack
    add({ run = function()
        local bag = im().Inventory_Player
        for _, g in ipairs(GIVE) do
            local a = StaticFindObject(g[1])
            for _ = 1, g[2] do
                local it = lib():CreateItemInstance(T.world(), a, 0)
                if g[3] then
                    a.Properties:ForEach(function(_, e)
                        local p = e:get()
                        if p:GetFName():ToString() == "IP_Durability" then lib():SetItemProperty(p, it, FName("Durability"), g[3]) end
                    end)
                end
                bag:AddItem(it, true)
            end
        end
        local cm = T.first("BP_MainCharacterManager_C")
        for i = 0, bag:GetNumSlots() - 1 do
            local s = bag:GetSlot(i)
            local n = s:GetCurrentArchetype():GetFName():ToString()
            if n:find("Scrapper") then cm:BindHotbarSlotIndex(s:GetItem(0), 0, false, false, {}, {}) end
            if n:find("Cutter") then cm:BindHotbarSlotIndex(s:GetItem(0), 1, false, false, {}, {}) end
        end
    end })
    add({ check = "guest_filled", timeout = 5, cond = function() return carried() == 10 and hotCount() == 2 end })
    add({ check = "guest_durability_set", timeout = 5, cond = function() local d = durs(); return d.Scrapper == 123 and d.Cutter == 4 end })
    add({ wait = 15 }) -- the host stores it (host_file_has_guest_backpack)
    local mark
    add({ run = function() mark = L.mark(); T.console("disconnect") end })
    -- the shipping mod's rejoin goes straight back without the menu: wipe once the new map is loading
    add({ check = "guest_wiped", timeout = 90, cond = function()
        if not L.reloadedNoMenu(mark) then return false end
        local m = im()
        m.Inventory_Player:RemoveAllItems(); m.Inventory_PlayerHand:RemoveAllItems()
        for _, sc in ipairs(T.first("BP_MainCharacterManager_C").HotbarShortcuts:GetShortcuts()) do pcall(function() sc:get():SetShortcutItem(CreateInvalidObject()) end) end
        return carried() == 0
    end })
    add(clientIn("client_rejoined")) -- the shipping mod joins by itself
    add({ check = "guest_restored_backpack", timeout = 90, cond = function()
        local d = durs()
        return carried() == 10 and d.Scrapper == 123 and d.Cutter == 4 and hotCount() == 2
    end })
    add({ run = function() sendHost("t.restored") end })
    add({ wait = 10 })
    add({ run = function()
        local h, m = health()
        h:Adjust(T.first("BP_ResourceManager_C"), -m) -- the game's own sink for every damage message
    end })
    add({ check = "guest_backpack_emptied", timeout = 30, cond = function() return carried() == 0 and hotCount() == 0 end })
    add({ check = "guest_sees_death_bag", timeout = 90, cond = function() return bagWith(10) ~= nil end })
    add({ check = "guest_cmd_take", timeout = 120, cond = function() return has("t.take") end })
    add({ run = function()
        local b = bagWith(10)
        local c = b.a.InventoryContainer
        for i = 0, c:GetNumSlots() - 1 do
            local s = c:GetSlot(i)
            if s:IsValid() and s:GetNumItems() > 0 then s:TransferStackIntoContainer(im().Inventory_PlayerHand, {}); return end
        end
    end })
    add({ check = "guest_took_from_bag", timeout = 10, cond = function() return carried() > 0 end })
    add({ wait = 10 })
    return steps
end
