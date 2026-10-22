-- P1 hands: each player sees what the other holds and does with it, both directions (host sees guest, then guest sees host).
--   Fixture `garage`. Per direction the acting side (A) does one thing, the observing side (B) checks its view of A's character:
--   1 item     A holds a flashlight: B has a mesh actor attached to A's character with the same mesh as A's hand, within 2 s
--   2 light    A presses the flashlight's use input (the game's own toggle): B has a light at A's head, and the use swing ran
--   3 off      A presses again: the light is gone
--   4 switch   A holds a patch kit instead: the mesh follows (a different one), no light
--   5 use      A presses the patch kit's use input: B sees the use swing (the mannequin has no tool montage, the mirror swings)
--   6 carry    A holds a large item (fuel can): the mirror sits on the chest (spine_03), not the hand
--   7 empty    A empties the hand: the mirror is gone
-- Run: tools/run-test.ps1 -Scenario hands -Fixture garage -Headless      Mutation nohands: hands.lua inert, B's checks FAIL.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local log, ROLE = T.log, T.ROLE
    local TOOLS = "/Game/Gameplay/Inventory/Items/Tools/"
    local FLASH = TOOLS .. "Flashlight/Potato/IA_Tool_Toggle_Flashlight.IA_Tool_Toggle_Flashlight"
    local PATCH = TOOLS .. "PatchKit/IA_Tool_Target_Consumable_PatchKit.IA_Tool_Target_Consumable_PatchKit"
    local CAN = TOOLS .. "FuelCan/FuelCan5G/IA_Tool_Target_FuelCan_5Gal.IA_Tool_Target_FuelCan_5Gal"
    local slow = (T.MUTATE == "nohands") and 0.15 or 1
    local function to(s) return math.max(6, math.floor(s * slow)) end
    local function alive(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end

    local got = {}
    local function has(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind]
    end
    local function say(kind, data)
        if ROLE == "host" then PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), kind, data or "")
        else PTNative_MsgToHost(T.localPC():GetAddress(), kind, data or "") end
    end

    -- A's side -----------------------------------------------------------------------------------------------------------
    local function arch(path)
        local a = StaticFindObject(path)
        if not (a and a:IsValid()) then pcall(LoadAsset, path); a = StaticFindObject(path) end
        return a
    end
    local function im() return T.first("BP_InventoryManager_C") end
    local function hold(path)
        local m = im()
        m.Inventory_PlayerHand:GetSlot(0):RemoveAllItems({})
        if not path then return end
        m:GiveItemToPlayer(arch(path))
        local want = path:match("([^/%.]+)$")
        for i = 0, m.Inventory_Player:GetNumSlots() - 1 do
            local s = m.Inventory_Player:GetSlot(i)
            if s:GetNumItems() > 0 and s:GetCurrentArchetype():GetFName():ToString() == want then s:TransferStackIntoContainer(m.Inventory_PlayerHand, {}); return end
        end
        error("not in the backpack: " .. want)
    end
    local function me() return L.own() end
    local function handItem()
        local c = me()
        if not c then return end
        local o = {}
        c:GetActiveHandItem(false, o)
        local h = o["Hand Item"]
        return alive(h) and h or nil
    end
    local SMC = StaticFindObject("/Script/Engine.StaticMeshComponent")
    -- the mesh of our own hand item, found the way the mod does (CurrentItemMesh, else the biggest static mesh)
    local function ownMesh()
        local h = handItem()
        if not h then return "none" end
        local cim = h.CurrentItemMesh
        if alive(cim) and alive(cim:GetStaticMesh()) then return cim:GetStaticMesh():GetFullName() end
        local best, size = nil, -1
        for _, c in ipairs(h:K2_GetComponentsByClass(SMC)) do
            c = c:get()
            local sm = alive(c) and c:GetStaticMesh()
            if alive(sm) and sm:GetBounds().SphereRadius > size then best, size = sm, sm:GetBounds().SphereRadius end
        end
        return best and best:GetFullName() or "none"
    end
    -- the game's own input event of the use button: press (sets the desire flag the hand item acts on) and release
    local function press()
        local h = handItem()
        h:InpActEvt_ToolPrimaryUse_K2Node_InputActionEvent_2({})
        h:InpActEvt_ToolPrimaryUse_K2Node_InputActionEvent_3({})
        log("PT|info press on %s desire=%s", T.name(h), tostring(h["Desire Tool Primary Use"]))
    end

    -- B's side -----------------------------------------------------------------------------------------------------------
    local swing = { last = nil, max = 0 }
    local sampling = false
    local function otherC() return T.otherChar() end
    local function mirror()
        local o = otherC()
        if not o then return end
        for _, a in ipairs(FindAllOf("StaticMeshActor") or {}) do
            if alive(a) and a:GetAttachParentActor():IsValid() and a:GetAttachParentActor():GetFullName() == o:GetFullName() then return a end
        end
    end
    local function mirrorMesh()
        local a = mirror()
        local m = a and a.StaticMeshComponent:GetStaticMesh()
        return (m and m:IsValid()) and m:GetFullName() or "none"
    end
    local function mirrorSocket()
        local a = mirror()
        return a and a.RootComponent:GetAttachSocketName():ToString() or "none"
    end
    local function lightAtHead()
        local o = otherC()
        if not o then return false end
        local head = o.Mesh:GetSocketLocation(FName("head"))
        for _, cls in ipairs({ "SpotLight", "PointLight" }) do
            for _, a in ipairs(FindAllOf(cls) or {}) do
                if alive(a) and a.LightComponent:IsVisible() then
                    local l = a:K2_GetActorLocation()
                    if math.sqrt((l.X - head.X) ^ 2 + (l.Y - head.Y) ^ 2 + (l.Z - head.Z) ^ 2) < 120 then return true end
                end
            end
        end
        return false
    end
    -- the mirror's use swing is a rotation of the mirror for 0.45 s: sample it every 30 ms
    local function startSampler()
        if sampling then return end
        sampling = true
        local cache, at = nil, -1
        LoopInGameThreadWithDelay(30, function()
            pcall(function()
                -- FindAllOf is slow: look for the mirror twice a second, read its rotation every tick
                if not alive(cache) or os.clock() - at > 0.5 then cache, at = mirror(), os.clock() end
                if alive(cache) and math.abs(cache.RootComponent.RelativeRotation.Pitch) > 5 then swing.last = os.clock() end
            end)
        end)
    end

    local steps = {}
    local function add(s) steps[#steps + 1] = s end
    local function hostSetup()
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 8 })
        add({ run = function() startSampler() end })
    end
    local function guestSetup()
        steps[1] = T.onMap("RB_MainMenu", 90)
        add({ check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end })
        add({ check = "guest_sees_host", timeout = 60, cond = function() return otherC() ~= nil end })
        add({ wait = 8 })
        add({ run = function() startSampler() end })
    end
    if ROLE == "host" then hostSetup() else guestSetup() end

    local dirs = { { a = "host", b = "guest", tag = "1" }, { a = "guest", b = "host", tag = "2" } }
    for _, d in ipairs(dirs) do
        local I, tag = ROLE == d.a, d.tag
        local pre = (I and d.a or d.b) .. "_"
        local function msg(n) return "t.h" .. tag .. "_" .. n end
        -- A: act, announce; B: wait for the announcement, check, acknowledge. A waits for the ack before the next step.
        local function phase(n, name, act, observe)
            if I then
                add({ run = function() act(); say(msg(n), ownMesh()) end })
                add({ check = d.a .. "_phase_" .. name .. "_acked", timeout = to(30), cond = function() return has(msg(n) .. "k") ~= nil end })
            else
                add({ check = d.b .. "_told_" .. name, timeout = to(60), cond = function() return has(msg(n)) ~= nil end })
                add({ run = function() swing.last = nil end })
                add({ check = d.b .. "_sees_" .. name, timeout = to(4), cond = function() return observe(has(msg(n))) end })
                add({ run = function() say(msg(n) .. "k", "") end })
            end
        end
        phase(1, "item", function() hold(FLASH) end, function(mesh)
            local m = mirrorMesh()
            log("PT|info %s item mirror=%s hand=%s", d.b, m, mesh)
            return m ~= "none" and mesh ~= "none" and m == mesh
        end)
        phase(2, "light", function() press() end, function()
            log("PT|info %s light=%s swing=%s", d.b, tostring(lightAtHead()), tostring(swing.last))
            return lightAtHead() and swing.last ~= nil
        end)
        phase(3, "lightoff", function() press() end, function() return not lightAtHead() end)
        phase(4, "switch", function() hold(PATCH) end, function(mesh)
            local m = mirrorMesh()
            log("PT|info %s switch mirror=%s hand=%s", d.b, m, mesh)
            return m ~= "none" and m == mesh and not m:find("lashlight", 1, true) and not lightAtHead()
        end)
        phase(5, "use", function() press() end, function()
            log("PT|info %s swing=%s", d.b, tostring(swing.last))
            return swing.last ~= nil
        end)
        phase(6, "carry", function() hold(CAN) end, function(mesh)
            local s, m = mirrorSocket(), mirrorMesh()
            log("PT|info %s carry socket=%s mirror=%s hand=%s", d.b, s, m, mesh)
            return s == "spine_03" and m == mesh
        end)
        phase(7, "empty", function() hold(nil) end, function() return mirror() == nil end)
    end
    add({ wait = 3 })
    return steps
end
