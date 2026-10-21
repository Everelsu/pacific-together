-- M3 car (C1-C4, C7). Only the car's transform replicates, so:
--   guest: its own copy of the car (Role 3) is destroyed once the host's replicated car is there; the replicated car is
--          kinematic and moved every frame by motion-time Hermite interpolation of ReplicatedMovement (X7); the game's
--          door interaction (BP_CarPart_Door_Base:EnterCar) is turned into an intent, the host seats the guest in the
--          mirrored passenger seat and the guest holds the seat (X8); the host's car state (parts, health, fuel, battery,
--          ignition, gear, lights, doors, handbrake) arrives as a message and is applied to the guest's own car inventory.
--   host:  seats/unseats the guest on intent and broadcasts the state; the ARC is moved between the seats (D12).
-- Only the garage/run car BP_PlayerCarNew_C (not the intro car). Single player: nothing here runs unless this is a client, or a listening host with a guest.
local UEHelpers = require("UEHelpers")
local common = require("common")
local safety = require("safety")
local net = require("net")
local log = common.log
local ov = require("overlay")

local M = {}
if os.getenv("PT_MUTATE") == "nocarsync" then
    log("PT|car disabled (mutation nocarsync)")
    return M
end

local NONE = FName("None")
local PREFIX = "/Game/Gameplay/Inventory/Items/"
local COMP = "/Game/Gameplay/Inventory/GenericItemProperties/Components/"
local PASSENGER = { X = 46.2, Y = 45.8, Z = -12.3 } -- X8: the driver's seat mirrored across the car's centre line
local ARC_SHIFT = -42.5                              -- X8: both ARC slots, car-local Y

-- helpers -------------------------------------------------------------------------------------------------------------

local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function fname(o) return valid(o) and o:GetFullName() or "none" end
local function same(a, b) return valid(a) and valid(b) and a:GetFullName() == b:GetFullName() end
local function world() return UEHelpers.GetWorld() end
local function inWorld(o) return valid(o) and valid(o:GetWorld()) and same(o:GetWorld(), world()) end
local function now()
    local s, p = {}, {}
    UEHelpers.GetGameplayStatics():GetAccurateRealTime(s, p)
    return s.Seconds + p.PartialSeconds
