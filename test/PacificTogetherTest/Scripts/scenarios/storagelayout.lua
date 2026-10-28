-- Where items lie in a storage (loot.lua + ids.layout). Owner's screenshot 2026-10-28: the same locker held the same items on both
-- sides, laid out differently (the state was a bag of items; each side placed them where they fitted, and a move inside a container
-- was no change at all). Checks: after the join the guest's locker matches the host's slot by slot; a stack the host moves to an
-- empty slot moves there on the guest; one the guest moves moves there on the host.
-- Run: tools/run-test.ps1 -Scenario storagelayout -Fixture garage -Headless      Mutation nolayout: the bag as before (checks FAIL).
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local NAME = "Stations.Install.Inventory.Starter"
    local got = {}
    local function g(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind]
    end
    local function box()
        local m = T.first("BP_InventoryManager_C")
        local c
        pcall(function() m.Inventories_Garage:ForEach(function(k, v) if k:get().TagName:ToString() == NAME then c = v:get() end end) end)
        return c
    end
    -- "x.y.rotated=archetype*count,..." per stack, sorted: the cell in the locker's tile grid (state like fuel is not compared here)
    local function layout()
        local c = box()
        if not c then return nil end
        local r = {}
        for i = 0, c:GetNumSlots() - 1 do
            local s = c:GetSlot(i)
            if s:GetNumItems() > 0 then
                r[#r + 1] = string.format("%d.%d.%d=%s*%d", s.Location.X, s.Location.Y, s.bRotated and 1 or 0, s:GetItem(0).Archetype:GetFName():ToString(), s:GetNumItems())
            end
        end
        table.sort(r)
        return table.concat(r, ",")
    end
    -- swap the first slot with the last one holding something else (the locker on this save is full: no empty slot to move to);
    -- the same items, other places: no count changes. Returns "a<>b"
    local function move()
        local c = box()
        local function at(i) local s = c:GetSlot(i); return s:GetNumItems() > 0 and (s:GetItem(0).Archetype:GetFName():ToString() .. "*" .. s:GetNumItems()) or "-" end
        local b
        for i = 1, c:GetNumSlots() - 1 do if at(i) ~= at(0) then b = i end end
        local ok = c:GetSlot(0):SwapSlotContents(c:GetSlot(b))
        T.log("PT|info swapped slots 0 <> %d ok=%s", b, tostring(ok))
        return "0<>" .. b
    end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local function same(tag)
            local mine, theirs = layout(), g("t.layout")
            if mine ~= theirs then T.log("PT|info %s host %s | guest %s", tag, tostring(mine):sub(1, 200), tostring(theirs):sub(1, 200)) end
            return mine ~= nil and mine ~= "" and mine == theirs
        end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "host_locker_has_items", timeout = 30, cond = function() local l = layout(); return l ~= nil and l ~= "" end })
        add({ check = "guest_locker_laid_out_like_host", timeout = 150, cond = function() return same("join") end })
        add({ run = function() move() end })
        add({ check = "host_move_shows_on_guest", timeout = 15, cond = function() return same("host move") end })
        add({ run = function() got["t.layout"] = nil; PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.move", "1") end })
        add({ check = "guest_moved", timeout = 30, cond = function() return g("t.moved") ~= nil end })
        add({ check = "guest_move_shows_on_host", timeout = 15, cond = function() return same("guest move") end })
        add({ run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.done", "1") end })
        add({ wait = 3 })
        return steps
    end

    local moved = false
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end },
        { check = "guest_reports", timeout = 900, cond = function()
            if g("t.move") and not moved then moved = true; PTNative_MsgToHost(T.localPC():GetAddress(), "t.moved", move()) end
            local l = layout()
            if l then PTNative_MsgToHost(T.localPC():GetAddress(), "t.layout", l) end
            return g("t.done") ~= nil
        end },
    }
end
