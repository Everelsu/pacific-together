-- C5, C6, W1: the guest works on the car like the host: part remove/install and trunk, host is the authority. Fixture `gateway`
--   (a real run, the car parked; the trunk holds items). The guest calls the game's own CarManager "Swap Equipment" (action 1 = take a
--   part off into hands/pack, action 0 = install from hands) on the front-left door slot, then moves a stack out of the trunk and back
--   with the container's own TransferStackIntoContainer.
--   Checks: the HOST's car lost the door, then has it again (same archetype); the guest carries exactly one door after the removal,
--   its own car slot stays empty (the host's state message must not put the door back: that was the dupe), the host carries none;
--   a stack taken from the trunk is gone on the host and carried by the guest, and back after the put.
--   Fuel and battery by the guest: scenario guestact (proven there, not repeated).
-- Run: tools/run-test.ps1 -Scenario guestswap -Fixture gateway -Headless
-- Mutation noswap: guestswap.lua does nothing, the guest's change is overwritten by the host's state (door dupe): checks FAIL.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local log = T.log
    local SLOT = "Car.Equip.Body.DoorsFL"
    local slow = (T.MUTATE == "noswap") and 0.2 or 1
    local function to(s) return math.max(15, math.floor(s * slow)) end

    local function im() return T.first("BP_InventoryManager_C") end
    local function partSlot(name)
        for _, a in ipairs(FindAllOf("BP_CarPart_Interactive_C") or {}) do
            if a:IsValid() then
                local sl, nm = {}, {}
                a:GetSlot(sl, nm)
                if nm.TagName and nm.TagName:ToString() == name then return a, sl.ItemSlot end
            end
        end
    end
    local function slotArch()
        local _, s = partSlot(SLOT)
        if not s or s:GetNumItems() == 0 then return s and "empty" or "noslot" end
        return s:GetItem(0).Archetype:GetFName():ToString()
    end
    -- items of the door archetype in hand and pack
    local function carriedDoors()
        local n = 0
        for _, c in ipairs({ im().Inventory_Player, im().Inventory_PlayerHand }) do
            local items = {}
            c:GetAllItems(items)
            for _, it in ipairs(items) do if it:get().Archetype:GetFName():ToString():find("Door", 1, true) then n = n + 1 end end
        end
        return n
    end
    local function carried() return im().Inventory_Player:GetNumItems() + im().Inventory_PlayerHand:GetNumItems() end
    local function trunk() return im().Inventory_Trunk end
    local function trunkCount() return trunk():GetNumItems() end

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
        local base = {}
        local function say(k) PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), k, "") end
        for _, s in ipairs(T.loadFixture("gateway")) do add(s) end
        add({ check = "host_listen_zone", timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_zone", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 15 })
        add({ run = function()
            base.arch, base.trunk, base.carried = slotArch(), trunkCount(), carried()
            log("PT|info host baseline door=%s trunk=%d carried=%d", base.arch, base.trunk, base.carried)
            say("t.go")
        end })
        add({ check = "host_door_removed_by_guest", timeout = to(120), cond = function() local a = slotArch(); log("PT|info host door=%s", a); return a == "empty" end })
        add({ check = "host_carries_no_door", timeout = 10, cond = function() return carriedDoors() == 0 end })
        add({ run = function() say("t.removed") end })
        add({ check = "host_door_installed_by_guest", timeout = to(120), cond = function() local a = slotArch(); log("PT|info host door=%s", a); return a == base.arch end })
        add({ check = "host_door_stays_installed", timeout = to(60), cond = L.holds(8, function() return slotArch() == base.arch end) })
        add({ run = function() say("t.installed") end })
        add({ check = "host_trunk_lost_guest_take", timeout = to(90), cond = function() local n = trunkCount(); log("PT|info host trunk=%d (was %d)", n, base.trunk); return n < base.trunk end })
        add({ run = function() say("t.took") end })
        add({ check = "host_trunk_back_after_guest_put", timeout = to(90), cond = function() local n = trunkCount(); log("PT|info host trunk=%d", n); return n == base.trunk end })
        add({ check = "host_guest_finished", timeout = to(120), cond = function() return has("t.done") ~= nil end })
        return steps
    end

    -- guest -------------------------------------------------------------------------------------------------------------
    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    local base, moved = {}, 0
    -- what the game's hold-to-swap ends in
    local function swap(action)
        local cm, a = T.first("BP_CarManager_C"), partSlot(SLOT)
        local r = {}
        cm["Swap Equipment"](cm, action, a, r)
        log("PT|info guest swap action=%d success=%s", action, tostring(r.Success))
    end
    -- a part that landed in the pack goes to the hand like the player would carry it
    local function toHand()
        local m = im()
        if m.Inventory_PlayerHand:GetNumItems() > 0 then return end
        for i = 0, m.Inventory_Player:GetNumSlots() - 1 do
            local s = m.Inventory_Player:GetSlot(i)
            if s:GetNumItems() > 0 and s:GetCurrentArchetype():GetFName():ToString():find("Door", 1, true) then s:TransferStackIntoContainer(m.Inventory_PlayerHand, {}); return end
        end
    end
    add({ check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "Rural_Forest_Radio_Scylla_02" and T.cls(T.myPawn()) == T.CHAR end })
    add({ check = "guest_has_car_part_slot", timeout = 90, cond = function() return slotArch() ~= "noslot" and slotArch() ~= "empty" end })
    add({ check = "guest_told_to_go", timeout = 240, cond = function() return has("t.go") ~= nil end })
    add({ run = function() base.arch, base.doors, base.carried, base.trunk = slotArch(), carriedDoors(), carried(), trunkCount() end })
    -- remove: the part ends as ONE item, here
    add({ run = function() swap(1) end })
    add({ check = "guest_carries_one_door", timeout = 20, cond = function() return carriedDoors() == base.doors + 1 end })
    add({ check = "guest_slot_empty_and_stays_so", timeout = to(60), cond = L.holds(8, function() return slotArch() == "empty" and carriedDoors() == base.doors + 1 end) })
    add({ check = "guest_told_removed", timeout = to(120), cond = function() return has("t.removed") ~= nil end })
    -- install it back from the hand
    add({ run = function() toHand(); swap(0) end })
    add({ check = "guest_slot_has_door_again", timeout = 20, cond = function() return slotArch() == base.arch and carriedDoors() == base.doors end })
    add({ check = "guest_told_installed", timeout = to(120), cond = function() return has("t.installed") ~= nil end })
    add({ check = "guest_door_stays_installed", timeout = to(30), cond = L.holds(6, function() return slotArch() == base.arch and carriedDoors() == base.doors end) })
    -- C6: the trunk through the container's own stack transfer
    add({ run = function()
        local m = im()
        local c0 = carried()
        for i = 0, trunk():GetNumSlots() - 1 do
            local s = trunk():GetSlot(i)
            if s:GetNumItems() > 0 then moved = s:GetNumItems(); s:TransferStackIntoContainer(m.Inventory_PlayerHand, {}); break end
        end
        log("PT|info guest took %d from trunk, carried %d -> %d", moved, c0, carried())
    end })
    add({ check = "guest_took_stack", timeout = 10, cond = function() return moved > 0 and carried() > base.carried end })
    add({ check = "guest_told_took", timeout = to(120), cond = function() return has("t.took") ~= nil end })
    add({ run = function()
        im().Inventory_PlayerHand:GetSlot(0):TransferStackIntoContainer(trunk(), {})
    end })
    add({ check = "guest_trunk_back", timeout = 20, cond = function() return trunkCount() == base.trunk end })
    add({ wait = 8 })
    add({ run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.done", "1") end })
    add({ wait = 3 })
    return steps
end
