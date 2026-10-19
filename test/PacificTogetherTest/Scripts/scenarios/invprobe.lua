-- X4/X12 probe, one instance: what the inventory, hotbar and highlight APIs look like from Lua (information only)
return function(T)
    local log = T.log
    local function try(tag, fn)
        local ok, err = pcall(fn)
        if not ok then log("PT|info probe %s err %s", tag, tostring(err)) end
    end
    local function keys(t)
        local r = {}
        for k, v in pairs(t) do r[#r + 1] = tostring(k) .. "=" .. type(v) end
        return table.concat(r, ",")
    end
    local im, cm, inv, lib, bfl
    local function un(v) local ok, r = pcall(function() return v:get() end); if ok then return r end; return v end
    local arch = {}
    local function setup()
        im, cm = T.first("BP_InventoryManager_C"), T.first("BP_MainCharacterManager_C")
        inv = im.Inventory_Player
        lib = StaticFindObject("/Script/PenDriverInventory.Default__InventoryBlueprintLibrary")
        log("PT|info probe layout before=%s", T.name(inv.Layout))
        try("backpack", function() cm:CheckGiveStartBackpack() end)
        inv = im.Inventory_Player
        log("PT|info probe layout after=%s player=%s", T.name(inv.Layout), T.name(inv))
        try("arch", function()
            for _, a in ipairs(T.first("InventorySystem"):GetAllArchetypes()) do a = un(a)
                local props = {}
                a.Properties:ForEach(function(_, p) props[#props + 1] = p:get():GetFName():ToString() end)
                arch[a:GetFName():ToString()] = a
                log("PT|arch %s stack=%d grid=%dx%d props=%s", a:GetFullName(), a.StackSize, a.TileWidth, a.TileHeight, table.concat(props, "|"))
            end
        end)
    end
    local function slots(c, tag)
        log("PT|info probe %s slots=%d items=%d", tag, c:GetNumSlots(), c:GetNumItems())
        for i = 0, c:GetNumSlots() - 1 do
            try("slot" .. i, function()
                local s = c:GetSlot(i)
                local it = s:GetItem(0)
                local d = { {}, {}, {}, {}, {} }
                bfl:GetDurability(it, T.world(), d[1], d[2], d[3], d[4], d[5])
                log("PT|info probe %s slot=%d cls=%s arch=%s n=%d cap=%d loc=%d,%d rot=%s dur={%s|%s|%s}", tag, i, T.cls(s), T.name(s:GetCurrentArchetype()),
                    s:GetNumItems(), s:GetCapacity(), s.Location.X, s.Location.Y, tostring(s.bRotated), keys(d[3]), tostring(d[3].Durability), tostring(d[4].MaxDurability))
            end)
        end
    end
    local function give()
        bfl = FindObject("BFL_ItemPropertyUtilityFns_C", "Default__BFL_ItemPropertyUtilityFns_C")
        log("PT|info probe bfl=%s", T.name(bfl))
        -- one stackable resource and one tool with durability, by name pattern
        local picks = {}
        for n, a in pairs(arch) do
            if #picks < 2 and n:find("Scrap") then picks[#picks + 1] = a end
        end
        for n, a in pairs(arch) do
            local hasDur = false
            a.Properties:ForEach(function(_, p) if p:get():GetFName():ToString() == "IP_Durability" then hasDur = true end end)
            if hasDur and #picks < 4 then picks[#picks + 1] = a end
        end
        for _, a in ipairs(picks) do
            try("give " .. a:GetFName():ToString(), function()
                local it = lib:CreateItemInstance(T.world(), a, 0)
                log("PT|info probe created %s for %s add=%s dump=%s", T.name(it), a:GetFName():ToString(), tostring(inv:AddItem(it, false)), it:GetDataBlockDump():ToString():sub(1, 600))
            end)
        end
        try("out", function()
            local t = {}
            inv:GetAllItems(t)
            log("PT|info probe GetAllItems keys=%s n=%s", keys(t), t.Items and tostring(#t.Items) or "nil")
        end)
        slots(inv, "player")
        try("hotbar", function()
            for i, s in ipairs(cm.HotbarShortcuts:GetShortcuts()) do s = un(s); log("PT|info probe hotbar %d %s item=%s", i, T.name(s), T.name(s:GetShortcutItem())) end
        end)
        try("guest", function()
            local c = lib:CreateContainerWithLayout(im, FText("Guest"), inv.Layout)
            local it = lib:CreateItemInstance(T.world(), arch[next(arch)], 0)
            log("PT|info probe guest=%s add=%s", T.name(c), tostring(c:AddItem(it, false)))
            slots(c, "guest")
        end)
        try("save", function()
            local sm = T.saveMgr()
            log("PT|info probe slot=%s SaveGame(7) -> %s", tostring(sm:GetCurrentSlot()), tostring(sm:SaveGame(7, "", 1)))
        end)
    end
    return {
        T.onMap("RB_MainMenu", 90),
        { wait = 5 },
        { run = function() T.console("open " .. T.GARAGE) end },
        T.onMap("RB_Garage", 120),
        { wait = 15 },
        { run = setup },
        { wait = 3 },
        { run = give },
        { wait = 5 },
        { run = function() log("PT|info probe slot after save=%s", tostring(T.saveMgr():GetCurrentSlot())); slots(inv, "later") end },
    }
end