end
local function vec(x, y, z) return { X = x, Y = y, Z = z } end
local function dist(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end
local function kml() return StaticFindObject("/Script/Engine.Default__KismetMathLibrary") end
local function toLocal(car, p) return kml():InverseTransformLocation(car:GetTransform(), p) end
local function toWorld(car, p) return kml():TransformLocation(car:GetTransform(), p) end
local function first(class)
    for _, o in ipairs(FindAllOf(class) or {}) do if valid(o) then return o end end
end
local function localPC()
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        if inWorld(pc) and pc:IsLocalController() then return pc end
    end
end

-- a destroyed car stays IsValid until GC and then sits at exactly 0,0,0 (X7)
local function gone(c)
    if not valid(c) or not valid(c.RootComponent) then return true end
    local p = c:K2_GetActorLocation()
    return p.X == 0 and p.Y == 0 and p.Z == 0
end
local function cars()
    local r = {}
    for _, c in ipairs(FindAllOf("BP_PlayerCarNew_C") or {}) do
        if inWorld(c) and not gone(c) then r[#r + 1] = c end
    end
    return r
end
-- the host's car: on the host its only car; on the guest the replicated one (Role 3 = the guest's own copy)
local function theCar(isHost)
    for _, c in ipairs(cars()) do
        if isHost or c.Role ~= 3 then return c end
    end
end
local function localCopies()
    local r = {}
    for _, c in ipairs(cars()) do if c.Role == 3 then r[#r + 1] = c end end
    return r
end
local function carManager() return first("BP_CarManager_C") end

-- the car's equipped container: one slot per car slot tag, one ItemInstance per installed part
local function equipped()
    local im = first("BP_InventoryManager_C")
    if not im then return end
    local box = {}
    im:GetCarEquippedContainer(box)
    local c = box.Inventory_CarEquipped
    return valid(c) and c or nil
end
local function itemOf(slot)
    local it
    slot.Items:ForEach(function(_, e) it = e:get() end)
    return valid(it) and it or nil
end
local function slotName(slot) return (slot.SlotName:ToString():gsub("^Car%.Equip%.", "")) end
local function archPath(it)
    local p = it.Archetype:GetFullName():match("^%S+ ([^%.]+)")
    return p and (p:sub(1, #PREFIX) == PREFIX and p:sub(#PREFIX + 1) or p) or "?"
end
local function archObject(p)
    if p:sub(1, 1) ~= "/" then p = PREFIX .. p end
    local full = p .. "." .. p:match("([^/]+)$")
    local o = StaticFindObject(full)
    if not valid(o) then o = LoadAsset(full) end
    return valid(o) and o or nil
end
local function manifestation(cm, name)
    local r, r2 = {}, {}
    cm:GetItemManifestationEquippedInSlot({ TagName = FName("Car.Equip." .. name) }, r, r2)
    local m = r.Manifestation
    return valid(m) and m or nil
end

-- property components of a part (health, fuel, battery), cached per manifestation
local classes, compCache = nil, {}
local function propComps(m)
    classes = classes or {
        h = StaticFindObject(COMP .. "BP_HealthComponent.BP_HealthComponent_C"),
        f = StaticFindObject(COMP .. "BP_FuelableComponent.BP_FuelableComponent_C"),
        b = StaticFindObject(COMP .. "BP_BatteryComponent.BP_BatteryComponent_C"),
    }
    local key = m:GetAddress()
    local c = compCache[key]
    if c and c.owner == m:GetFullName() then return c end
    c = { owner = m:GetFullName() }
    for k, cls in pairs(classes) do
        for _, x in ipairs(m:K2_GetComponentsByClass(cls)) do
            local comp = x:get()
            -- the gas cap and the charge port pass fuel and charge through; the tanks and batteries own it
            local n = comp:GetClass():GetFName():ToString()
            if not n:find("GasCap", 1, true) and not n:find("ChargePort", 1, true) then c[k] = comp; break end
        end
    end
    compCache[key] = c
    return c
end
local function readPart(c)
    local h, f, b
    if c.h and valid(c.h) then
        local t = { {}, {}, {}, {}, {}, {}, {}, {} }
        c.h:GetHealth(t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8])
        h = t[1].Health
    end
    if c.f and valid(c.f) then
        local t = { {}, {}, {}, {}, {}, {}, {} }
        c.f:GetFuelStatus(t[1], t[2], t[3], t[4], t[5], t[6], t[7])
        f = t[1].Fuel
    end
    if c.b and valid(c.b) then
        local t = { {}, {}, {}, {}, {} }
        c.b:GetBatteryStatus(t[1], t[2], t[3], t[4], t[5])
        b = t[1].BATTERY
    end
    return h, f, b
end
local function num(v) return v and string.format("%.1f", v) or "-" end

-- ARC (D12): both of its slots slide between the seats; nothing about it replicates, each side moves its own pair
local arcDone = {}
local function moveArc(car)
    for _, class in ipairs({ "BP_Carpart_Internal_Gobbler_C", "BP_Carpart_Internal_GobblerScreen_C" }) do
        for _, a in ipairs(FindAllOf(class) or {}) do
            if inWorld(a) and same(a:GetAttachParentActor(), car) then
                local slot = a.RootComponent:GetAttachParent()
                if valid(slot) and not arcDone[slot:GetFullName()] then
                    local r = slot.RelativeLocation
                    if r.Y > ARC_SHIFT / 2 then
                        slot:K2_SetRelativeLocation(vec(r.X, r.Y + ARC_SHIFT, r.Z), false, {}, true)
                        log("PT|car arc slot moved %s", slot:GetFullName())
                    end
                    arcDone[slot:GetFullName()] = true
                end
            end
        end
    end
end

-- host -------------------------------------------------------------------------------------------------------------------

local function sample(car, cm)
    local cont = equipped()
    if not cont then return end
    local ign = cm.CarIgnitionState
    local doors = 0
    for d = 0, 5 do
        local o = {}
        cm:GetDoorState(d, o)
        if o.Open then doors = doors | (1 << d) end
    end
    local hb = false
    pcall(function() hb = car.VehicleController:GetParkingBrakeActive() end)
    local lines = { string.format("H\t%d\t%d\t%d\t%d\t%d", ign, cm.MyCarGearBox, cm.CarLightsOn and 1 or 0, hb and 1 or 0, doors) }
    local n = 0
    cont.Slots:ForEach(function(_, e)
        local slot = e:get()
        local it = itemOf(slot)
        if it then
            local name = slotName(slot)
            local h, f, b
            local m = manifestation(cm, name)
            if m then h, f, b = readPart(propComps(m)) end
            n = n + 1
            lines[#lines + 1] = string.format("P\t%s\t%s\t%s\t%s\t%s", name, archPath(it), num(h), num(f), num(b))
        end
    end)
    lines[#lines + 1] = "E\t" .. n
    return table.concat(lines, "\n")
end

local lastSent, lastAt, lastGuests = nil, 0, 0
local function hostTick()
    local guests = net.guests()
    if #guests == 0 then lastSent, lastGuests = nil, 0; return end
    local car, cm = theCar(true), carManager()
    if not car or not cm then return end
    moveArc(car)
    local s = sample(car, cm)
    if not s then return end
    local t = now()
    if #guests ~= lastGuests or s ~= lastSent or t - lastAt > 3 then
        net.toGuests("g.car.s", s)
        lastSent, lastAt, lastGuests = s, t, #guests
    end
end

-- C1: seat the guest at the mirrored seat and attach it (movement and collision off on both sides)
local function seat(char, car)
    local lp = PASSENGER
    pcall(function()
        local t = {}
        local f = StaticFindObject(char:GetClass():GetFullName():match("^%S+ (.+)$") .. ":GetCarAttachTransformForCharacter")
        f(char, t)
        local d = toLocal(car, t.Translation)
        lp = vec(d.X, -d.Y, d.Z)
    end)
    pcall(function() char.CharacterMovement:DisableMovement() end)
    char:SetActorEnableCollision(false)
    local r = car:K2_GetActorRotation()
    char:K2_SetActorLocationAndRotation(toWorld(car, lp), { Pitch = 0, Yaw = r.Yaw, Roll = 0 }, false, {}, true)
    char:K2_AttachToActor(car, NONE, 1, 1, 1, false)
    log("PT|car seated %s at %.1f,%.1f,%.1f", char:GetFullName(), lp.X, lp.Y, lp.Z)
end

local function guestChar(pc)
    local c = pc.Pawn
    return valid(c) and c:IsA(StaticFindObject("/Script/PenDriverPro.BaseCharacter")) and c or nil
end

net.on("g.car.enter", function(pc)
    if not safety.active() or common.netMode() ~= "listen" then return end
    local char, car = guestChar(pc), theCar(true)
    if not char or not car then return end
    if same(char:GetAttachParentActor(), car) then return end
    -- shortcut: no reach check (a client-side teleport did not move the guest on the host); add one when doors are real input
    log("PT|car enter from %.0f uu", dist(char:K2_GetActorLocation(), car:K2_GetActorLocation()))
    seat(char, car)
    ov.post(ov.other() .. " entered the car")
end)

net.on("g.car.exit", function(pc)
    if common.netMode() ~= "listen" then return end
    local char, car = guestChar(pc), theCar(true)
    if not char or not car or not same(char:GetAttachParentActor(), car) then return end
    char:K2_DetachFromActor(1, 1, 1)
    -- beside the driver's door, a little up so the capsule clears the sill
    local p = car:K2_GetActorLocation()
    local r = car:GetActorRightVector()
    local out = vec(p.X - r.X * 250, p.Y - r.Y * 250, p.Z + 80)
    char:K2_SetActorLocation(out, false, {}, true)
    -- the guest's own pawn is autonomous: the host's move is not replicated to it, so it places itself
    net.toGuest(pc, "g.car.out", string.format("%.2f|%.2f|%.2f", out.X, out.Y, out.Z))
    char:SetActorEnableCollision(true)
    pcall(function() char.CharacterMovement:SetMovementMode(1, 0) end)
    log("PT|car guest left the car")
    ov.post(ov.other() .. " left the car")
end)

net.on("g.car.hello", function() lastSent = nil end)

-- guest ------------------------------------------------------------------------------------------------------------------

-- X7: chassis kinematic, vehicle controller off, placed every frame by motion-time Hermite interpolation of the replicated
-- transform (ported from the carride scenario's carlib.lua, mode "motion")
local function wrap(a) return (a + 180) % 360 - 180 end
local function hermite(a, b, s, k)
    local h = b[k] - a[k]
    local s2, s3 = s * s, s * s * s
    local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
    local function ax(c, vk) return h00 * a[c] + h10 * h * a[vk] + h01 * b[c] + h11 * h * b[vk] end
    local function ang(c) return a[c] + wrap(b[c] - a[c]) * s end
    return vec(ax("x", "vx"), ax("y", "vy"), ax("z", "vz")), { Pitch = ang("pitch"), Yaw = ang("yaw"), Roll = ang("roll") }
end
local function sample_at(buf, r, k)
    local n = #buf
    if n == 0 then return end
    for i = n - 1, 1, -1 do
        local a, b = buf[i], buf[i + 1]
        if a[k] <= r and r < b[k] then return hermite(a, b, (r - a[k]) / (b[k] - a[k]), k) end
    end
    local z = buf[n]
    if r < buf[1][k] then z = buf[1] end
    local dt = math.max(0, math.min(r - z[k], 0.25))
    return vec(z.x + z.vx * dt, z.y + z.vy * dt, z.z + z.vz * dt), { Pitch = z.pitch, Yaw = z.yaw, Roll = z.roll }
end
-- a motion time is the previous one plus the time the car needed for the distance at its replicated speed, pulled 10 %
-- per snapshot towards the arrival time so it cannot drift
local function motionTime(prev, t, p, v)
    if not prev then return t end
    local h = t - prev.t
    local sp = (math.sqrt(v.X ^ 2 + v.Y ^ 2 + v.Z ^ 2) + math.sqrt(prev.vx ^ 2 + prev.vy ^ 2 + prev.vz ^ 2)) / 2
    if sp > 50 then
        local d = math.sqrt((p.X - prev.x) ^ 2 + (p.Y - prev.y) ^ 2 + (p.Z - prev.z) ^ 2)
        h = math.max(0.3 * h, math.min(3 * h, d / sp))
    end
    local tm = prev.tm + h
    return tm + 0.1 * (t - tm)
end

local followed, followLoop = nil, nil
local function follow(car)
    if followLoop then CancelDelayedAction(followLoop) end
    pcall(function() car.Chassis:SetSimulatePhysics(false) end)
    pcall(function() car.VehicleController:SetComponentTickEnabled(false) end)
    local buf, gaps, last, delay, target = {}, {}, nil, 0.1, 0.1
    local name = car:GetFullName()
    log("PT|car follow %s", name)
    followed = name
    followLoop = LoopInGameThreadWithDelay(1, function()
        if not valid(car) then CancelDelayedAction(followLoop); followLoop, followed = nil, nil; return end
        local ok, err = pcall(function()
            local t, rm = now(), car.ReplicatedMovement
            local p, r, v = rm.Location, rm.Rotation, rm.LinearVelocity
            if not last or p.X ~= last.x or p.Y ~= last.y or p.Z ~= last.z then
                local tm = motionTime(last, t, p, v)
                if last then
                    table.insert(gaps, t - last.t)
                    if #gaps > 60 then table.remove(gaps, 1) end
                    local s = {}
                    for i, g in ipairs(gaps) do s[i] = g end
                    table.sort(s)
                    target = math.max(0.1, math.min(0.25, 1.5 * s[math.ceil(#s * 0.95)] + 0.02))
                else
                    delay = target
                end
                last = { t = t, tm = tm, x = p.X, y = p.Y, z = p.Z, vx = v.X, vy = v.Y, vz = v.Z, pitch = r.Pitch, yaw = r.Yaw, roll = r.Roll }
                table.insert(buf, last)
                if #buf > 64 then table.remove(buf, 1) end
            end
            delay = delay + (target - delay) * 0.01
            local to, rot = sample_at(buf, t - delay, "tm")
            if to then car:K2_SetActorLocationAndRotation(to, rot, false, {}, true) end
        end)
        if not ok then log("PT|error car follow %s", tostring(err)) end
    end)
end

-- the guest's own copy of the car and its part actors
local function dedupe(car)
    for _, c in ipairs(localCopies()) do
        local n = 0
        for _, a in ipairs(FindAllOf("Actor") or {}) do
            if valid(a) and same(a:GetAttachParentActor(), c) then a:K2_DestroyActor(); n = n + 1 end
        end
        log("PT|car destroying local copy %s (%d parts)", c:GetFullName(), n)
        c:K2_DestroyActor()
    end
    local cm = carManager()
    if cm and not same(cm.NewCarActor, car) then cm.NewCarActor = car end
end

-- X8: once the host attached us, hold the replicated offset; the pawn arrives attached but far off its seat
local riding = nil
local function seatErr(char, car)
    local o = char.AttachmentReplication.LocationOffset
    return dist(toLocal(car, char:K2_GetActorLocation()), vec(o.X, o.Y, o.Z))
end
local function stopRide(char)
    if riding then CancelDelayedAction(riding.loop) end
    riding = nil
    if valid(char) then
        pcall(function() char:SetActorEnableCollision(true) end)
        pcall(function() char.CharacterMovement:SetComponentTickEnabled(true); char.CharacterMovement:SetMovementMode(1, 0) end)
    end
end
net.on("g.car.out", function(_, data)
    if common.netMode() ~= "client" or os.getenv("PT_MUTATE") == "noexitfix" then return end
    local me = localPC() and localPC().Pawn
    local x, y, z = data:match("^([^|]*)|([^|]*)|(.*)$")
    if not valid(me) or not x then return end
    pcall(function() me:K2_DetachFromActor(1, 1, 1) end)
    stopRide(me)
    me:K2_SetActorLocation(vec(tonumber(x), tonumber(y), tonumber(z)), false, {}, true)
    log("PT|car guest placed outside at %s,%s,%s", x, y, z)
end)

local function ride(char, car)
    local cm = char.CharacterMovement
    pcall(function() cm:StopMovementImmediately(); cm:DisableMovement(); cm:SetComponentTickEnabled(false) end)
    pcall(function() char:SetActorEnableCollision(false) end)
    local function place()
        local o = char.AttachmentReplication.LocationOffset
        char:K2_SetActorRelativeLocation(vec(o.X, o.Y, o.Z), false, {}, true)
    end
    place()
    local fixes = 0
    local loop
    loop = LoopInGameThreadWithDelay(1, function()
        local ok = pcall(function()
            if not same(char:GetAttachParentActor(), car) then
                log("PT|car left the seat (fixes=%d)", fixes)
                stopRide(char)
                return
            end
            if seatErr(char, car) > 1 then
                fixes = fixes + 1
                if fixes <= 3 then log("PT|car seat guard n=%d", fixes) end
                place()
            end
        end)
        if not ok then CancelDelayedAction(loop); riding = nil end
    end)
    riding = { loop = loop, car = car:GetFullName() }
    log("PT|car riding %s offset=%.1f,%.1f,%.1f", car:GetFullName(), char.AttachmentReplication.LocationOffset.X,
        char.AttachmentReplication.LocationOffset.Y, char.AttachmentReplication.LocationOffset.Z)
end

-- apply the host's state to our own car inventory (the manifestations on the replicated car follow it)
local function applyState(data)
    local cm, cont = carManager(), equipped()
    if not cm or not cont then return end
    local car = theCar(false)
    local head, parts, count, n = nil, {}, 0, nil
    for line in data:gmatch("[^\n]+") do
        local f = {}
        for x in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = x end
        if f[1] == "H" then head = f
        elseif f[1] == "P" then parts[f[2]] = { arch = f[3], h = tonumber(f[4]), f = tonumber(f[5]), b = tonumber(f[6]) }; count = count + 1
        elseif f[1] == "E" then n = tonumber(f[2]) end
    end
    -- a truncated message must never look like "the host has no parts"
    if not head or n ~= count then log("PT|error car state message incomplete"); return end
    local changed = 0
    cont.Slots:ForEach(function(_, e)
        local slot = e:get()
        local name = slotName(slot)
        local want, it = parts[name], itemOf(slot)
        if not want then
            if it then slot:RemoveAllItems({}); changed = changed + 1; log("PT|car part removed %s", name); if ov.settled() then ov.post("%d car part{s} changed by the host", "info", "carpart") end end
            return
        end
        if not it or archPath(it) ~= want.arch then
            local arch = archObject(want.arch)
            if not arch then log("PT|error car archetype not found %s", want.arch); return end
            if it then slot:RemoveAllItems({}) end
            slot:SetItem(arch:CreateInstance(UEHelpers.GetWorldContextObject(), 0), {})
            changed = changed + 1
            log("PT|car part installed %s %s", name, want.arch)
            if ov.settled() then ov.post("%d car part{s} changed by the host", "info", "carpart") end
        end
        if want.h or want.f or want.b then
            local m = manifestation(cm, name)
            if m then
                local c = propComps(m)
                local h, f, b = readPart(c)
                if want.h and h and math.abs(h - want.h) > 0.05 then c.h:SetHealth(want.h); changed = changed + 1 end
                if want.f and f and math.abs(f - want.f) > 0.05 then c.f["Set Fuel"](c.f, want.f); changed = changed + 1 end
                if want.b and b and math.abs(b - want.b) > 0.05 then c.b["Set Battery"](c.b, want.b); changed = changed + 1 end
            end
        end
    end)
    if changed > 0 then
        pcall(function() cm:UpdateAggregateFuel() end)
        pcall(function() cm:UpdateAggregateBattery() end)
    end
    -- car-level state
    local ign, gear, lights, hb, doors = tonumber(head[2]), tonumber(head[3]), head[4] == "1", head[5] == "1", tonumber(head[6])
    if car then
        if cm.CarIgnitionState ~= ign then pcall(function() car:ManualSetIgnition_NoAnim(ign) end) end
        if cm.MyCarGearBox ~= gear then pcall(function() car:ManualActivate_Gearbox(gear, true) end) end
        pcall(function()
            if car.VehicleController:GetParkingBrakeActive() ~= hb then car.VehicleController:SetParkingBrakeActive(hb) end
        end)
    end
    if cm.CarLightsOn ~= lights then pcall(function() cm:SetCarLightsOn(lights) end) end
    for d = 0, 5 do
        local o = {}
        cm:GetDoorState(d, o)
        local want = (doors >> d) & 1 == 1
        if o.Open ~= want then pcall(function() cm:SetDoorState(d, want) end) end
    end
end

net.on("g.car.s", function(_, data)
    if common.netMode() ~= "client" then return end
    local ok, err = pcall(applyState, data)
    if not ok then log("PT|error car apply %s", tostring(err)) end
end)

-- C1: the game's door interaction ends in the door's EnterCar, then a broadcast of CommandEnterCar to every character of
-- this process, ours included (muted below). The intent goes to the host.
local function sendEnter()
    local char = localPC() and localPC().Pawn
    log("PT|car enter intent sent=%s", tostring(net.toHost("g.car.enter")))
    return char
end
local function sendExit()
    log("PT|car exit intent sent=%s", tostring(net.toHost("g.car.exit")))
end

local hooked = false
local function hookAll()
    if hooked then return end
    local ok, err = pcall(RegisterHook, "/Game/Gameplay/Inventory/Items/Car/Doors/BP_CarPart_Door_Base.BP_CarPart_Door_Base_C:EnterCar", function(self)
        local okc, e = pcall(function()
            if common.netMode() ~= "client" then return end
            sendEnter()
            -- the door flow set this and waits for the (muted) enter to end it
            local door = self:get() -- a hook parameter must not outlive the callback
            ExecuteInGameThreadWithDelay(500, function() pcall(function() if valid(door) then door.PlayerStartedEnteringCar = false end end) end)
        end)
        if not okc then log("PT|error car door hook %s", tostring(e)) end
    end)
    if not ok then log("PT|error car hook EnterCar %s", tostring(err)); return end
    hooked = true
    -- leaving: key X while seated
    pcall(RegisterKeyBind, Key.X, function()
        ExecuteInGameThread(function() if common.netMode() == "client" and riding then sendExit() end end)
    end)
end

local helloFor = nil
local function guestTick()
    local car = theCar(false)
    if not car then return end
    hookAll()
    local c0 = #localCopies()
    if c0 > 0 then dedupe(car) end
    if followed ~= car:GetFullName() then follow(car) end
    moveArc(car)
    local pc = localPC()
    local me = pc and pc.Pawn
    if valid(me) then
        -- our own enter must not run locally; it is the host's job
        if PTNative_Mute then PTNative_Mute(me:GetAddress(), "CommandEnterCar") end
        if same(me:GetAttachParentActor(), car) then
            if not riding or riding.car ~= car:GetFullName() then ride(me, car) end
        elseif riding then
            stopRide(me)
        end
    end
    if helloFor ~= car:GetFullName() then
        helloFor = car:GetFullName()
        net.toHost("g.car.hello")
    end
end

LoopInGameThreadWithDelay(250, function()
    local mode = common.netMode()
    local ok, err
    if mode == "client" then ok, err = pcall(guestTick)
    elseif mode == "listen" then ok, err = pcall(hostTick)
    else
        riding, helloFor, followed = nil, nil, nil
        return
    end
    if not ok then log("PT|error car tick %s", tostring(err)) end
end)

M.exit = sendExit
-- for guestact.lua (the guest's car work and ARC)
M.theCar, M.carManager, M.equipped, M.itemOf, M.slotName = theCar, carManager, equipped, itemOf, slotName
M.manifestation, M.propComps, M.readPart = manifestation, propComps, readPart
return M
