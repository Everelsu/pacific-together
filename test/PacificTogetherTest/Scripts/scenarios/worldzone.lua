-- PT3 world, zone: things in the host's world that the guest did not see or saw different (first Steam play #15, #7b).
--   guest_sees_anchor              an ARC anchor structure (BP_Spawn_Anchor_Stable_S) the host's spawn pass made exists on the guest (a copy) within 60 s
--   guest_anchor_gone_when_host_takes   the host removes it (picks it up): the guest's copy goes
--   guest_generator_present        a plasma generator (whole) the host has exists on the guest, whole
--   guest_generator_broken_follows_host  the host's game breaks it (the harvest event): the guest's generator is broken within 10 s
-- Run: tools/run-test.ps1 -Scenario worldzone -Fixture zone -Headless [-Root .. -Port ..]   Mutation novisual: anchors not mirrored; noloot: see loot.lua
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local slow = (T.MUTATE == "novisual") and 0.15 or 1
    local function to(s) return math.max(12, math.floor(s * slow)) end
    local ANCHOR = "/Game/Gameplay/Resources/AnchorBase/BP_Spawn_Anchor_Stable_S.BP_Spawn_Anchor_Stable_S_C"
    local GEN = "/Game/Gameplay/Resources/PlasmaGenerator/BP_Spawn_Resource_Plasma_PlasmaGenerator.BP_Spawn_Resource_Plasma_PlasmaGenerator_C"
    local function alive(o) return o ~= nil and o:IsValid() end
    local function d3(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end
    local function spawn(path, p)
        if not StaticFindObject(path):IsValid() then pcall(LoadAsset, path) end
        local cls = StaticFindObject(path)
        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = p, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local a = gs:BeginDeferredActorSpawnFromClass(T.myPawn(), cls, xf, 1, nil)
        return gs:FinishSpawningActor(a, xf)
    end
    local function near(cn, p, r)
        for _, o in ipairs(FindAllOf(cn) or {}) do
            if alive(o) and not o:GetFullName():find("/Engine/Transient", 1, true) and d3(o:K2_GetActorLocation(), p) < r then return o end
        end
    end
    local got = {}
    local function poll()
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then return end
            got[k] = d
        end
    end
    local function pt(s) local x, y, z = s:match("^([^,]+),([^,]+),([^,]+)$"); return { X = tonumber(x), Y = tonumber(y), Z = tonumber(z) } end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local function toGuest(k, v) PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), k, v or "") end
        local anchor, gen
        for _, s in ipairs(T.loadFixture("zone")) do add(s) end
        add({ check = "host_listen_zone", timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_zone", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ check = "guest_ready", timeout = 400 * slow, cond = function() poll(); return got["t.ready"] ~= nil end })
        add({ run = function()
            local l = T.myPawn():K2_GetActorLocation()
            anchor = spawn(ANCHOR, { X = l.X, Y = l.Y + 700, Z = l.Z + 20 })
            for _ = 1, 8 do -- the game rolls a broken one on spawn sometimes: want a whole one
                gen = spawn(GEN, { X = l.X + 400, Y = l.Y + 700, Z = l.Z + 20 })
                if gen.Broken ~= true then break end
                gen:K2_DestroyActor()
            end
            local a, g = anchor:K2_GetActorLocation(), gen:K2_GetActorLocation()
            T.log("PT|info host spawned anchor %s generator broken=%s", anchor:GetFullName(), tostring(gen.Broken))
            toGuest("t.spawned", string.format("%.1f,%.1f,%.1f;%.1f,%.1f,%.1f", a.X, a.Y, a.Z, g.X, g.Y, g.Z))
        end })
        add({ check = "guest_generator_present", timeout = to(120), cond = function() poll(); return got["t.genok"] ~= nil end })
        add({ check = "guest_anchor_seen", timeout = to(120), cond = function() poll(); return got["t.anchorok"] ~= nil end })
        add({ run = function()
            -- the game's own path: the harvest event of the generator (Broken, mesh, light, highlight)
            gen["BndEvt__BP_ItemHarvestableComponent_K2Node_ComponentBoundEvent_0_OnHarvested__DelegateSignature"](gen, {}, 0, 0, false, nil)
            T.log("PT|info host broke the generator: broken=%s", tostring(gen.Broken))
            toGuest("t.broke", "1")
        end })
        add({ check = "host_generator_broken", timeout = 10, cond = function() return gen.Broken == true end })
        add({ check = "guest_generator_broken_follows_host", timeout = to(30), cond = function() poll(); return got["t.genbroken"] ~= nil end })
        add({ run = function() anchor:K2_DestroyActor(); toGuest("t.taken", "1") end })
        add({ check = "guest_anchor_gone_when_host_takes", timeout = to(60), cond = function() poll(); return got["t.anchorgone"] ~= nil end })
        add({ wait = 2 })
        return steps
    end

    -- guest
    local ap, gp
    local function sawBy(key, sec, test)
        local t0
        return function()
            poll()
            if not got[key] then return false end
            t0 = t0 or os.clock()
            return test()
        end
    end
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "Rural_Forest_Radio_Scylla_02" and T.cls(T.myPawn()) == T.CHAR end },
        { wait = 20 },
        { run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.ready", "1") end },
        { check = "got_spawned", timeout = 60, cond = function() poll(); if got["t.spawned"] then local a, g = got["t.spawned"]:match("^(.-);(.*)$"); ap, gp = pt(a), pt(g); return true end end },
        { check = "guest_generator_present", timeout = to(120), cond = function()
            local o = near("BP_Spawn_Resource_Plasma_PlasmaGenerator_C", gp, 150)
            if o and o.Broken ~= true then PTNative_MsgToHost(T.localPC():GetAddress(), "t.genok", "1"); return true end
            T.log("PT|info guest generator near host's: %s broken=%s", tostring(o ~= nil), tostring(o and o.Broken))
        end },
        { check = "guest_sees_anchor", timeout = to(120), cond = function()
            local o = near("BP_Spawn_Anchor_Stable_S_C", ap, 60)
            if o then PTNative_MsgToHost(T.localPC():GetAddress(), "t.anchorok", "1"); return true end
        end },
        { check = "guest_generator_broken_follows_host", timeout = to(60), cond = function()
            poll()
            if not got["t.broke"] then return false end
            local o = near("BP_Spawn_Resource_Plasma_PlasmaGenerator_C", gp, 150)
            if o and o.Broken == true then PTNative_MsgToHost(T.localPC():GetAddress(), "t.genbroken", "1"); return true end
        end },
        { check = "guest_anchor_gone_when_host_takes", timeout = to(60), cond = function()
            poll()
            if not got["t.taken"] then return false end
            if not near("BP_Spawn_Anchor_Stable_S_C", ap, 60) then PTNative_MsgToHost(T.localPC():GetAddress(), "t.anchorgone", "1"); return true end
        end },
        { wait = 3 },
    }
end
