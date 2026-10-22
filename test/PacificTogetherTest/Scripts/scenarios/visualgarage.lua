-- PT2 visual, garage: what the guest's garage and car look like. Fixture garage, the guest joins by itself.
--   guest_fig_level_loaded       the Fig DLC garage dressing (a sublevel the host loads at run time, 876 actors) is loaded on the guest too
--   guest_paint_follows_host_*   the host repaints two car parts (the front-left door, the hood); the guest's parts have the same paint within 3 s
--   guest_decal_follows_host     the host swaps the front-left door's decal palette; the guest's door has it within 3 s
-- Run: tools/run-test.ps1 -Scenario visualgarage -Fixture garage -Headless [-Root .. -Port ..]   Mutation novisual: visual.lua inert on both sides.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local slow = (T.MUTATE == "novisual") and 0.15 or 1
    local function to(s) return math.max(12, math.floor(s * slow)) end
    local FIG = "Garage_Fig_Props"
    local TINT = "/Game/Gameplay/Inventory/GenericItemProperties/Components/BP_TintableComponent.BP_TintableComponent_C"
    local PAINT = "/Game/BaseArt/Palettes/Paints/BP_Palette_Paint_%s.BP_Palette_Paint_%s_C"
    local DECAL = "/Game/BaseArt/Palettes/Decals/BP_Palette_Decal_%s.BP_Palette_Decal_%s_C"
    local function load(path)
        local o = StaticFindObject(path)
        if not o:IsValid() then pcall(LoadAsset, path); o = StaticFindObject(path) end
        return o
    end
    local function tintable(slot)
        local r, r2 = {}, {}
        T.first("BP_CarManager_C"):GetItemManifestationEquippedInSlot({ TagName = FName("Car.Equip." .. slot) }, r, r2)
        local m = r.Manifestation
        if not (m and m:IsValid()) then return nil end
        local l = m:K2_GetComponentsByClass(load(TINT))
        return #l > 0 and l[1]:get() or nil
    end
    local function paintOf(slot)
        local tc = tintable(slot)
        if not tc then return "no part" end
        local a, b, c, d = {}, {}, {}, {}
        tc:GetTintableProperties(a, b, c, d)
        local function n(x) return (x and x:IsValid()) and x:GetFName():ToString() or "-" end
        return n(a.Paint) .. "|" .. n(c.DecalPalette)
    end
    local function figActors()
        local n = 0
        for _, o in ipairs(FindAllOf("Actor") or {}) do
            if o:IsValid() and o:GetFullName():find(FIG, 1, true) then n = n + 1 end
        end
        return n
    end

    local got = {}
    local function poll()
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then return end
            got[k] = d
        end
    end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local function toGuest(k, v) PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), k, v or "") end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "host_has_fig_level", timeout = 30, cond = function() return figActors() > 500 end })
        add({ run = function() T.log("PT|info host fig actors=%d door=%s hood=%s", figActors(), paintOf("Body.DoorsFL"), paintOf("Body.PanelHood")) end })
        add({ check = "guest_ready", timeout = 400 * slow, cond = function() poll(); return got["t.ready"] ~= nil end })
        add({ run = function()
            tintable("Body.DoorsFL"):SetPaint(load(PAINT:format("HotrodPurple", "HotrodPurple")), { TagName = FName("None") })
            toGuest("t.paint1", "Body.DoorsFL\tBP_Palette_Paint_HotrodPurple_C")
            T.log("PT|info host painted door %s", paintOf("Body.DoorsFL"))
        end })
        add({ wait = 8 })
        add({ run = function()
            tintable("Body.PanelHood"):SetPaint(load(PAINT:format("Pink", "Pink")), { TagName = FName("None") })
            toGuest("t.paint2", "Body.PanelHood\tBP_Palette_Paint_Pink_C")
            T.log("PT|info host painted hood %s", paintOf("Body.PanelHood"))
        end })
        add({ wait = 8 })
        add({ run = function()
            tintable("Body.DoorsFL"):SetDecal(load(DECAL:format("Flames_01", "Flames_01")), { TagName = FName("None") })
            local cur = paintOf("Body.DoorsFL")
            toGuest("t.decal", "Body.DoorsFL\t" .. cur)
        end })
        add({ check = "host_guest_finished", timeout = 400 * slow, cond = function() poll(); return got["t.done"] ~= nil end })
        add({ wait = 2 })
        return steps
    end

    -- guest
    local function follows(key, sec)
        local t0
        return function()
            poll()
            if not got[key] then return false end
            t0 = t0 or os.clock()
            local slot, want = got[key]:match("^([^\t]+)\t(.*)$")
            local have = paintOf(slot)
            T.log("PT|info %s %s want=%s have=%s after %.1fs", key, slot, want, have, os.clock() - t0)
            local ok = (key == "t.decal") and have == want or have:find(want:gsub("_C$", ""), 1, true) ~= nil
            return ok and os.clock() - t0 <= sec
        end
    end
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end },
        { check = "guest_fig_level_loaded", timeout = to(180), cond = function()
            local n = figActors()
            T.log("PT|info guest fig actors=%d", n)
            return n > 500
        end },
        { run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.ready", "1") end },
        { check = "guest_paint_follows_host_door", timeout = to(60), cond = follows("t.paint1", 3) },
        { check = "guest_paint_follows_host_hood", timeout = to(60), cond = follows("t.paint2", 3) },
        { check = "guest_decal_follows_host", timeout = to(60), cond = follows("t.decal", 3) },
        { run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.done", "1") end },
        { wait = 3 },
    }
end
