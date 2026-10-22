-- P1 hands: what the other player holds and does with it. The game is first person: a held item is a hand manifestation actor
-- (BP_BaseHandManifestation_C, local to each process, drawn on the first-person arms), so nothing of it reaches the other player's
-- view of the character. Each side reports its own hand (item mesh, size, toggle state) and tool use; the other side mirrors it
-- on the character it has of us: a local StaticMeshActor on the hand_r bone (large items in front of the chest), a spot light
-- for an "on" flashlight, a swing of the item on use. Nothing replicates, nothing exists outside a session (Q7).
-- The mannequin skeleton has no tool animation (only ALS turn and get-up montages), so the swing is procedural.
local UEHelpers = require("UEHelpers")
local common = require("common")
local safety = require("safety")
local net = require("net")
local log = common.log

local M = {}
if os.getenv("PT_MUTATE") == "nohands" then return M end

local CHAR = "PDP_MainCharacter_C"
local SWING_S = 0.45
local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function path(o) return valid(o) and (o:GetFullName():match("^%S+ (.+)$")) or nil end

-- ours ----------------------------------------------------------------------------------------------------------------

local function ownChar()
    local pc = UEHelpers.GetPlayerController()
    local p = valid(pc) and pc.Pawn
    if valid(p) and p:GetClass():GetFName():ToString() == CHAR then return p end
    local cm = FindFirstOf("BP_MainCharacterManager_C")
    return valid(cm) and valid(cm.CharacterActor) and cm.CharacterActor or nil
end

local SMC, SKC = StaticFindObject("/Script/Engine.StaticMeshComponent"), StaticFindObject("/Script/Engine.SkeletalMeshComponent")
local SCENE, LIGHT = StaticFindObject("/Script/Engine.SceneComponent"), StaticFindObject("/Script/Engine.LightComponent")

-- the mesh the item shows in the hand: the manifestation's CurrentItemMesh (items), else its biggest visible static mesh (tools)
local function heldMesh(h)
    local cim = h.CurrentItemMesh
    if valid(cim) and valid(cim:GetStaticMesh()) then return cim:GetStaticMesh() end
    local best, size = nil, -1
    for _, c in ipairs(h:K2_GetComponentsByClass(SMC)) do
        c = c:get()
        local sm = valid(c) and c:GetStaticMesh()
        if valid(sm) then
            local e = sm:GetBounds().SphereRadius
            if e > size then best, size = sm, e end
        end
    end
    return best
end

-- "<archetype>|<mesh>|<size>|<light 0/1>|<light kind>"; "" for an empty hand
local function localState()
    local c = ownChar()
    if not c then return "" end
    local o = {}
    c:GetActiveHandItem(false, o)
    local h = o["Hand Item"]
    if not valid(h) or not valid(h.Instance) then return "" end
    local arch = h.Instance.Archetype
    local mesh = heldMesh(h)
    local on, kind = 0, "none"
    local ok, v = pcall(function() return h.IsOn end)
    if ok and v == true then on = 1 end
    if h:K2_GetComponentsByClass(LIGHT)[1] then kind = h:GetClass():GetFName():ToString():find("Camping", 1, true) and "point" or "spot" end
    return string.format("%s|%s|%d|%d|%s", valid(arch) and arch:GetFName():ToString() or "?", path(mesh) or "", arch.Size or 0, on, kind)
end

-- theirs ----------------------------------------------------------------------------------------------------------------

local remote = { state = "", at = 0 } -- last report from the other player
local mirrors = {}                    -- character full name -> { actor, state, light, swingAt }

local function otherChars()
    local list, me = {}, ownChar()
    local wn = UEHelpers.GetWorld():GetFullName()
    for _, c in ipairs(FindAllOf(CHAR) or {}) do
        if valid(c) and c:GetWorld():GetFullName() == wn and not (valid(me) and c:GetFullName() == me:GetFullName()) then list[#list + 1] = c end
    end
    return list
end

local function spawn(char, class)
    local gs = UEHelpers.GetGameplayStatics()
    local l = char:K2_GetActorLocation()
    local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X, Y = l.Y, Z = l.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    return gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(char, StaticFindObject(class), xf, 1, nil), xf)
end

local function dropMirror(key)
    local m = mirrors[key]
    if not m then return end
    if valid(m.actor) then m.actor:K2_DestroyActor() end
    if valid(m.light) then m.light:K2_DestroyActor() end
    mirrors[key] = nil
end

local function loadMesh(p)
    local m = StaticFindObject(p)
    if not valid(m) then pcall(LoadAsset, p); m = StaticFindObject(p) end
    return valid(m) and m or nil
end

