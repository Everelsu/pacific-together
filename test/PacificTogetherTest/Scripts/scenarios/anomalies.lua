-- W6, W7, D19: anomalies act on both players. Fixture `zone`, the guest joins by itself.
--   damage    a Landmine (the Tourist class) blows up next to the guest only: the guest's own health drops, the host's does not
--             (before the mod the guest's pawn on the host hurt the HOST's health and the guest felt nothing).
--   (Tourists: scenario tourist with PT_MUTATE=mod, in the garage where the guest camera reaches the host)
-- Run: tools/run-test.ps1 -Scenario anomalies -Fixture zone -Headless
-- Mutation noanom: the shipping mod's anomalies module is off in both processes (the guest takes no damage, the host does, the Tourist creeps).
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local UEHelpers = require("UEHelpers")
    local MINE = "/Game/Gameplay/Hazards/Landmine/BP_Hazard_Landmine.BP_Hazard_Landmine_C"
    local mapName = "Rural_Forest_Radio_Scylla_02"

    local function health()
        local rm = T.first("BP_ResourceManager_C")
        local h = rm and rm.PlayerHealth
        if not (h and h:IsValid()) then return -1, 100 end
        return h.Current, h.Maximum
    end
    local function xf(x, y, z) return { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = x, Y = y, Z = z }, Scale3D = { X = 1, Y = 1, Z = 1 } } end
    local function spawnMine(x, y, z)
        local cls = StaticFindObject(MINE)
        if not cls:IsValid() then LoadAsset(MINE); cls = StaticFindObject(MINE) end
        local gs = UEHelpers.GetGameplayStatics()
        return gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(T.world(), cls, xf(x, y, z), 2, nil), xf(x, y, z))
    end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local gpc, guestHp, mine, start, guestHp0, hostHp0 = nil, -1, nil, nil, 0, 0
        local function poll()
            while true do
                local kind, data = PTNative_MsgPoll("t.")
                if not kind then return end
                if kind == "t.hp" then guestHp = tonumber(data) or guestHp end
            end
        end
        -- the guest turns itself (a rotation the host sets is not kept in the zone); its moves carry the view to the host
        local function turnGuest(yaw) PTNative_MsgToGuest(gpc:GetAddress(), "t.look", tostring(yaw)) end
        local function moved() local l = mine:K2_GetActorLocation(); return math.sqrt((l.X - start.X) ^ 2 + (l.Y - start.Y) ^ 2) end
        for _, s in ipairs(T.loadFixture("zone")) do add(s) end
        add({ check = "host_listen", timeout = 120, cond = function() return T.netMode() == "listen" and T.listening() and T.map() == mapName end })
        add({ check = "host_guest_in", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 8 })
        add({ run = function() gpc = L.remotePCs()[1] end })
        add({ check = "host_sees_guest_health", timeout = 20, cond = function() poll(); guestHp0, hostHp0 = guestHp, (health()); return guestHp > 50 and hostHp0 > 50 end })
        -- what every hazard does: dispatch a damage message to the pawns near it; here to the guest's pawn on the host
        -- (a spawned Landmine also throws the car and the host about, which would hide whose health dropped)
        add({ run = function()
            local MSG = "/Game/Systems/Messages/MSG_Damage_Electrical.MSG_Damage_Electrical_C"
            local ms = T.first("MessageSystem")
            if not StaticFindObject(MSG):IsValid() then LoadAsset(MSG) end
            local m = StaticConstructObject(StaticFindObject(MSG), ms)
            m.Damage = 15
            ms:DispatchMessage(m, L.guestChar())
            T.log("PT|info shock sent to the guest's pawn: hostHp=%.0f guestHp=%.0f", health(), guestHp)
        end })
        add({ check = "guest_hurt_by_mine", timeout = 25, cond = function() poll(); T.log("PT|info guest hp=%.0f host hp=%.0f", guestHp, (health())); return guestHp < guestHp0 - 8 end })
        add({ check = "host_not_hurt_for_guest", timeout = 15, cond = L.holds(8, function() poll(); return health() >= hostHp0 - 0.5 end) })
        add({ run = function() PTNative_MsgToGuest(gpc:GetAddress(), "t.end", "1") end })
        add({ wait = 3 })
        return steps
    end

    -- guest: reports its health once a second until the host is done
    local finished, lookYaw = false, nil
    LoopInGameThreadWithDelay(200, function()
        pcall(function() if lookYaw and T.netMode() == "client" then T.localPC():SetControlRotation({ Pitch = 0, Yaw = lookYaw, Roll = 0 }) end end)
    end)
    LoopInGameThreadWithDelay(1000, function()
        pcall(function()
            if T.netMode() ~= "client" then return end
            PTNative_MsgToHost(T.localPC():GetAddress(), "t.hp", string.format("%.0f", (health())))
            while true do
                local kind, data = PTNative_MsgPoll("t.")
                if not kind then break end
                if kind == "t.end" then finished = true end
                if kind == "t.look" then lookYaw = tonumber(data) end
            end
        end)
    end)
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == mapName and T.cls(T.myPawn()) == T.CHAR end },
        { check = "client_stays_until_host_done", timeout = 400, cond = function() return finished end },
    }
end
