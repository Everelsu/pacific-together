-- PT2 car upgrades, one proving scenario. Garage fixture, host and guest in the garage (the guest does not ride: the effects are on
-- the car's parts).
--   capacity: the host installs a large battery and a bigger fuel tank (the game's own slots); the host's aggregate capacity grows
--             and the guest's follows (cm aggregate, the dashboard battery bar's target, the car's tank part).
--   abilities: the host installs Boost, Jump, Bracer shield, Bubble shield, Juke and Chrono Dilator parts, then fires each ability
--             through the car's ability container (AddAbility, SetAbilityPressed: the attachment's own activate path). The guest's
--             copy of the part shows the effect within 1 s: boost flame and particles on, shields up, jump rack animation, juke
--             thrust (a particle/audio component or the part's own state, see each check).
--   chrono:   the Chrono Dilator fires on the host, the global time dilation stays 1 on both sides.
--   quirks:   the host runs quirk behaviours through the game's own QB_*:StartBehavior (lights, interior light, wipers, a door);
--             the guest's car shows each; a quirk status effect added to the guest's own car part is gone within 10 s and
--             none of the guest's quirk behaviours starts by itself.
-- Run: tools/run-test.ps1 -Scenario upgrades -Fixture garage -Headless
-- Mutation noupgrades: upgrades.lua of the shipping mod does nothing (guest ability, interior light and quirk checks FAIL).
-- Not testable headless (-nosound): that a sound is audible; the check is the part's audio component and its own state.
return function(T)
    local L = require("scenarios.carlib")(T)
    local S = require("scenarios.sessionlib")(T)
    local log, ROLE = T.log, T.ROLE

    local function cm() return T.first("BP_CarManager_C") end
    local function im() return T.first("BP_InventoryManager_C") end
    local function sm() return T.first("BP_StatusEffectManager_C") end
    local function near(a, b, tol) return a ~= nil and b ~= nil and math.abs(a - b) <= tol end
    local function container() return FindAllOf("AbilityContainer")[1] end
    local function carSlot(name)
        local box = {}
        im():GetCarEquippedContainer(box)
        local r
        box.Inventory_CarEquipped.Slots:ForEach(function(_, e)
            local s = e:get()
            if s.SlotName:ToString() == "Car.Equip." .. name then r = s end
        end)
        return r
    end
    local function arch(short)
        for _, a in ipairs(FindAllOf("ItemArchetype") or {}) do if a:GetFName():ToString() == short then return a end end
    end
    local function put(slot, a)
        local s = carSlot(slot)
        s:RemoveAllItems({})
        s:SetItem(StaticFindObject("/Script/PenDriverInventory.Default__InventoryBlueprintLibrary"):CreateItemInstance(T.first("World"), arch(a), 0), {})
        return s.Items:GetArrayNum() == 1
    end
    local function caps() local c = cm(); return c.AggregateBatteryMax, c.AggregateFuelMax, c.AggregateBatteryCurrent end
    local function part(class)
        local car = L.car()
        for _, o in ipairs(FindAllOf(class) or {}) do
            if o:IsValid() and car and o:GetAttachParentActor():IsValid() and o:GetAttachParentActor():GetFullName() == car:GetFullName() then return o end
        end
    end
    local function charge()
        for _, b in ipairs(FindAllOf("BP_BatteryComponent_C") or {}) do
            if b:IsValid() and not b:GetClass():GetFName():ToString():find("ChargePort", 1, true) then pcall(function() b["Set Battery"](b, 100) end) end
        end
        pcall(function() cm():UpdateAggregateBattery() end)
    end
    local function dilation() return T.first("World") and StaticFindObject("/Script/Engine.Default__GameplayStatics"):GetGlobalTimeDilation(T.first("World")) or 1 end
    local function doors() local m = 0; for d = 0, 5 do local o = {}; cm():GetDoorState(d, o); if o.Open then m = m | (1 << d) end end; return m end
    local function qb(name)
        local P = "/Game/Gameplay/StatusEffects/Quirks/QuirkBehaviors/"
        local f = P .. name .. "." .. name .. "_C"
        local c = StaticFindObject(f)
        if not c:IsValid() then c = LoadAsset(f) end
        local b = StaticConstructObject(c, sm())
        b:StartBehavior()
        return b
    end

    local inbox = {}
    local function drain()
        while true do
            local kind, data = PTNative_MsgPoll("t.")
            if not kind then return end
            inbox[kind] = { data = data, at = L.now(), n = (inbox[kind] and inbox[kind].n or 0) + 1 }
        end
    end
    local function got(kind) drain(); return inbox[kind] end

    -- the abilities under test: key, part class, part slot, archetype, ability class, state seen on a copy of the part
    local ABIL = {
        { key = "boost", class = "BP_Attach_Util_Ability_Boost_Base_C", slot = "Attachments.FrontGrill", arch = "IA_Attach_Util_Ability_Boost", ab = "AB_ZoomAbility",
          state = function(p) return p.BP_AbilityProviderComponent.AbilityIsActive and p.outterFlame:IsVisible() and p["Ak Component"]:IsValid() end },
        { key = "jump", class = "BP_Attach_Util_Ability_Jump_C", slot = "Attachments.BackSeatRight", arch = "IA_Attach_Util_Ability_Jump", ab = "AB_CarJump",
          state = function(p) return p.jumping:IsPlaying() or p.NS_Sparks:IsActive() end },
        { key = "bracer", class = "BP_Attach_Util_Ability_Shield_Bracer_C", slot = "Attachments.RearTow", arch = "IA_Attach_Util_Ability_Shield_Bracer", ab = "AB_BubbleShield_Bracer",
          state = function(p) return p.ShieldActive == true end },
        { key = "bubble", class = "BP_Attach_Util_Ability_BubbleShield_C", slot = "Attachments.RoofFront", arch = "IA_Attach_Util_Ability_BubbleShield", ab = "AB_BubbleShield",
          state = function(p) return p.BubbleShieldActive == true end },
        { key = "juke", class = "BP_Attach_Util_Ability_Juke_C", slot = "Attachments.LeftRearWindowBack", arch = "IA_Attach_Util_Ability_Juke", ab = "AB_CarJuke",
          state = function(p) return p.BP_AbilityProviderComponent.AbilityIsActive end },
    }
    local CHRONO = { class = "BP_Attach_Util_Ability_TimeWarper_C", slot = "Attachments.RoofBack", arch = "IA_Attach_Util_Ability_TimeWarper", ab = "AP_TimeWarper" }

    if ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local function guestPC() return S.remotePCs()[1] end
        local function send(kind, data) PTNative_MsgToGuest(guestPC():GetAddress(), kind, data or "") end
        local base = {}
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return S.guestChar() ~= nil end })
        add({ wait = 8 })

        -- capacity ------------------------------------------------------------------------------------------------------
        add({ run = function() base.b, base.f = caps(); log("PT|info host base battery max %.1f fuel max %.1f", base.b, base.f) end })
        add({ check = "host_installed_battery_and_tank", timeout = 10, cond = function()
            local a = put("Attachments.BackSeatRight", "IA_Attach_Battery_Large")
            local b = put("Attachments.BackSeatLeft", "IA_Attach_Fuel_Basic2")
            return a and b
        end })
        add({ check = "host_capacity_grew", timeout = 20, cond = function()
            local b, f = caps()
            log("PT|info host battery max %.1f fuel max %.1f", b, f)
            return b > base.b + 1 and f > base.f + 1
        end })
        add({ run = function() local b, f, c = caps(); send("t.cap", string.format("%.1f,%.1f,%.1f,%.1f,%.1f", base.b, base.f, b, f, c)) end })
        add({ check = "host_guest_capacity_done", timeout = 90, cond = function() return got("t.capok") ~= nil end })

        -- the ability parts ---------------------------------------------------------------------------------------------
        add({ check = "host_installed_ability_parts", timeout = 10, cond = function()
            local ok = true
            for _, a in ipairs(ABIL) do ok = put(a.slot, a.arch) and ok end
            ok = put(CHRONO.slot, CHRONO.arch) and ok
            return ok
        end })
        add({ check = "host_ability_parts_exist", timeout = 30, cond = function()
            for _, a in ipairs(ABIL) do if not part(a.class) then return false end end
            return part(CHRONO.class) ~= nil
        end })
        add({ run = function() send("t.parts") end })
        add({ check = "host_guest_has_parts", timeout = 90, cond = function() return got("t.partsok") ~= nil end })

        local function fire(a)
            charge()
            local c = container()
            local av = c:GetAvailableAbilities()
            local data
            for i = 1, #av do
                local d = av[i]:get()
                if d.AbilityClass:GetFullName():find(a.ab .. ".", 1, true) then data = d end
            end
            assert(data, "no ability data for " .. a.ab)
            c:ClearAllAbilities()
            c:AddAbility(0, data)
            send("t.go", a.key)
            c:SetAbilityPressed(0, false)
            c:SetAbilityPressed(0, true)
        end
        local function release() container():SetAbilityPressed(0, false) end
        for _, a in ipairs(ABIL) do
            local seen = false
            add({ run = function()
                seen = false
                fire(a)
                local n = 0
                local h
                h = LoopInGameThreadWithDelay(100, function()
                    n = n + 1
                    local p = part(a.class)
                    if p and pcall(function() if a.state(p) then seen = true end end) and seen then CancelDelayedAction(h) end
                    if n > 40 then CancelDelayedAction(h) end
                end)
            end })
            add({ check = "host_" .. a.key .. "_fired", timeout = 6, cond = function() return seen end })
            add({ wait = 2 })
            add({ run = function() release(); send("t.end", a.key) end })
            add({ check = "host_guest_" .. a.key .. "_done", timeout = 60, cond = function() return got("t.done." .. a.key) ~= nil end })
        end

        -- chrono dilator: fires, time stays at 1
        local dmin, dmax, chronoSeen = 1, 1, false
        add({ run = function()
            fire({ key = "chrono", ab = CHRONO.ab })
            local n = 0
            local h
            h = LoopInGameThreadWithDelay(100, function()
                n = n + 1
                local d = dilation()
                dmin, dmax = math.min(dmin, d), math.max(dmax, d)
                local p = part(CHRONO.class)
                if p and p.BP_AbilityProviderComponent and p.BP_AbilityProviderComponent.AbilityIsActive then chronoSeen = true end
                if n > 50 then CancelDelayedAction(h) end
            end)
        end })
        add({ wait = 6 })
        add({ run = function() release(); log("PT|info host chrono active=%s dilation min=%.3f max=%.3f", tostring(chronoSeen), dmin, dmax) end })
        add({ check = "host_chrono_dilation_stays_1", timeout = 1, cond = function() return dmin > 0.99 and dmax < 1.01 end })
        add({ run = function() send("t.chrono") end })
        add({ check = "host_guest_chrono_done", timeout = 60, cond = function() return got("t.done.chrono") ~= nil end })

        -- quirks -------------------------------------------------------------------------------------------------------
        add({ run = function() charge(); cm():SetCarLightsOn(false); send("t.q.lights.pre") end })
        add({ wait = 3 })
        add({ run = function() qb("QB_ToggleLights"); send("t.q.lights") end })
        add({ check = "host_quirk_lights_on", timeout = 10, cond = function() return cm().CarLightsOn == true end })
        add({ check = "host_guest_quirk_lights_done", timeout = 60, cond = function() return got("t.done.q.lights") ~= nil end })
        add({ run = function() qb("QB_ToggleInteriorLights"); send("t.q.int") end })
        add({ check = "host_quirk_interior_on", timeout = 10, cond = function() return cm().CarTopLightOnOff == true end })
        add({ check = "host_guest_quirk_interior_done", timeout = 60, cond = function() return got("t.done.q.int") ~= nil end })
        add({ run = function() qb("QB_ToggleWipers"); send("t.q.wip") end })
        add({ check = "host_quirk_wipers_on", timeout = 10, cond = function() return cm().WiperBladesOnOff == true end })
        add({ check = "host_guest_quirk_wipers_done", timeout = 60, cond = function() return got("t.done.q.wip") ~= nil end })
        add({ run = function() qb("QB_OpenDriverDoor"); send("t.q.door") end })
        add({ check = "host_quirk_door_open", timeout = 10, cond = function() return doors() ~= 0 end })
        add({ run = function() send("t.q.doormask", tostring(doors())) end })
        add({ check = "host_guest_quirk_door_done", timeout = 60, cond = function() return got("t.done.q.door") ~= nil end })
        add({ check = "host_guest_quirks_local_done", timeout = 120, cond = function() return got("t.done.q.local") ~= nil end })
        add({ wait = 3 })
        return steps
    end

    -- guest ----------------------------------------------------------------------------------------------------------------
    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    local function toHost(kind, data) PTNative_MsgToHost(T.localPC():GetAddress(), kind, data or "") end
    add({ check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end })
    add({ wait = 8 })
    add({ check = "guest_one_car", timeout = 60, cond = function() local cs = L.cars(); return #cs == 1 and #L.localCopies() == 0 end })

    -- capacity
    local cap
    add({ check = "guest_got_capacity_msg", timeout = 240, cond = function()
        local m = got("t.cap")
        if not m then return false end
        cap = {}
        for x in m.data:gmatch("[^,]+") do cap[#cap + 1] = tonumber(x) end
        return #cap == 5
    end })
    add({ check = "guest_capacity_follows_host", timeout = 40, cond = function()
        local b, f, c = caps()
        log("PT|info guest battery %.1f/%.1f fuel max %.1f (host %.1f, %.1f, now %.1f)", c, b, f, cap[3], cap[4], cap[5])
        return near(b, cap[3], 0.5) and near(f, cap[4], 0.5) and b > cap[1] + 1 and f > cap[2] + 1
    end })
    add({ check = "guest_dashboard_battery_bar_matches", timeout = 30, cond = function()
        for _, lb in ipairs(FindAllOf("BP_CarPart_Internal_LimBox_C") or {}) do
            if lb:IsValid() and lb:GetAttachParentActor():IsValid() and L.car() and lb:GetAttachParentActor():GetFullName() == L.car():GetFullName() then
                log("PT|info guest LimBox TargetMaxBattery %.1f", lb.TargetMaxBattery)
                return near(lb.TargetMaxBattery, cap[3], 0.5)
            end
        end
        return false
    end })
    add({ run = function() toHost("t.capok") end })

    -- ability parts
    add({ check = "guest_told_parts", timeout = 240, cond = function() return got("t.parts") ~= nil end })
    add({ check = "guest_has_ability_parts", timeout = 60, cond = function()
        for _, a in ipairs(ABIL) do if not part(a.class) then return false end end
        return part(CHRONO.class) ~= nil
    end })
    add({ run = function() toHost("t.partsok") end })

    -- the guest samples each ability's state 50 ms; the host announces (t.go) right before it presses
    local seen, goAt, firstSeen = {}, {}, {}
    local sampler
    local function startSampler()
        if sampler then return end
        sampler = LoopInGameThreadWithDelay(50, function()
            drain()
            local g = inbox["t.go"]
            if g then goAt[g.data] = goAt[g.data] or g.at end
            for _, a in ipairs(ABIL) do
                if goAt[a.key] and not seen[a.key] then
                    local p = part(a.class)
                    local ok, v = pcall(function() return p and a.state(p) end)
                    if ok and v then seen[a.key], firstSeen[a.key] = true, L.now() end
                end
            end
        end)
    end
    -- latch for the jump rack, whose animation is a fraction of a second
    local jumpHook = false
    local function hookJump()
        if jumpHook then return end
        jumpHook = pcall(RegisterHook, "/Game/Gameplay/Inventory/Items/Car/Abilities/Abilities_Jump/BP_Attach_Util_Ability_Jump.BP_Attach_Util_Ability_Jump_C:onJumpStart", function()
            if goAt.jump and not seen.jump then seen.jump, firstSeen.jump = true, L.now() end
        end, function() end)
    end
    add({ run = function() startSampler(); hookJump() end })
    for _, a in ipairs(ABIL) do
        add({ check = "guest_sees_" .. a.key, timeout = 120, cond = function()
            if not goAt[a.key] then return false end
            if not seen[a.key] then return false end
            local dt = firstSeen[a.key] - goAt[a.key]
            log("PT|info guest %s effect %.2f s after the host's press", a.key, dt)
            return dt <= 1.0
        end })
        add({ check = "guest_" .. a.key .. "_told_end", timeout = 60, cond = function() local m = got("t.end"); return m ~= nil and m.data == a.key end })
        add({ run = function() toHost("t.done." .. a.key) end })
    end
    add({ check = "guest_dilation_stays_1", timeout = 90, cond = function() return got("t.chrono") ~= nil end })
    add({ run = function()
        local d = dilation()
        log("PT|info guest dilation %.3f", d)
        toHost("t.done.chrono")
        T.guestDilation = d
    end })
    add({ check = "guest_dilation_is_1", timeout = 1, cond = function() return near(T.guestDilation, 1, 0.01) end })

    -- quirks
    add({ check = "guest_lights_off_before", timeout = 60, cond = function() return got("t.q.lights.pre") ~= nil end })
    add({ check = "guest_sees_quirk_lights", timeout = 60, cond = function() return got("t.q.lights") ~= nil and cm().CarLightsOn == true end })
    add({ run = function() toHost("t.done.q.lights") end })
    add({ check = "guest_sees_quirk_interior_light", timeout = 60, cond = function() return got("t.q.int") ~= nil and cm().CarTopLightOnOff == true end })
    add({ run = function() toHost("t.done.q.int") end })
    add({ check = "guest_sees_quirk_wipers", timeout = 60, cond = function() return got("t.q.wip") ~= nil and cm().WiperBladesOnOff == true end })
    add({ run = function() toHost("t.done.q.wip") end })
    add({ check = "guest_sees_quirk_door", timeout = 60, cond = function()
        local m = got("t.q.doormask")
        return m ~= nil and doors() == tonumber(m.data) and doors() ~= 0
    end })
    add({ run = function() toHost("t.done.q.door") end })
    -- the guest's own quirks: a quirk effect put on its car part is removed, and no quirk behaviour starts on its own
    local localStarts, effect = 0, nil
    add({ run = function()
        for _, n in ipairs({ "QB_ToggleLights", "QB_Horn_Honk", "QB_ToggleWipers", "QB_OpenDriverDoor", "QB_ToggleRadio", "QB_KillEngine", "QB_ToggleInteriorLights" }) do
            local P = "/Game/Gameplay/StatusEffects/Quirks/QuirkBehaviors/"
            pcall(RegisterHook, P .. n .. "." .. n .. "_C:StartBehavior", function() localStarts = localStarts + 1 end, function() end)
        end
        local item
        local box = {}
        im():GetCarEquippedContainer(box)
        box.Inventory_CarEquipped.Slots:ForEach(function(_, e)
            local s = e:get()
            if s.SlotName:ToString() == "Car.Equip.Essentials.Engine" then s.Items:ForEach(function(_, x) item = x:get() end) end
        end)
        local f = "/Game/Gameplay/StatusEffects/Quirks/SE_Quirk_MixAndMatch.SE_Quirk_MixAndMatch_C"
        local c = StaticFindObject(f)
        if not c:IsValid() then c = LoadAsset(f) end
        sm():AddItemStatusEffect(item, c)
        T.engineItem = item
        local n = 0
        local list = sm():GetStatusEffects(item)
        for i = 1, #list do if list[i]:get():GetClass():GetFName():ToString() == "SE_Quirk_MixAndMatch_C" then n = n + 1 end end
        log("PT|info guest quirk effects on engine after add: %d", n)
        effect = n
    end })
    add({ check = "guest_local_quirk_effect_added", timeout = 1, cond = function() return effect ~= nil and effect >= 1 end })
    add({ check = "guest_local_quirk_effect_removed", timeout = 12, cond = function()
        local list = sm():GetStatusEffects(T.engineItem)
        for i = 1, #list do if list[i]:get():GetClass():GetFName():ToString() == "SE_Quirk_MixAndMatch_C" then return false end end
        return true
    end })
    add({ wait = 5 })
    add({ check = "guest_no_local_quirk_started", timeout = 1, cond = function() log("PT|info guest local quirk starts %d", localStarts); return localStarts == 0 end })
    add({ run = function() toHost("t.done.q.local") end })
    add({ wait = 3 })
    return steps
end