local function build(char, st)
    local arch, mesh, size, on, kind = st:match("^([^|]*)|([^|]*)|(%d+)|(%d)|(%a+)$")
    local m = { state = st, arch = arch, size = tonumber(size), on = on == "1", kind = kind, swingAt = nil }
    local sm = mesh ~= "" and loadMesh(mesh)
    if sm then
        local a = spawn(char, "/Script/Engine.StaticMeshActor")
        local comp = a.StaticMeshComponent
        comp:SetMobility(2)
        comp:SetStaticMesh(sm)
        comp:SetCollisionEnabled(0)
        comp:SetCastShadow(false)
        -- large items: both hands, in front of the chest (the mannequin has no carry animation); the rest in the right hand
        if m.size == 1 then
            a:K2_AttachToComponent(char.Mesh, FName("spine_03"), 0, 0, 0, false)
            a:K2_SetActorRelativeLocation({ X = 0, Y = 35, Z = 0 }, false, {}, true)
        else
            a:K2_AttachToComponent(char.Mesh, FName("hand_r"), 0, 0, 0, false)
        end
        m.actor = a
        m.rest = a:K2_GetActorLocation()
    end
    if m.on then
        local a = spawn(char, m.kind == "point" and "/Script/Engine.PointLight" or "/Script/Engine.SpotLight")
        local lc = a.LightComponent
        lc:SetMobility(2)
        lc:SetIntensity(m.kind == "point" and 2000 or 8000)
        if m.kind ~= "point" then lc:SetOuterConeAngle(30); lc:SetAttenuationRadius(1500) end
        m.light = a
    end
    return m
end

local function swing(m)
    if not (m.swingAt and valid(m.actor)) then return end
    local t = (os.clock() - m.swingAt) / SWING_S
    if t >= 1 then
        m.swingAt = nil
        m.actor:K2_SetActorRelativeRotation({ Pitch = 0, Yaw = 0, Roll = 0 }, false, {}, true)
        return
    end
    m.actor:K2_SetActorRelativeRotation({ Pitch = -70 * math.sin(t * math.pi), Yaw = 0, Roll = 0 }, false, {}, true)
end

local function follow(char, m)
    if valid(m.light) then
        local head = char.Mesh:GetSocketLocation(FName("head"))
        local aim = char:GetBaseAimRotation()
        local f = UEHelpers.GetKismetMathLibrary():GetForwardVector(aim)
        m.light:K2_SetActorLocationAndRotation({ X = head.X + f.X * 30, Y = head.Y + f.Y * 30, Z = head.Z + f.Z * 30 }, aim, false, {}, true)
    end
    swing(m)
end

local nextScan, others = 0, {}
local function update()
    if not safety.active() then
        for k in pairs(mirrors) do dropMirror(k) end
        remote = { state = "", at = 0 }
        return
    end
    if os.time() >= nextScan then nextScan = os.time() + 2; others = otherChars() end
    local seen = {}
    for _, c in ipairs(others) do
        if valid(c) then
            local key = c:GetFullName()
            seen[key] = true
            local m = mirrors[key]
            if remote.state == "" then
                if m then dropMirror(key) end
            else
                if m and m.state ~= remote.state then
                    local at = m.swingAt
                    dropMirror(key)
                    m = nil
                end
                if not m then m = build(c, remote.state); mirrors[key] = m; log("PT|hands mirror %s %s", key:match("[^.]+$"), remote.state) end
                if remote.useAt and m.useSeen ~= remote.useAt then m.useSeen, m.swingAt = remote.useAt, os.clock() end
                follow(c, m)
            end
        end
    end
    for key in pairs(mirrors) do if not seen[key] then dropMirror(key) end end
end

-- state reports and tool use ---------------------------------------------------------------------------------------------

local lastSent, lastAt = nil, 0
local function send(kind, data)
    if safety.guest() then net.toHost(kind, data) else net.toGuests(kind, data) end
end

local function report()
    if not safety.active() then lastSent = nil; return end
    local s = localState()
    -- on change, else every 3 s so a late joiner and a missed message catch up
    if s ~= lastSent or os.time() - lastAt >= 3 then
        lastSent, lastAt = s, os.time()
        send("g.hands.s", s)
    end
end

net.on("g.hands.s", function(_, data) remote.state, remote.at = data, os.time() end)
net.on("g.hands.use", function() remote.useAt = os.clock() end)

local useHooked = false
local function hookUse()
    useHooked = pcall(RegisterHook, "/Game/Gameplay/Inventory/BaseItems/Hand/BP_BaseHandManifestation.BP_BaseHandManifestation_C:PrimaryUsePress", function()
        if safety.active() then send("g.hands.use", "") end
    end)
end

-- a map change frees every object we hold
RegisterLoadMapPreHook(function() mirrors, others, nextScan, remote = {}, {}, 0, { state = "", at = 0 } end)

LoopInGameThreadWithDelay(100, function()
    local ok, err = pcall(function()
        if not useHooked then hookUse() end
        report()
        update()
    end)
    if not ok then log("PT|error hands %s", tostring(err)) end
end)

return M
