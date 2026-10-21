-- W6: run-shaping anomalies act on both players, third pass. Fixture `zone`, the guest joins by itself.
--   spark tower (Tesla)        spawned next to the guest on the host: the guest sees it and takes its discharge
--   pickpocket (Part Stealer)  spawned at the car: the guest sees it and the part it takes leaves the guest's car too
--   bunny (Loot Creature)      the guest sees it; its push hurts the guest, not the host
-- Run: tools/run-test.ps1 -Scenario anomalies3 -Fixture zone -Headless
-- Mutation noanom3: the anomalies3 module is off in both processes.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local UEHelpers = require("UEHelpers")
    local CLS = {
        tesla = "/Game/Gameplay/Hazards/TeslaAnomaly/BP_Hazard_Tesla.BP_Hazard_Tesla_C",
        stealer = "/Game/Gameplay/Hazards/PartStealer/BP_Hazard_PartStealer.BP_Hazard_PartStealer_C",
        bunny = "/Game/Gameplay/Boons/ChubbyBunny/BP_Boon_LootCreature.BP_Boon_LootCreature_C",
    }
    local WATCH = { tesla = "BP_Hazard_Tesla_C", stealer = "BP_Hazard_PartStealer_C", bunny = "BP_Boon_LootCreature_C" }
    local function health()
        local rm = T.first("BP_ResourceManager_C")
        local h = rm and rm.PlayerHealth
        if not (h and h:IsValid()) then return -1 end
        return h.Current
    end
    local mapName = "Rural_Forest_Radio_Scylla_02"
    local function xf(x, y, z) return { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = x, Y = y, Z = z }, Scale3D = { X = 1, Y = 1, Z = 1 } } end
    local function spawn(path, x, y, z)
        local cls = StaticFindObject(path)
        if not cls:IsValid() then LoadAsset(path); cls = StaticFindObject(path) end
        local gs = UEHelpers.GetGameplayStatics()
        return gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(T.world(), cls, xf(x, y, z), 2, nil), xf(x, y, z))
    end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local guestHp, guestSpd, maxSpd, hostHp0, guestHp0, guestParts, partsBefore = -1, 0, 0, 0, 0, 0, 0
        local gpc, haz = nil, {}
        local function poll()
            while true do
                local kind, data = PTNative_MsgPoll("t.")
                if not kind then return end
                if kind == "t.parts" then guestParts = tonumber(data) or guestParts end
                if kind == "t.hp" then guestHp, guestSpd = data:match("^(%-?[%d%.]+)	([%d%.]+)$"); guestHp, guestSpd = tonumber(guestHp) or guestHp, tonumber(guestSpd) or 0 end
                if kind == "t.haz" then
                    haz = {}
                    for c, role, d in data:gmatch("([^|;]+)|(%d+)|([%d%.]+)") do haz[c] = { role = tonumber(role), dist = tonumber(d) } end
                end
            end
        end
        local function nearGuest(dx, dy) local l = L.guestChar():K2_GetActorLocation(); return l.X + dx, l.Y + dy, l.Z + 120 end
        local function sees(k)
            add({ check = "guest_sees_" .. k, timeout = 30, cond = function()
                poll()
                local h = haz[WATCH[k]]
                T.log("PT|info guest %s: %s", WATCH[k], h and string.format("role=%d dist=%.0f", h.role, h.dist) or "none")
                return h ~= nil and h.role == 1 and h.dist < 1500
            end })
        end
        for _, s in ipairs(T.loadFixture("zone")) do add(s) end
        add({ check = "host_listen", timeout = 120, cond = function() return T.netMode() == "listen" and T.listening() and T.map() == mapName end })
        add({ check = "host_guest_in", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 8 })
        add({ run = function() gpc = L.remotePCs()[1] end })

        -- spark tower: the discharge reaches the guest
        local tesla
        add({ run = function()
            poll(); guestHp0, hostHp0 = guestHp, health()
            tesla = spawn(CLS.tesla, nearGuest(700, 0))
            T.log("PT|info spawned tesla %s guestHp=%.0f hostHp=%.0f", T.name(tesla), guestHp0, hostHp0)
        end })
        sees("tesla")
        add({ check = "guest_hurt_by_tesla", timeout = 90, cond = function()
            poll()
            T.log("PT|info tesla: guest hp=%.0f (was %.0f) host hp=%.0f", guestHp, guestHp0, health())
            return guestHp < guestHp0 - 3
        end })
        add({ run = function() if tesla and tesla:IsValid() then tesla:K2_DestroyActor() end end })

        -- pickpocket: a Part Stealer at the car takes a part, the guest's car loses it too
        local stealer
        add({ check = "guest_car_has_parts", timeout = 60, cond = function() poll(); return guestParts >= 3 end })
        add({ run = function()
            poll(); partsBefore = guestParts
            local car = T.first("BaseNewCar")
            local l = car:K2_GetActorLocation()
            stealer = spawn(CLS.stealer, l.X + 250, l.Y, l.Z + 250)
            T.log("PT|info spawned stealer %s at the car, guest parts=%d", T.name(stealer), partsBefore)
        end })
        sees("stealer")
        add({ check = "guest_car_lost_part_to_stealer", timeout = 120, cond = function()
            poll()
            T.log("PT|info stealer state=%s guest parts=%d (was %d)", tostring(stealer:IsValid() and stealer.State), guestParts, partsBefore)
            return guestParts < partsBefore
        end })
        add({ run = function() if stealer and stealer:IsValid() then stealer:K2_DestroyActor() end end })

        -- bunny: the guest sees it and its push hurts the guest
        local bunny
        add({ run = function()
            poll(); guestHp0, hostHp0 = guestHp, health()
            bunny = spawn(CLS.bunny, nearGuest(400, 0))
            T.log("PT|info spawned bunny %s guestHp=%.0f hostHp=%.0f", T.name(bunny), guestHp0, hostHp0)
        end })
        sees("bunny")
        add({ run = function()
            poll(); guestHp0, hostHp0 = guestHp, health()
            pcall(function() bunny:PushFx() end) -- the game's push step (damage 0.1 intensity, radial force) as a touch starts it
            pcall(function() bunny.PlayerPusher:FireImpulse() end)
            T.log("PT|info bunny push sent")
        end })
        add({ check = "guest_hurt_by_bunny", timeout = 20, cond = function()
            poll()
            T.log("PT|info bunny: guest hp=%.0f (was %.0f) host hp=%.0f", guestHp, guestHp0, health())
            return guestHp < guestHp0 - 0.5
        end })
        add({ check = "host_not_hurt_by_bunny_on_guest", timeout = 5, cond = L.holds(3, function() return health() >= hostHp0 - 0.5 end) })
        add({ run = function() PTNative_MsgToGuest(gpc:GetAddress(), "t.end", "1") end })
        add({ wait = 3 })
        return steps
    end

    local finished = false
    local WATCHL = { "BP_Hazard_Tesla_C", "BP_Hazard_PartStealer_C", "BP_Boon_LootCreature_C" }
    LoopInGameThreadWithDelay(1000, function()
        pcall(function()
            if T.netMode() ~= "client" then return end
            local me, out = T.myPawn(), {}
            if me and me:IsValid() then
                for _, c in ipairs(WATCHL) do
                    local best
                    for _, o in ipairs(FindAllOf(c) or {}) do
                        if T.inWorld(o) and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) then
                            local d = T.dist(me, o)
                            if not best or d < best.d then best = { d = d, r = o.Role } end
                        end
                    end
                    if best then out[#out + 1] = string.format("%s|%d|%.0f", c, best.r, best.d) end
                end
            end
            PTNative_MsgToHost(T.localPC():GetAddress(), "t.haz", table.concat(out, ";"))
            local n, im, box = 0, T.first("BP_InventoryManager_C"), {}
            if im then
                im:GetCarEquippedContainer(box)
                local c = box.Inventory_CarEquipped
                if c and c:IsValid() then c.Slots:ForEach(function(_, e) e:get().Items:ForEach(function() n = n + 1 end) end) end
            end
            PTNative_MsgToHost(T.localPC():GetAddress(), "t.parts", tostring(n))
            local v = me and me:IsValid() and me:GetVelocity() or { X = 0, Y = 0, Z = 0 }
            PTNative_MsgToHost(T.localPC():GetAddress(), "t.hp", string.format("%.0f	%.0f", health(), math.sqrt(v.X ^ 2 + v.Y ^ 2)))
            while true do
                local kind, data = PTNative_MsgPoll("t.")
                if not kind then break end
                if kind == "t.end" then finished = true end
            end
        end)
    end)
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == mapName and T.cls(T.myPawn()) == T.CHAR end },
        { check = "client_stays_until_host_done", timeout = 600, cond = function() return finished end },
    }
end
