-- PT2 garage stations (PLAN G2): the guest uses the stations with its own game's functions, the HOST performs each action once.
--   shredder   the guest puts a spare wheel in its shredder and runs it (OnTransactionEnd, what closing the container does): the host's shredder
--              takes the wheel, the products appear in the host's world once and the guest sees the same products
--   research   the guest buys a research node that costs items (graph state PurchaseNode, what the invent button calls): the host has it purchased,
--              its resources fell by exactly the cost, the guest shows it purchased and sees the same resources
--   upgrade    the guest builds a garage station at its spawner (InstallSpecificUpgrade): the host has it installed once, both sides show it
--   fabricate  the guest crafts a tool (Craft Recipe Asset): it owns the tool, the host's garage lost exactly the inputs once, both sides agree
-- Run: tools/run-test.ps1 -Scenario stations -Fixture garage -Headless      Mutation nostations: stations.lua inert.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local function alive(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
    local function real(o) return alive(o) and not o:GetFullName():find("/Engine/Transient", 1, true) end
    local function im() return T.first("BP_InventoryManager_C") end
    local function graph() return FindFirstOf("BaseGenericGraphState") end
    local function arch(o) return o.Archetype:GetFName():ToString() end

    -- owned items (backpack, hand, garage, car) by archetype name
    local function owned()
        local o, c = {}, {}
        im():GetOwnedItems(true, true, true, o)
        for _, e in ipairs(o) do local k = arch(e:get()); c[k] = (c[k] or 0) + 1 end
        return c
    end
    local function resources(c) -- one comparable string of every resource count
        local r = {}
        for k, v in pairs(c) do if k:find("^IA_Resource") then r[#r + 1] = k .. "=" .. v end end
        table.sort(r)
        return table.concat(r, " ")
    end
    local function worldRes() -- resource pickups lying in this side's world
        local t, n = {}, 0
        for _, w in ipairs(FindAllOf("BP_WorldItem_C") or {}) do
            if real(w) then
                local ok, a = pcall(function() return w.Instance.Archetype:GetFName():ToString() end)
                if ok and a:find("^IA_Resource") then n = n + 1; t[#t + 1] = a end
            end
        end
        table.sort(t)
        return n, table.concat(t, ",")
    end
    local function shredder() return T.first("BP_Garage_PartShredder_C") end
    local function shredderItems()
        local a = {}
        shredder().BP_InventoryContainerComponent:GetAllItems(a)
        return #a
    end

    -- research: the first node that costs items and can be bought now
    local function costNode()
        local g = graph()
        for _, x in ipairs(FindAllOf("GenericGraphRecipeNode") or {}) do
            if real(x) or x:GetFullName():find("RecipeResearchGraph", 1, true) then
                if g:IsNodeUnlockable(x) and not g:HasNodeBeenPurchased(x) then
                    local r = {}
                    if g:CanUnlockNode(x, r) and #r.ComponentsToBeConsumed > 0 then
                        local cost = {}
                        for i = 1, #r.ComponentsToBeConsumed do
                            local e = r.ComponentsToBeConsumed[i]:get()
                            local k = arch(e)
                            cost[k] = (cost[k] or 0) + e.Quantity
                        end
                        return x, cost
                    end
                end
            end
        end
    end
    local function nodeByName(n)
        for _, x in ipairs(FindAllOf("GenericGraphRecipeNode") or {}) do
            if x:GetFName():ToString() == n then return x end
        end
    end
    local function costStr(c) local r = {} for k, v in pairs(c) do r[#r + 1] = k .. "=" .. v end table.sort(r) return table.concat(r, " ") end

    -- upgrades
    local UP = {
        fax = { "BP_GarageStation_Fax", "/Game/Gameplay/CarGarage/Stations/FaxMachine/UP_Garage_FaxMachine_Install.UP_Garage_FaxMachine_Install_C" },
        destabilizer = { "BP_GarageStation_Destabilizer", "/Game/Gameplay/CarGarage/Stations/Destabilizer/UP_Garage_Destabilizer_Install.UP_Garage_Destabilizer_Install_C" },
    }
    local function spawner(name)
        for _, s in ipairs(FindAllOf("BP_GarageInstallation_Spawner_C") or {}) do
            if real(s) and s:GetFName():ToString() == name then return s end
        end
    end
    local function upCount(key) -- how many times the station's upgrade effect sits in its slot
        local s, sm = spawner(UP[key][1]), T.first("BP_StatusEffectManager_C")
        if not (s and sm) then return -1 end
        local a, t = {}, {}
        s:GetUpgradeArchetype(a)
        s:GetInstallTag(t)
        local item = im():FindOrCreateGarageUpgradeSlot(a.Archetype, t.Station):GetItem(0)
        if not (item and item:IsValid()) then return 0 end
        local n, want = 0, UP[key][2]:match("[^.]+$")
        local list = sm:GetStatusEffects(item)
        for i = 1, #list do if list[i]:get():GetClass():GetFName():ToString() == want then n = n + 1 end end
        return n
    end

    local RECIPE = "/Game/Gameplay/Inventory/Items/Tools/FixStatusEffect/FixElectronic/CR_Tool_Target_FixElectronics.CR_Tool_Target_FixElectronics"
    local function tools() return owned()["IA_Tool_Target_FixElectronics"] or 0 end

    local got = {}
    local function has(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind] ~= nil
    end
    local function g(kind) has(kind); return got[kind] end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local function toGuest(k, v) PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), k, v or "") end
        local st = {}
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 20 }) -- the garage storage and progression reach the guest
        add({ check = "host_has_shredder_and_bench", timeout = 30, cond = function()
            return shredder() ~= nil and T.first("BP_Garage_InventingBench_C") ~= nil and T.first("BP_Garage_CraftingTable_01_New_C") ~= nil
        end })

        -- shredder
        add({ run = function()
            st.worldBefore = worldRes()
            T.log("PT|info host world resources before shred: %d", st.worldBefore)
            toGuest("t.go.shred")
        end })
        add({ check = "host_shredder_took_the_wheel_and_ran", timeout = 90, cond = function()
            if g("t.shredded") == nil then return false end
            local n, list = worldRes()
            if n > st.worldBefore then st.products = n; st.list = list end
            return st.products ~= nil
        end })
        add({ check = "host_products_stay_once_for_25s_and_shredder_empty", timeout = 60, cond = L.holds(25, function()
            local n, list = worldRes()
            if n ~= st.products then T.log("PT|info host products changed %d -> %d (%s)", st.products, n, list) end
            return n == st.products and shredderItems() == 0
        end) })
        add({ run = function() T.log("PT|info host products: %s", st.list); toGuest("t.shreddone") end })
        add({ check = "guest_sees_same_products", timeout = 60, cond = function()
            local n = tonumber(g("t.gres") or "-1")
            return n == st.products
        end })

        -- research
        add({ run = function()
            local node, cost = costNode()
            st.node, st.cost, st.before = node, cost, owned()
            T.log("PT|info host research node %s cost %s", node and T.name(node) or "none", cost and costStr(cost) or "")
            if node then toGuest("t.go.buy", node:GetFName():ToString()) end
        end })
        add({ check = "host_research_node_found", timeout = 1, cond = function() return st.node ~= nil end })
        add({ check = "host_has_node_purchased", timeout = 60, cond = function() return graph():HasNodeBeenPurchased(st.node) end })
        add({ check = "host_resources_fell_by_exactly_the_cost_once", timeout = 60, cond = L.holds(15, function()
            local now = owned()
            for k, v in pairs(st.cost) do
                if (now[k] or 0) ~= (st.before[k] or 0) - v then T.log("PT|info host %s %d -> %d (cost %d)", k, st.before[k] or 0, now[k] or 0, v) return false end
            end
            return true
        end) })
        add({ run = function() st.after = resources(owned()); toGuest("t.buydone") end })
        add({ check = "guest_shows_node_purchased", timeout = 60, cond = function() return g("t.bought") == "1" end })
        add({ check = "guest_resources_equal_host", timeout = 60, cond = function()
            local r = g("t.gresources")
            if r ~= st.after then T.log("PT|info guest resources differ from host") end
            return r == st.after
        end })

        -- garage upgrade
        add({ run = function()
            for _, k in ipairs({ "fax", "destabilizer" }) do
                if not st.up and upCount(k) == 0 then st.up = k end
            end
            T.log("PT|info host upgrade to build: %s", tostring(st.up))
            if st.up then toGuest("t.go.up", st.up) end
        end })
        add({ check = "host_upgrade_candidate_exists", timeout = 1, cond = function() return st.up ~= nil end })
        add({ check = "host_has_upgrade_installed_once", timeout = 60, cond = L.holds(10, function() return upCount(st.up) == 1 end) })
        add({ check = "guest_shows_upgrade_once", timeout = 60, cond = function() return g("t.upcount") == "1" end })

        -- fabrication
        add({ run = function()
            st.fb = owned()
            T.log("PT|info host before craft: %s", resources(st.fb))
            toGuest("t.go.craft")
        end })
        add({ check = "guest_crafted_the_tool", timeout = 60, cond = function() return g("t.crafted") == "1" end })
        add({ check = "host_garage_lost_exactly_the_inputs_once", timeout = 60, cond = L.holds(15, function()
            local now = owned()
            local want = { IA_Resource_Raw_Battery = 1, IA_Resource_Raw_Copper = 2, IA_Resource_Raw_Electronics = 1 }
            for k, v in pairs(want) do
                if (now[k] or 0) ~= (st.fb[k] or 0) - v then T.log("PT|info host %s %d -> %d (inputs %d)", k, st.fb[k] or 0, now[k] or 0, v) return false end
            end
            return true
        end) })
        add({ run = function() st.after2 = resources(owned()); toGuest("t.craftdone") end })
        add({ check = "guest_resources_equal_host_after_craft", timeout = 60, cond = function()
            local r = g("t.gresources2")
            if r ~= st.after2 then T.log("PT|info guest resources after craft differ from host") end
            return r == st.after2
        end })
        add({ run = function() toGuest("t.done") end })
        add({ wait = 3 })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    local function say(k, v) PTNative_MsgToHost(T.localPC():GetAddress(), k, v or "") end
    local st = {}
    add({ check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end })

    -- shredder: a spare wheel into the guest's own shredder, then the game's end-of-transaction event
    add({ check = "guest_go_shred", timeout = 300, cond = function() return has("t.go.shred") end })
    add({ run = function()
        local lib = StaticFindObject("/Script/PenDriverInventory.Default__InventoryBlueprintLibrary")
        local a = StaticFindObject("/Game/Gameplay/Inventory/Items/Car/Wheels/Wheel_Spare_01/IA_Attach_Wheel_Spare.IA_Attach_Wheel_Spare")
        local s = shredder()
        local c, r = s.BP_InventoryContainerComponent, {}
        c:AddItem(lib:CreateItemInstance(T.myPawn():GetWorld(), a, 0), r)
        T.log("PT|info guest wheel added to its shredder: %s", tostring(r.Added))
        s:OnTransactionEnd(c)
        say("t.shredded")
    end })
    add({ check = "guest_go_shreddone", timeout = 180, cond = function() return has("t.shreddone") end })
    add({ check = "guest_report_world_products", timeout = 120, cond = L.holds(10, function()
        local n, list = worldRes()
        say("t.gres", tostring(n))
        T.log("PT|info guest world resources %d %s", n, list)
        return has("t.go.buy")
    end) })

    -- research
    add({ check = "guest_go_buy", timeout = 120, cond = function() return has("t.go.buy") end })
    add({ run = function()
        local node = nodeByName(g("t.go.buy"))
        st.node = node
        im():SetActiveTier(3, true, true)
        local ok = graph():PurchaseNode(node)
        T.log("PT|info guest PurchaseNode(%s) -> %s", g("t.go.buy"), tostring(ok))
    end })
    add({ check = "guest_go_buydone", timeout = 180, cond = function() return has("t.buydone") end })
    add({ check = "guest_reports_purchase", timeout = 90, cond = function()
        say("t.bought", graph():HasNodeBeenPurchased(st.node) and "1" or "0")
        say("t.gresources", resources(owned()))
        return has("t.go.up")
    end })

    -- upgrade
    add({ check = "guest_go_up", timeout = 120, cond = function() return has("t.go.up") end })
    add({ run = function()
        local key = g("t.go.up")
        st.up = key
        spawner(UP[key][1]):InstallSpecificUpgrade(StaticFindObject(UP[key][2]), false)
        T.log("PT|info guest installed %s", key)
    end })
    add({ check = "guest_reports_upgrade", timeout = 120, cond = function()
        say("t.upcount", tostring(upCount(st.up)))
        return has("t.go.craft")
    end })

    -- fabrication
    add({ check = "guest_go_craft", timeout = 120, cond = function() return has("t.go.craft") end })
    add({ run = function()
        local m = im()
        m:SetActiveTier(3, true, true)
        local o = {}
        m["Craft Recipe Asset"](m, StaticFindObject(RECIPE), true, true, o)
        T.log("PT|info guest craft success=%s", tostring(o.Success))
        st.crafted = tools() == 1
        say("t.crafted", st.crafted and "1" or "0")
    end })
    add({ check = "guest_reports_resources_after_craft", timeout = 180, cond = function()
        say("t.gresources2", resources(owned()))
        return has("t.done")
    end })
    return steps
end
