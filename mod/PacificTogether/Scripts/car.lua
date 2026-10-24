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
local ARC_SHIFT = { X = -70, Y = 0 } -- both ARC slots, car-local: behind the seats (the old X8 spot between them hid the starter key)
if os.getenv("PT_MUTATE") == "arcold" then ARC_SHIFT = { X = 0, Y = -42.5 } end -- test mutation: the old spot

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
local first = common.first
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
-- read several times per tick by several modules (665 lookups a minute on a guest, PT|perf 2026-10-22): reused for 100 ms,
-- each car is still checked on every call
local carList, carAt = {}, -1
RegisterLoadMapPreHook(function() carList, carAt = {}, -1 end)
local function cars()
    if os.clock() - carAt > 0.1 then carList, carAt = FindAllOf("BP_PlayerCarNew_C") or {}, os.clock() end
    local r = {}
    for _, c in ipairs(carList) do
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
                    -- not yet moved: the slot is still on the near side of the half-way point along the shift
                    if r.X * ARC_SHIFT.X + r.Y * ARC_SHIFT.Y < (ARC_SHIFT.X ^ 2 + ARC_SHIFT.Y ^ 2) / 2 then
                        slot:K2_SetRelativeLocation(vec(r.X + ARC_SHIFT.X, r.Y + ARC_SHIFT.Y, r.Z), false, {}, true)
                        log("PT|car arc slot moved %s", slot:GetFullName())
                    end
                    arcDone[slot:GetFullName()] = true
                end
            end
        end
    end
end

-- doors and the rear hatch (BP_CarPart_Door_Base on SLOT_*Door / Slot_Trunk): slot name -> part
-- Opening only unlatches one; its mesh then swings on physics. The guest's copy stayed shut (no physics there), and the
-- host's door-state sync closed the guest's own opening 1-2 s later (hand playtest 2026-10-23).
local DOOR = "BP_CarPart_Door_Base_C"
local function doorParts(car)
    local r, list = {}, {}
    pcall(function() car:GetAttachedActors(list, true) end)
    for _, e in ipairs(list) do
        local a = e:get()
        if valid(a) and a:GetClass():GetFName():ToString() == DOOR then
            local ok, slot = pcall(function() return a.RootComponent.AttachParent:GetFName():ToString() end)
            if ok then r[slot] = a end
        end
    end
    return r
