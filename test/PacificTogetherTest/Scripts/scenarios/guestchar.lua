-- Shared by the X4/X12 scenarios (not a scenario itself): guest character and single-reference manager helpers.
local UEHelpers = require("UEHelpers")
local M = {}

-- host: spawn a PDP_MainCharacter_C for every remote PC and possess it (body scenario); keep the manager on the host's
function M.spawnGuest(T)
    local hostChar, guest = T.myPawn(), nil
    assert(hostChar and T.cls(hostChar) == T.CHAR, "host pawn " .. T.cls(hostChar))
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        -- a PC whose guest left stays findable until GC: only PCs with a live connection and no character yet
        if T.inWorld(pc) and not pc:IsLocalController() and pc.Player:IsValid() and T.cls(pc.Pawn) ~= T.CHAR then
            local cm = T.first("BP_MainCharacterManager_C")
            local before = cm.CharacterActor
            local l = hostChar:K2_GetActorLocation()
            local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X, Y = l.Y + 600, Z = l.Z + 60 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
            local gs = UEHelpers.GetGameplayStatics()
            local a = gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(T.world(), hostChar:GetClass(), xf, 2, nil), xf)
            local flipped = cm.CharacterActor:GetFullName() ~= before:GetFullName()
            pc:Possess(a)
            if before:IsValid() and cm.CharacterActor:GetFullName() ~= before:GetFullName() then cm.CharacterActor = before end
            guest = a
            T.log("PT|info spawned %s for %s managerFlippedOnSpawn=%s", T.name(a), T.name(pc), tostring(flipped))
        end
    end
    return guest
end

-- which character / car / highlight view each single-reference manager points at, on this side
function M.managers(T, tag)
    local cm, car, hm = T.first("BP_MainCharacterManager_C"), T.first("BP_CarManager_C"), T.first("BP_HighlightManager_C")
    local me, other = T.myPawn(), T.otherChar()
    local function who(a)
        if not (a and a:IsValid()) then return "none" end
        if me and a:GetFullName() == me:GetFullName() then return "own" end
        if other and a:GetFullName() == other:GetFullName() then return "other" end
        return T.name(a)
    end
    local pov, cam = hm.CurrentTracePOV.Location, T.localPC().PlayerCameraManager:GetCameraLocation()
    T.log("PT|managers side=%s tag=%s CharacterActor=%s NewCarActor=%s(role=%s) highlightPOV-ownCam=%.0f highlight=%s",
        T.ROLE, tag, who(cm.CharacterActor), T.name(car.NewCarActor), car.NewCarActor:IsValid() and tostring(car.NewCarActor.Role) or "-",
        math.sqrt((pov.X - cam.X) ^ 2 + (pov.Y - cam.Y) ^ 2 + (pov.Z - cam.Z) ^ 2), T.name(hm.CurrentHighlight:IsValid() and hm.CurrentHighlight:GetOwner() or nil))
end

-- remote connections on the host's NetDriver (PC counts include PCs of guests who left, until GC)
function M.clients(T)
    local d = T.world().NetDriver
    return d:IsValid() and #d.ClientConnections or 0
end

-- before any host map change: a second character in the world crashes BeginTearingDown (0x20, PDCoopNet exp13)
function M.destroyGuests(T)
    local me, n = T.myPawn(), 0
    for _, c in ipairs(FindAllOf(T.CHAR) or {}) do
        if T.inWorld(c) and not (me and c:GetFullName() == me:GetFullName()) then c:K2_DestroyActor(); n = n + 1 end
    end
    T.log("PT|info destroyed %d guest characters", n)
end

-- items in the player's backpack + hand on this side
function M.invCount(T)
    local im = T.first("BP_InventoryManager_C")
    return im.Inventory_Player:GetNumItems() + im.Inventory_PlayerHand:GetNumItems()
end

function M.menuOpen(T)
    local o = {}
    T.first("BP_InventoryManager_C"):IsPlayerMenuOpen(o, {})
    return o.IsOpen == true
end

-- nearest interactable of a class to a point: owners of highlight components (FindAllOf by class name misses some)
function M.nearest(T, class, p)
    local best, bd
    for _, c in ipairs(FindAllOf("HighlightComponent") or {}) do
        local a = c:IsValid() and c:GetOwner()
        if a and a:IsValid() and T.inWorld(a) and T.cls(a) == class then
            local q = a:K2_GetActorLocation()
            local d = math.sqrt((q.X - p.X) ^ 2 + (q.Y - p.Y) ^ 2 + (q.Z - p.Z) ^ 2)
            if not bd or d < bd then best, bd = a, d end
        end
    end
    return best, bd or math.huge
end

return M
