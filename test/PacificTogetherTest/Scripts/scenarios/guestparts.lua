-- PT1 playtest bug: the guest cannot repair or break car parts. Fixture `gateway` (a run map with the parked car and wrecks).
--   1. repair: the guest's repair paste heals a hurt door of the player car (the paste actor's HealthComp.HealDamage): the HOST's door
--      is healed and stays healed on both sides
--   2. scrap (player car): the guest's scrapper damages the door the way its OnTickInUse does (MSG_Damage_Physical_Piercing_Scrapper
--      dispatched through the message system, source = the guest's real scrapper): the door is removed from the host's car, the scrap
--      drops once (same world item count on both sides, the guest has no ghost items), the car state on the guest has no door
--   3. world car part: the same damage on a wreck's panel: it breaks on the host (destroyed, items dropped) and is gone on the guest
-- Headless has no camera aim, so the guest does not press the tool (exploration with PrimaryUsePress worked but is flaky): the damage
-- message is the one the tool's tick sends, and the paste's heal is its own HealDamage call.
-- Run: tools/run-test.ps1 -Scenario guestparts -Fixture gateway -Headless
-- Mutation noguestparts: the guest's damage and repair stay local (host checks FAIL).
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local log = T.log
    local COMP = "/Game/Gameplay/Inventory/GenericItemProperties/Components/"
    local SLOT_HEAL, SLOT_SCRAP = "Body.DoorsFR", "Body.DoorsFL"
    local slow = (T.MUTATE == "noguestparts") and 0.15 or 1
    local function to(s) return math.max(15, math.floor(s * slow)) end
    local function alive(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end

    local function cm() return T.first("BP_CarManager_C") end
    local function manif(name)
        local r, r2 = {}, {}
        cm():GetItemManifestationEquippedInSlot({ TagName = FName("Car.Equip." .. name) }, r, r2)
        local m = r.Manifestation
        return alive(m) and m or nil
    end
    local function hcOf(a) return a:K2_GetComponentsByClass(StaticFindObject(COMP .. "BP_HealthComponent.BP_HealthComponent_C"))[1]:get() end
    local function hpOf(name)
        local t = { {}, {}, {}, {}, {}, {}, {}, {} }
        hcOf(manif(name)):GetHealth(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8])
        return t[1].Health
    end
    local function worldItems()
        local n = 0
        for _, a in ipairs(FindAllOf("BP_WorldItem_C") or {}) do
            if alive(a) and alive(a.Instance) and not a:GetAttachParentActor():IsValid() then n = n + 1 end
        end
        return n
    end
    local function panels()
        local r = {}
        for _, a in ipairs(FindAllOf("BP_TemplatePart_Panel_C") or {}) do
            if alive(a) and not a:GetFullName():find("/Engine/Transient", 1, true) then
                local l = a:K2_GetActorLocation()
                r[#r + 1] = { a = a, x = l.X, y = l.Y, z = l.Z }
            end
        end
        table.sort(r, function(p, q) return p.x * 3 + p.y * 7 + p.z < q.x * 3 + q.y * 7 + q.z end)
        return r
    end
    local function near(list, x, y, z)
        for _, e in ipairs(list) do
            if math.abs(e.x - x) < 40 and math.abs(e.y - y) < 40 and math.abs(e.z - z) < 40 then return e end
        end
    end

    -- the tools besides the plain scrapper (checked in 2 and 3): archetype, actor class, damage message and what its tick dispatches
    local TOOLS = {
        { name = "electric_scrapper", arch = "IA_Tool_Target_ItemHarvest_Scrapper_T2", cls = "BP_Tool_Target_ItemHarvest_Scrapper_T2_C", msg = "Piercing_Scrapper", dmg = 3.0, ticks = 400 },
        { name = "hammer", arch = "IA_Tool_Target_Breaker", cls = "BP_Tool_Target_Breaker_C", msg = "Impact_Hammer", dmg = 500.0, ticks = 6, hammer = true },
        { name = "magnetic_hammer", arch = "IA_Tool_Target_Breaker_T2", cls = "BP_Tool_Target_Breaker_T2_C", msg = "Impact_HammerT2", dmg = 500.0, ticks = 6, hammer = true },
        { name = "prybar", arch = "IA_Tool_Target_Unlocker_Basic", cls = "BP_Tool_Target_Unlocker_Basic_C", msg = "Prybar", dmg = 500.0, ticks = 6 },
        { name = "cutter", arch = "IA_Tool_Target_ItemHarvest_Cutter_T1", cls = "BP_Tool_Target_ItemHarvest_Cutter_C", msg = "Explosive_Cutter", dmg = 500.0, ticks = 6 },
    }
    local got = {}
    local function drain()
        while true do
            local kind, data = PTNative_MsgPoll("t.")
            if not kind then return end
            got[kind] = data
        end
    end
    local function has(kind) drain(); return got[kind] end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local base, P = {}, nil
        for _, s in ipairs(T.loadFixture("gateway")) do add(s) end
        add({ check = "host_listen_zone", timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_zone", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 20 })
        -- 1. repair
        add({ run = function()
            hcOf(manif(SLOT_HEAL)):SetHealth(5.0)
            log("PT|info host door hp=%.1f", hpOf(SLOT_HEAL))
            PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.heal", "")
        end })
        add({ check = "host_door_repaired_by_guest", timeout = to(120), cond = function() local h = hpOf(SLOT_HEAL); log("PT|info host door hp=%.1f", h); return h >= 39 end })
        -- 2. scrap a car part
        add({ run = function()
            base.items = worldItems()
            log("PT|info host scrap baseline items=%d door=%s", base.items, tostring(manif(SLOT_SCRAP) ~= nil))
            PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.scrap", "")
        end })
        add({ check = "host_door_scrapped_by_guest", timeout = to(120), cond = function() return manif(SLOT_SCRAP) == nil end })
        add({ check = "host_scrap_dropped", timeout = to(30), cond = function() local n = worldItems(); log("PT|info host items %d -> %d", base.items, n); return n > base.items end })
        add({ wait = 8 })
        add({ run = function()
            base.after = worldItems()
            PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.count", tostring(base.after))
        end })
        add({ check = "guest_items_grew_like_host_no_ghosts", timeout = to(60), cond = function()
            local g = has("t.counted"); if not g then return false end
            local g0, g1 = g:match("^(%d+)|(%d+)$")
            log("PT|info items host %d -> %d, guest %s -> %s", base.items, base.after, g0, g1)
            return tonumber(g1) - tonumber(g0) == base.after - base.items
        end })
        -- 3. a wreck's panel
        add({ run = function()
            P = panels()[3]
            base.items = worldItems()
            log("PT|info host wreck panel %.0f %.0f %.0f items=%d", P.x, P.y, P.z, base.items)
            PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.wreck", string.format("%.0f|%.0f|%.0f", P.x, P.y, P.z))
        end })
        add({ check = "host_wreck_part_broken_by_guest", timeout = to(120), cond = function() return not alive(P.a) end })
        add({ check = "host_wreck_dropped", timeout = to(30), cond = function() return worldItems() > base.items end })
        -- 4. every other tool on its own wreck panel (the panels are picked now, before any of them breaks)
        local picked = {}
        add({ run = function()
            local list = panels()
            for i = 1, #TOOLS do picked[i] = list[3 + i * 2] end
        end })
        for i, tl in ipairs(TOOLS) do
            add({ run = function()
                local p = picked[i]
                base.items = worldItems()
                base.after = nil
                log("PT|info host %s panel %.0f %.0f %.0f", tl.name, p.x, p.y, p.z)
                PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.w_" .. tl.name, string.format("%.0f|%.0f|%.0f", p.x, p.y, p.z))
            end })
            add({ check = "host_panel_broken_by_guest_" .. tl.name, timeout = to(90), cond = function() return not alive(picked[i].a) end })
            -- a panel's drop is a loot roll: the cutter's panel dropped nothing in 2 of 5 runs (host and guest agree, checked below)
            if tl.name ~= "cutter" then add({ check = "host_dropped_by_guest_" .. tl.name, timeout = to(30), cond = function() return worldItems() > base.items end }) end
            add({ wait = 6 })
            add({ run = function() base.after = worldItems(); PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.cnt_" .. tl.name, "") end })
            add({ check = "guest_items_grew_like_host_" .. tl.name, timeout = to(60), cond = function()
                local g = has("t.cntd_" .. tl.name); if not g then return false end
                local g0, g1 = g:match("^(%d+)|(%d+)$")
                log("PT|info %s items host %d -> %d, guest %s -> %s", tl.name, base.items, base.after, g0, g1)
                return tonumber(g1) - tonumber(g0) == base.after - base.items
            end })
        end
        -- 5. the blowtorch repairs the hurt door
        add({ run = function()
            hcOf(manif(SLOT_HEAL)):SetHealth(5.0)
            PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.torch", "")
        end })
        add({ check = "host_door_repaired_by_guest_blowtorch", timeout = to(90), cond = function() return hpOf(SLOT_HEAL) >= 14 end })
        add({ check = "host_guest_finished", timeout = to(120), cond = function() return has("t.done") ~= nil end })
        return steps
    end

    -- guest ---------------------------------------------------------------------------------------------------------------
    local function im() return T.first("BP_InventoryManager_C") end
    local function arch(path)
        local a = StaticFindObject(path)
        if not (a and a:IsValid()) then pcall(LoadAsset, path); a = StaticFindObject(path) end
        return a
    end
    local SCRAPPER = "/Game/Gameplay/Inventory/Items/Tools/Scrapper/IA_Tool_Target_ItemHarvest_Scrapper.IA_Tool_Target_ItemHarvest_Scrapper"
    local function hold(path)
        local m = im()
        m.Inventory_PlayerHand:GetSlot(0):RemoveAllItems({})
        m:GiveItemToPlayer(arch(path))
        local want = path:match("([^/%.]+)$")
        for i = 0, m.Inventory_Player:GetNumSlots() - 1 do
            local s = m.Inventory_Player:GetSlot(i)
            if s:GetNumItems() > 0 and s:GetCurrentArchetype():GetFName():ToString() == want then s:TransferStackIntoContainer(m.Inventory_PlayerHand, {}); return end
        end
        error("tool not in the backpack: " .. want)
    end
    local function tool() for _, x in ipairs(FindAllOf("BP_Tool_Target_ItemHarvest_Scrapper_C") or {}) do if alive(x) then return x end end end
    -- what the scrapper's OnTickInUse does for a target: one damage message through the message system (3 per 50 ms)
    local function scrape(target, ticks)
        local t = tool()
        local ms = StaticFindObject("/Script/PenDriverPro.Default__BlueprintGameUtilities"):GetMessageSystem(t)
        local cls = StaticFindObject("/Game/Systems/Messages/MSG_Damage_Physical_Piercing_Scrapper.MSG_Damage_Physical_Piercing_Scrapper_C")
        local n, loop = 0, nil
        loop = LoopInGameThreadWithDelay(50, function()
            n = n + 1
            if not alive(target) or not alive(t) or n > ticks then CancelDelayedAction(loop); return end
            local msg = StaticConstructObject(cls, t)
            msg.Damage, msg.IsDamageOverTime, msg.ToolDispatched = 3.0, true, true
            ms:DispatchMessage(msg, target)
        end)
    end

    local function holdByName(name)
        local m, a = im(), nil
        for _, x in ipairs(FindAllOf("ItemArchetype") or {}) do if alive(x) and x:GetFName():ToString() == name then a = x end end
        m.Inventory_PlayerHand:GetSlot(0):RemoveAllItems({})
        m:GiveItemToPlayer(a)
        for i = 0, m.Inventory_Player:GetNumSlots() - 1 do
            local s = m.Inventory_Player:GetSlot(i)
            if s:GetNumItems() > 0 and s:GetCurrentArchetype():GetFName():ToString() == name then s:TransferStackIntoContainer(m.Inventory_PlayerHand, {}); return end
        end
        error("tool not in the backpack: " .. name)
    end
    local function toolOf(cls) for _, x in ipairs(FindAllOf(cls) or {}) do if alive(x) then return x end end end
    -- the damage message the tool's tick dispatches (scrapper: 3 per 50 ms until the part is gone; the others: one hit, a few times)
    local function send(t, tl, target)
        local ms = StaticFindObject("/Script/PenDriverPro.Default__BlueprintGameUtilities"):GetMessageSystem(t)
        local cls = StaticFindObject("/Game/Systems/Messages/MSG_Damage_Physical_" .. tl.msg .. ".MSG_Damage_Physical_" .. tl.msg .. "_C")
        local n, loop = 0, nil
        loop = LoopInGameThreadWithDelay(50, function()
            n = n + 1
            if not alive(target) or not alive(t) or n > tl.ticks then CancelDelayedAction(loop); return end
            local msg = StaticConstructObject(cls, t)
            msg.Damage, msg.ToolDispatched = tl.dmg, true
            if tl.msg == "Piercing_Scrapper" then msg.IsDamageOverTime = true end
            if tl.hammer then
                local s, ty = {}, {}
                t.BP_ItemHarvesterComponent:GetHarvesterSettings(s, ty)
                msg.HarvestSettings = s
                msg.HarvesterType = ty.HarvesterType
            end
            ms:DispatchMessage(msg, target)
        end)
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    add({ check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "Rural_Forest_Radio_Scylla_02" and T.cls(T.myPawn()) == T.CHAR end })
    add({ check = "guest_has_car_parts", timeout = 120, cond = function() return manif(SLOT_HEAL) ~= nil and manif(SLOT_SCRAP) ~= nil end })
    -- 1. repair
    add({ check = "guest_told_heal", timeout = 240, cond = function() return has("t.heal") ~= nil end })
    add({ check = "guest_door_is_hurt", timeout = 30, cond = function() return hpOf(SLOT_HEAL) <= 6 end })
    add({ run = function()
        local m = manif(SLOT_HEAL)
        local PASTE = "/Game/Gameplay/Inventory/Items/Tools/PatchKit/BP_ToolSpawn_PatchKitPaste.BP_ToolSpawn_PatchKitPaste_C"
        local cls = StaticFindObject(PASTE)
        if not cls:IsValid() then pcall(LoadAsset, PASTE); cls = StaticFindObject(PASTE) end
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local l = m:K2_GetActorLocation()
        local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X, Y = l.Y, Z = l.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local p = gs:BeginDeferredActorSpawnFromClass(T.world(), cls, xf, 1, nil)
        p.ActorToHeal = m
        p = gs:FinishSpawningActor(p, xf)
        p.HealthComp = hcOf(m)
        hcOf(m):HealDamage(35.0, false, {}, {}, {}) -- the paste's tick
    end })
    add({ check = "guest_door_stays_repaired", timeout = to(60), cond = L.holds(8, function() return hpOf(SLOT_HEAL) >= 39 end) })
    -- 2. scrap the other door
    add({ check = "guest_told_scrap", timeout = 120, cond = function() return has("t.scrap") ~= nil end })
    local g0
    add({ run = function() g0 = worldItems() end })
    add({ run = function() hold(SCRAPPER) end })
    add({ check = "guest_holds_scrapper", timeout = 20, cond = function() return tool() ~= nil end })
    add({ wait = 3 })
    add({ run = function() scrape(manif(SLOT_SCRAP), 400) end })
    add({ check = "guest_door_gone_after_host_scrap", timeout = to(120), cond = function() return manif(SLOT_SCRAP) == nil end })
    add({ check = "guest_told_count", timeout = to(120), cond = function() return has("t.count") ~= nil end })
    add({ run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.counted", g0 .. "|" .. worldItems()) end })
    -- 3. a wreck's panel
    add({ check = "guest_told_wreck", timeout = to(120), cond = function() return has("t.wreck") ~= nil end })
    local E
    add({ check = "guest_has_wreck_copy", timeout = 60, cond = function()
        local x, y, z = got["t.wreck"]:match("^([^|]*)|([^|]*)|([^|]*)")
        E = near(panels(), tonumber(x), tonumber(y), tonumber(z))
        return E ~= nil
    end })
    add({ run = function() scrape(E.a, 400) end })
    add({ check = "guest_wreck_copy_gone", timeout = to(120), cond = function() return not alive(E.a) end })
    -- 4. the other tools: the message each one's tick sends, from the real held tool, at a wreck panel
    for _, tl in ipairs(TOOLS) do
        local key, tool_, copy = "t.w_" .. tl.name, nil, nil
        add({ check = "guest_told_" .. tl.name, timeout = to(120), cond = function() return has(key) ~= nil end })
        add({ check = "guest_copy_for_" .. tl.name, timeout = 60, cond = function()
            local x, y, z = got[key]:match("^([^|]*)|([^|]*)|([^|]*)")
            copy = near(panels(), tonumber(x), tonumber(y), tonumber(z))
            return copy ~= nil
        end })
        local g0
        add({ run = function() g0 = worldItems(); holdByName(tl.arch) end })
        add({ check = "guest_holds_" .. tl.name, timeout = 20, cond = function() tool_ = toolOf(tl.cls); return tool_ ~= nil end })
        add({ wait = 2 })
        add({ run = function() send(tool_, tl, copy.a) end })
        add({ check = "guest_copy_gone_" .. tl.name, timeout = to(90), cond = function() return not alive(copy.a) end })
        add({ check = "guest_told_cnt_" .. tl.name, timeout = to(60), cond = function() return has("t.cnt_" .. tl.name) ~= nil end })
        add({ run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.cntd_" .. tl.name, g0 .. "|" .. worldItems()) end })
    end
    -- 5. the blowtorch
    add({ check = "guest_told_torch", timeout = to(120), cond = function() return has("t.torch") ~= nil end })
    add({ check = "guest_door_hurt_again", timeout = 30, cond = function() return hpOf(SLOT_HEAL) <= 6 end })
    add({ run = function() holdByName("IA_Tool_Target_Healer_Basic") end })
    add({ check = "guest_holds_blowtorch", timeout = 20, cond = function() return toolOf("BP_Tool_Target_Healer_Basic_C") ~= nil end })
    add({ run = function()
        local t, m = toolOf("BP_Tool_Target_Healer_Basic_C"), manif(SLOT_HEAL)
        t.TargetedActor = m
        t.BP_HealerComponent:DoHeal(hcOf(m), 0.0, {}, {}) -- what the tool's tick does
    end })
    add({ check = "guest_door_stays_repaired_by_blowtorch", timeout = to(60), cond = L.holds(8, function() return hpOf(SLOT_HEAL) >= 14 end) })
    add({ run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.done", "1") end })
    add({ wait = 3 })
    return steps
end