end
local doorHold = 0 -- guest: until then its own door move (sent to the host) is not overridden
local entryDoor -- host: the door a guest opened last { part, at }; shut once they are seated (the game's entry does it itself)
local doorHeld -- guest: the host's last state during the hold, applied when it ends (else a shut showed only 3 s later)
local doorRest, doorSwung = {}, {} -- guest: part address -> the mesh's shut pose on its part; parts we posed open

-- host -------------------------------------------------------------------------------------------------------------------

-- the car's door parts, kept 2 s (the 50 ms swing loop and every 250 ms sample walked its attached actors)
local doorCache, doorCacheAt, doorCacheCar = {}, -10, nil
local function doorsOf(car)
    local addr = car:GetAddress()
    local ok = doorCacheCar == addr and os.clock() - doorCacheAt < 2
    if ok then for _, d in pairs(doorCache) do if not valid(d) then ok = false; break end end end
    if not ok then doorCache, doorCacheAt, doorCacheCar = doorParts(car), os.clock(), addr end
    return doorCache
end
-- host: the parts lines of the last sample (see sample); the list of doors shut or open last time starts the swing watcher
local partLines, partCount, partsAt, partsCar = {}, 0, -1, nil
local swingUntil, lastDoorBits = 0, nil
local function swingFor(s) swingUntil = os.clock() + (s or 6) end
RegisterLoadMapPreHook(function() doorCache, doorCacheCar, partsAt, partsCar = {}, nil, -1, nil end)
-- a guest's part work (heal, damage, swap, fuel ...) is applied on the host first: a cached line would send the old state back
-- for up to 1 s and the guest's repair flickered away (guestparts "door stays repaired" broke)
net.tap = function(kind) if kind:find("^g%.parts%.") or kind:find("^g%.act%.") or kind:find("^g%.swap%.") then partsAt = -1 end end

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
    if doors ~= lastDoorBits then lastDoorBits = doors; swingFor() end
    local hb = false
    pcall(function() hb = car.VehicleController:GetParkingBrakeActive() end)
    local lines = { string.format("H\t%d\t%d\t%d\t%d\t%d", ign, cm.MyCarGearBox, cm.CarLightsOn and 1 or 0, hb and 1 or 0, doors) }
    -- the part lines (about 30 slots, ~100 UE calls) are rebuilt at 1 Hz, or at once after a UpdatedCarEquip; the H and R lines
    -- stay at the tick's rate (health, fuel and battery drift slowly: the guest sees them 1 s late at most)
    if partsAt < 0 or os.clock() - partsAt > 1 or partsCar ~= car:GetAddress() then
        local n = 0
        local pl = {}
        cont.Slots:ForEach(function(_, e)
            local slot = e:get()
            local it = itemOf(slot)
            if it then
                local name = slotName(slot)
                local h, f, b
                local m = manifestation(cm, name)
                if m then h, f, b = readPart(propComps(m)) end
                n = n + 1
                pl[#pl + 1] = string.format("P\t%s\t%s\t%s\t%s\t%s", name, archPath(it), num(h), num(f), num(b))
            end
        end)
        partLines, partCount, partsAt, partsCar = pl, n, os.clock(), car:GetAddress()
    end
    for _, l in ipairs(partLines) do lines[#lines + 1] = l end
    local n = partCount
    -- an open door's mesh simulates physics, which detaches it (its "relative" transform is then the world's): its pose
    -- goes in the car's own space
    local ct = car:GetTransform()
    for slot, d in pairs(doorsOf(car)) do
        pcall(function()
            local m = d.MainMesh
            if not m:IsSimulatingPhysics(FName("None")) then return end
            local l = kml():InverseTransformLocation(ct, m:K2_GetComponentLocation())
            local r = kml():InverseTransformRotation(ct, m:K2_GetComponentRotation())
            lines[#lines + 1] = string.format("R\t%s\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f", slot, l.X, l.Y, l.Z, r.Pitch, r.Yaw, r.Roll)
        end)
    end
    lines[#lines + 1] = "E\t" .. n
    return table.concat(lines, "\n")
end

-- host hooks (listen only): a door verb or knock starts the swing watcher, a changed car loadout rebuilds the part lines.
-- Each keeps its slow timer fallback (the 2 s swing pass, the 1 s part lines); first fires are logged as PT|probe.
local DOORBP = "/Game/Gameplay/Inventory/Items/Car/Doors/BP_CarPart_Door_Base.BP_CarPart_Door_Base_C:"
local hostHooked, probeN = false, {}
local probeOk, probeLogged = {}, {} -- hook name -> registered; -> failure logged once
local function probe(name, fn)
    if probeOk[name] then return true end
    local ok, err = pcall(RegisterHook, name, function()
        if common.netMode() ~= "listen" then return end
        probeN[name] = (probeN[name] or 0) + 1
        if probeN[name] <= 3 then log("PT|probe car hook %s n=%d", name:match("[^:/%.]+$"), probeN[name]) end
        fn()
    end)
    if not ok and not probeLogged[name] then
        probeLogged[name] = true
        log("PT|probe car hook %s not registered: %s", name:match("[^:/%.]+$"), tostring(err))
    end
    probeOk[name] = ok
    return ok
end
local function hostHooks()
    if hostHooked then return end
    -- retried until all register: on the first listen tick the Blueprint classes may not be loaded yet
    local all = true
    for _, fn in ipairs({ "AttemptOpen", "AttemptShut", "ObjectKicked", "OnConstraintBroken_Event_0" }) do
        all = probe(DOORBP .. fn, function() swingFor() end) and all
    end
    all = probe("/Game/Systems/Managers/BP_CarManager.BP_CarManager_C:UpdatedCarEquip", function() partsAt = -1 end) and all
    hostHooked = all
end

local lastSent, lastAt, lastGuests = nil, 0, 0
local arcAt = -10
local function hostTick()
    hostHooks()
    local guests = net.guests()
    if #guests == 0 then lastSent, lastGuests = nil, 0; return end
    local car, cm = theCar(true), carManager()
    if not car or not cm then return end
    if os.clock() - arcAt > 5 then arcAt = os.clock(); moveArc(car) end -- a slot is moved once
    local s = sample(car, cm)
    if not s then return end
    local t = now()
    if #guests ~= lastGuests or s ~= lastSent or t - lastAt > 3 then
        net.toGuests("g.car.s", s)
        lastSent, lastAt, lastGuests = s, t, #guests
    end
end

-- C1: seat the guest at the mirrored seat and attach it (movement and collision off on both sides)
local seated = {} -- host: guest character full name -> true while our seat() holds it (the game attaches a new character as DRIVER, playtest 2026-10-23)
local function seat(char, car)
    seated[char:GetFullName()] = true
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
    -- the guest's door stayed open and swung while driving (hand playtest 2026-10-23): no entry animation shuts it here
    local door = entryDoor and now() - entryDoor.at < 5 and entryDoor.part
    entryDoor = nil
    if door then
        ExecuteInGameThreadWithDelay(800, function() pcall(function() if valid(door) then door:AttemptShut() end end) end)
    end
    ov.post(ov.other() .. " entered the car")
end)

net.on("g.car.exit", function(pc)
    if common.netMode() ~= "listen" then return end
    local char, car = guestChar(pc), theCar(true)
    if not char or not car or not same(char:GetAttachParentActor(), car) then return end
    seated[char:GetFullName()] = nil
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
    -- The guest sends no moves while seated, so the server's forced updates move its clock for the guest on and every move
    -- after the exit was dropped for about as long as the ride (frozen on the host, 2026-10-23). Unpossess resets the
    -- server's prediction data, Possess makes the client reset its own (proven live: moves accepted at once).
    ExecuteInGameThreadWithDelay(150, function()
        local ok, e = pcall(function() if valid(pc) and valid(char) then pc:UnPossess(); pc:Possess(char) end end)
        if not ok then log("PT|error car repossess %s", tostring(e)) end
    end)
    log("PT|car guest left the car")
    ov.post(ov.other() .. " left the car")
end)

net.on("g.car.hello", function() lastSent = nil end)

-- A character spawned while the host drives is attached by the game to the DRIVER's seat (stuck there, X dropped it through the
-- ground, once launched the car; Steam playtest 2026-10-23 #3, #17). Not seated by us: move it to the passenger seat.
LoopInGameThreadWithDelay(250, function()
    if not safety.active() or common.netMode() ~= "listen" or os.getenv("PT_MUTATE") == "nozonefix" then return end
    pcall(function()
        local car = theCar(true)
        if not car then return end
        for _, pc in ipairs(net.guests()) do
            local char = guestChar(pc)
            local on = char and same(char:GetAttachParentActor(), car)
            if char and not on then seated[char:GetFullName()] = nil end -- left by any path (death, unstick, the game's exit)
            if on and not seated[char:GetFullName()] then
                log("PT|car guest attached by the game, moved to the passenger seat")
                seat(char, car)
            end
        end
    end)
end)

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
if os.getenv("PT_MUTATE") ~= "noridefree" then RegisterLoadMapPreHook(function() if riding then CancelDelayedAction(riding.loop); riding = nil end end) end
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
    -- the camera and the controls stayed with the car: camera frozen, no walking (local playtest 2026-10-22)
    local pc = localPC()
    pcall(function() pc:ResetIgnoreInputFlags() end)
    pcall(function() pc:SetIgnoreLookInput(false); pc:SetIgnoreMoveInput(false) end)
    pcall(function() pc:SetViewTargetWithBlend(me, 0, 0, 0, false) end)
    pcall(function() me:EnableInput(pc) end)
    pcall(function() StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):SetInputMode_GameOnly(pc) end)
    local okv, view = pcall(function() return pc:GetViewTarget():GetFName():ToString() end)
    log("PT|car guest placed outside at %s,%s,%s view=%s", x, y, z, okv and view or "?")
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
        -- the pawn and car of a world that was freed: reading them is an access violation pcall cannot catch (guest rejoin crash)
        if os.getenv("PT_MUTATE") ~= "noridefree" and not (valid(char) and valid(car)) then CancelDelayedAction(loop); riding = nil; return end
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
    local head, parts, count, n, swing = nil, {}, 0, nil, {}
    for line in data:gmatch("[^\n]+") do
        local f = {}
        for x in (line .. "\t"):gmatch("([^\t]*)\t") do f[#f + 1] = x end
        if f[1] == "H" then head = f
        elseif f[1] == "P" then parts[f[2]] = { arch = f[3], h = tonumber(f[4]), f = tonumber(f[5]), b = tonumber(f[6]) }; count = count + 1
        elseif f[1] == "R" then swing[f[2]] = { vec(tonumber(f[3]), tonumber(f[4]), tonumber(f[5])), { Pitch = tonumber(f[6]), Yaw = tonumber(f[7]), Roll = tonumber(f[8]) } }
        elseif f[1] == "E" then n = tonumber(f[2]) end
    end
    -- a truncated message must never look like "the host has no parts"
    if not head or n ~= count then log("PT|error car state message incomplete"); return end
    local changed = 0
    cont.Slots:ForEach(function(_, e)
        local slot = e:get()
        local name = slotName(slot)
        local want, it = parts[name], itemOf(slot)
        if M.holdSlot and M.holdSlot(name) then return end -- the guest just swapped this part itself (guestswap.lua)
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
    if now() < doorHold then doorHeld = data; return end
    doorHeld = nil
    for d = 0, 5 do
        local o = {}
        cm:GetDoorState(d, o)
        local want = (doors >> d) & 1 == 1
        if o.Open ~= want then pcall(function() cm:SetDoorState(d, want) end) end
    end
    if not car then return end
    local ct = car:GetTransform()
    for slot, part in pairs(doorParts(car)) do
        pcall(function()
            local m = part.MainMesh
            local key = part:GetAddress()
            -- the shut pose: where the mesh sits on its part before anything swung it
            if not doorRest[key] and not swing[slot] and not m:IsSimulatingPhysics(FName("None")) then
                local l, r = m.RelativeLocation, m.RelativeRotation
                doorRest[key] = { parent = m.AttachParent, loc = vec(l.X, l.Y, l.Z), rot = { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } }
            end
            local want = swing[slot]
            if want then
                if m:IsSimulatingPhysics(FName("None")) then m:SetSimulatePhysics(false) end
                m:K2_SetWorldLocationAndRotation(kml():TransformLocation(ct, want[1]), kml():TransformRotation(ct, want[2]), false, {}, true)
                doorSwung[key] = true
            elseif doorSwung[key] and doorRest[key] then
                local rest = doorRest[key]
                if m:IsSimulatingPhysics(FName("None")) then m:SetSimulatePhysics(false) end
                if valid(rest.parent) then m:K2_AttachToComponent(rest.parent, FName("None"), 0, 0, 0, false) end
                m:K2_SetRelativeLocationAndRotation(rest.loc, rest.rot, false, {}, true)
                doorSwung[key] = nil
            end
        end)
    end
end

-- guest: its own open/close of the host's car door goes to the host, which runs the same AttemptOpen on its part;
-- the result comes back with the car state
net.on("g.car.door", function(_, data)
    if common.netMode() ~= "listen" then return end
    local slot, verb = data:match("^([^|]*)|?(.*)$")
    local shut = verb == "shut"
    local car = theCar(true)
    local part = car and doorParts(car)[slot]
    if not valid(part) then log("PT|car door intent: no door at %s", tostring(slot)); return end
    pcall(function() if shut then part:AttemptShut() else part:AttemptOpen() end end)
    entryDoor = not shut and { part = part, at = now() } or nil
    log("PT|car door intent %s %s applied", slot, shut and "shut" or "open")
end)

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

local hooked, exitWanted = false, false
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
    -- shutting too: a door the host opened is posed on the guest with its physics off, so a local shut did nothing (2026-10-23)
    for fn, suffix in pairs({ AttemptOpen = "", AttemptShut = "|shut" }) do
        local okd, errd = pcall(RegisterHook, "/Game/Gameplay/Inventory/Items/Car/Doors/BP_CarPart_Door_Base.BP_CarPart_Door_Base_C:" .. fn, function(self)
            pcall(function()
                if common.netMode() ~= "client" then return end
                local part, car = self:get(), theCar(false)
                if not (valid(part) and car and same(part:GetAttachParentActor(), car)) then return end
                local slot = part.RootComponent.AttachParent:GetFName():ToString()
                -- only our own physics swing needs protecting; a door the host opened is posed here, its shut animates from the host
                if suffix == "" or part.MainMesh:IsSimulatingPhysics(FName("None")) then doorHold = now() + 1.5 end
                log("PT|car door intent %s%s sent=%s", slot, suffix, tostring(net.toHost("g.car.door", slot .. suffix)))
            end)
        end)
        if not okd then log("PT|error car hook %s %s", fn, tostring(errd)) end
    end
    hooked = true
    -- leaving: key X while seated; the key only raises a flag (an ExecuteInGameThread per press crashed UE4SS when spammed, ping.lua)
    pcall(RegisterKeyBind, Key.X, function() exitWanted = true end)
end

-- F8 on the guest: log what holds the controls, then give them back (camera and walking stayed locked after an exit,
-- local playtest 2026-10-22, cause not found yet)
local unstickWanted = false
pcall(RegisterKeyBind, Key.F8, function() unstickWanted = true end)
local function unstick()
    local pc = localPC()
    local me = pc and pc.Pawn
    if not valid(me) then return end
    local s = {}
    local function probe(k, f) local ok, v = pcall(f); s[#s + 1] = k .. "=" .. (ok and tostring(v) or "?") end
    probe("look", function() return pc:IsLookInputIgnored() end)
    probe("move", function() return pc:IsMoveInputIgnored() end)
    probe("view", function() return pc:GetViewTarget():GetFName():ToString() end)
    probe("mode", function() return me.CharacterMovement.MovementMode end)
    probe("tick", function() return me.CharacterMovement:IsComponentTickEnabled() end)
    probe("parent", function() local p = me:GetAttachParentActor(); return p:IsValid() and p:GetFName():ToString() or "none" end)
    probe("riding", function() return riding ~= nil end)
    log("PT|car unstick %s", table.concat(s, " "))
    -- the controller looked normal when stuck (2026-10-22): dump the game's own car/seat/input state on the character and its manager
    local function dump(tag, o)
        if not valid(o) then return end
        local out = {}
        pcall(function()
            local cls = o:GetClass()
            while cls and cls:IsValid() do
                cls:ForEachProperty(function(p)
                    local n = p:GetFName():ToString()
                    if n:find("Car") or n:find("Seat") or n:find("Driv") or n:find("Input") or n:find("Camera") or n:find("State") or n:find("Mode") or n:find("Lock") then
                        local ok, v = pcall(function() return o[n] end)
                        if ok and type(v) ~= "userdata" then out[#out + 1] = n .. "=" .. tostring(v)
                        elseif ok and v and v.IsValid and v:IsValid() and v.GetFName then out[#out + 1] = n .. "=" .. v:GetFName():ToString() end
                    end
                end)
                cls = cls:GetSuperStruct()
            end
        end)
        log("PT|car unstick %s %s", tag, table.concat(out, " "))
    end
    dump("char", me)
    dump("manager", FindFirstOf("BP_MainCharacterManager_C"))
    if riding and not same(me:GetAttachParentActor(), theCar(false)) then stopRide(me) end
    if not riding then
        pcall(function() me:K2_DetachFromActor(1, 1, 1) end)
        stopRide(me)
    end
    pcall(function() pc:ResetIgnoreInputFlags() end)
    pcall(function() pc:SetViewTargetWithBlend(me, 0, 0, 0, false) end)
    pcall(function() me:EnableInput(pc) end)
    pcall(function() StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):SetInputMode_GameOnly(pc) end)
end

local helloFor = nil
local function guestTick()
    if doorHeld and now() >= doorHold then
        local held = doorHeld
        doorHeld = nil
        local ok, err = pcall(applyState, held)
        if not ok then log("PT|error car apply %s", tostring(err)) end
    end
    if exitWanted then
        exitWanted = false
        if common.netMode() == "client" and riding then sendExit() end
    end
    if unstickWanted then
        unstickWanted = false
        local ok, err = pcall(unstick)
        if not ok then log("PT|error car unstick %s", tostring(err)) end
        if ok then ov.post("Controls reset", "info", "unstick") end
    end
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
        -- our own enter and exit must not run locally; they are the host's job (a local exit crashed AC_CarAudio's tick, 2026-10-23)
        if PTNative_Mute then PTNative_Mute(me:GetAddress(), "CommandEnterCar|Exit Car") end
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
-- host: while a door swings the state goes out at 20 Hz, at 4 Hz the guest saw its swing "like 3 fps" (hand playtest 2026-10-23).
-- The loop read every door's physics 20 times a second; it now works while swingUntil is ahead (set by the door hooks and by
-- a door bit change in the 4 Hz sample) and, in case a hook did not fire, once every 2 s.
local swingFallbackAt = 0
M.swingWork = 0 -- debug counter for scenarios: passes that read door physics
LoopInGameThreadWithDelay(50, function()
    if os.clock() >= swingUntil then
        if os.clock() - swingFallbackAt < 2 then return end
        swingFallbackAt = os.clock()
    end
    if common.netMode() ~= "listen" or #net.guests() == 0 then return end
    local ok, err = pcall(function()
        local car = theCar(true)
        if not car then return end
        M.swingWork = M.swingWork + 1
        for _, d in pairs(doorsOf(car)) do
            local m = valid(d) and d.MainMesh
            if m and m:IsSimulatingPhysics(FName("None")) then
                local a = m:GetPhysicsAngularVelocityInDegrees(FName("None"))
                if a.X * a.X + a.Y * a.Y + a.Z * a.Z > 25 then swingFor(2); return hostTick() end
            end
        end
    end)
    if not ok then log("PT|error car door tick %s", tostring(err)) end
end)

M.exit = sendExit
M.unstick = function() unstickWanted = true end -- guestui.lua: second key and console command
-- for guestact.lua (the guest's car work and ARC)
M.theCar, M.carManager, M.equipped, M.itemOf, M.slotName = theCar, carManager, equipped, itemOf, slotName
M.manifestation, M.propComps, M.readPart = manifestation, propComps, readPart
return M
