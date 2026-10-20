-- X4: the guest (own PDP_MainCharacter_C) uses the game's own interaction: look at an interactable, press interact.
-- Each side has its own local copy of these actors (X3). Guest: aim, check the highlight, press, check the local
-- effect. Host: check its copy, inventory and menu are unaffected, then run the same interaction itself for the
-- guest's character (host-authority model) and log where it lands. Garage: a storage container and a pickup;
-- interactzone.lua observes a zone loot container and a host-only abandoned-car door (targets with observe = true).
-- -Mutate noaim: the guest does not aim (guest_highlight_* fail); nopress: the guest does not press (guest_effect_*
-- fail); hostpress: the host presses its own copy before its check (host_unaffected_* fail).
local G = require("scenarios.guestchar")
local STEEL = "/Game/Gameplay/Inventory/Items/Resources/Basic/RawSteel/IA_Resource_Raw_Scrap_Steel.IA_Resource_Raw_Scrap_Steel"
local GARAGE = {
    { id = "storage", class = "BP_Garage_InventoryContainer_StarterStorage_C" },
    { id = "pickup", class = "BP_WorldItem_C", spawn = true },
}

return function(T, opts)
    opts = opts or { map = T.GARAGE, mapName = "RB_Garage", targets = GARAGE }
    local log, MUTATE = T.log, T.MUTATE
    local pressed = 0
    local function hook()
        RegisterHook("/Script/PenDriverPro.HighlightComponent:InteractPressed", function(self, data)
            pressed = pressed + 1
            log("PT|info InteractPressed side=%s n=%d owner=%s data=%s", T.ROLE, pressed, T.cls(self:get():GetOwner()), T.name(data:get()))
        end)
    end
    -- where to look: the first highlight collision component (GetCollisionCenter returned points metres off)
    local function center(a)
        local ok, p = pcall(function() return a.Highlight.HighlightCollision[1]:K2_GetComponentLocation() end)
        if ok and p then return p end
        return a:K2_GetActorLocation()
    end
    -- what an interactable holds: archetype x count per slot of its own container, if it has one
    local function contents(a)
        local o = {}
        local comp = T.first("InventorySystem"):FindInventoryContainerOnActor(a, o)
        if not (comp and comp:IsValid() and comp.Container:IsValid()) then return "-" end
        local c, r = comp.Container, {}
        for i = 0, c:GetNumSlots() - 1 do
            local s = c:GetSlot(i)
            if s:GetNumItems() > 0 then r[#r + 1] = s:GetCurrentArchetype():GetFName():ToString():gsub("^IA_", "") .. "x" .. s:GetNumItems() end
        end
        table.sort(r)
        return "{" .. table.concat(r, ",") .. "}"
    end
    local function state(t, a)
        local s = string.format("inv=%d menu=%s", G.invCount(T), tostring(G.menuOpen(T)))
        if t.spawn then s = s .. string.format(" item=%s hidden=%s", T.name(a.Instance), tostring(a.bHidden)) else s = s .. " holds=" .. contents(a) end
        return s
    end
    local function closeMenu() if G.menuOpen(T) then T.first("BP_InventoryManager_C"):RequestPlayerMenuClose() end end
    -- both sides spawn their own copy of the pickup next to the host's character
    local function spawnPickup(hostChar)
        local l = hostChar:K2_GetActorLocation()
        local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X + 150, Y = l.Y, Z = l.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local a = T.first("InventorySystem"):SpawnItemActor(T.world(), xf, StaticFindObject(STEEL), 0, 0)
        log("PT|info spawned pickup %s", T.name(a))
        return xf.Translation
    end

    if T.ROLE == "host" then
        local guest, ht, before, pressed0 = nil, nil, nil, 0
        local steps = {
            T.onMap("RB_MainMenu", 90),
            { wait = opts.hostDelay or 5 },
            { run = function() T.console("open " .. opts.map .. "?listen") end },
            { check = "host_listen", timeout = 180, cond = function() return T.netMode() == "listen" and T.map() == opts.mapName end },
            { check = "host_two_pcs", timeout = 180, cond = function() return T.pcs() == 2 end },
            { wait = 10 },
            { check = "host_spawned_guest", timeout = 30, cond = function() guest = G.spawnGuest(T); return guest ~= nil and guest:IsValid() end },
            { wait = 8 },
            { run = function() hook(); G.managers(T, "spawned") end },
        }
        for _, t in ipairs(opts.targets) do
            local add = function(s) steps[#steps + 1] = s end
            add({ run = function()
                local from = t.spawn and spawnPickup(T.myPawn()) or T.myPawn():K2_GetActorLocation()
                ht = G.nearest(T, t.class, from)
                before, pressed0 = ht and state(t, ht), pressed
                log("PT|info host target %s %s d=%.0f %s", t.id, T.name(ht), ht and T.dist(ht, T.myPawn()) or -1, tostring(before))
            end })
            add({ check = "host_placed_" .. t.id, timeout = 10, cond = function()
                -- the highlight trace reaches 160 uu: take the closest free spot around the aim point
                local p = center(ht)
                for _, r in ipairs({ 90, 120, 150 }) do
                    for i = 0, 7 do
                        local ang = math.rad(i * 45)
                        local to = { X = p.X + math.cos(ang) * r, Y = p.Y + math.sin(ang) * r, Z = p.Z + 20 }
                        if guest:K2_TeleportTo(to, { Pitch = 0, Yaw = i * 45 + 180, Roll = 0 }) then
                            local g = guest:K2_GetActorLocation()
                            if math.sqrt((g.X - p.X) ^ 2 + (g.Y - p.Y) ^ 2) < r + 40 then
                                log("PT|info placed guest for %s r=%d try %d", t.id, r, i)
                                return true
                            end
                        end
                    end
                end
                return false
            end })
            add({ wait = 20 })
            if t.observe then
                add({ run = function() T.survey(t.id) end })
                add({ wait = 10 })
            else
                add({ run = function()
                    if MUTATE == "hostpress" then ht.Highlight:InteractPressed(T.myPawn()); ht.Highlight:InteractReleased(T.myPawn()) end
                end })
                add({ check = "host_unaffected_" .. t.id, timeout = 2, cond = function()
                    local now = state(t, ht)
                    log("PT|info host %s after guest press: %s (before %s) presses=%d", t.id, now, before, pressed - pressed0)
                    return now == before and pressed == pressed0
                end })
                -- host authority: the host runs the game's own interaction on its copy for the guest's character
                add({ run = function()
                    before = state(t, ht)
                    if t.spawn then
                        guest["Pickup Actor"](guest, ht, false)
                    else
                        ht.Highlight:InteractPressed(guest)
                        ExecuteInGameThreadWithDelay(150, function() pcall(function() ht.Highlight:InteractReleased(guest) end) end)
                    end
                end })
                add({ wait = 4 })
                add({ run = function()
                    log("PT|hostrun %s before=%s after=%s", t.id, before, state(t, ht))
                    G.managers(T, "after-hostrun-" .. t.id)
                    closeMenu()
                end })
                add({ wait = 3 })
            end
        end
        steps[#steps + 1] = { wait = opts.hostTail or 10 }
        return steps
    end

    local me0, ga, before, seen = nil, nil, nil, {}
    local function moved()
        local l = T.myPawn():K2_GetActorLocation()
        return math.sqrt((l.X - me0.X) ^ 2 + (l.Y - me0.Y) ^ 2) >= 60, l
    end
    local function aim()
        if not ga then return end
        local p, pc = center(ga), T.localPC()
        local c = pc.PlayerCameraManager:GetCameraLocation()
        local dx, dy, dz = p.X - c.X, p.Y - c.Y, p.Z - c.Z
        pc:SetControlRotation({ Pitch = math.deg(math.atan(dz, math.sqrt(dx * dx + dy * dy))), Yaw = math.deg(math.atan(dy, dx)), Roll = 0 })
    end
    local function highlighted(t)
        if not ga then return false end
        local h = T.first("BP_HighlightManager_C").CurrentHighlight
        local o = h:IsValid() and h:GetOwner()
        log("PT|info guest highlight %s", T.name(o))
        return o and T.cls(o) == t.class and T.dist(o, ga) < 60
    end
    local steps = {
        T.onMap("RB_MainMenu", 90),
        { run = function() StaticFindObject("/Script/OnlineSubsystemUtils.Default__IpNetDriver").ResolutionConnectionTimeout = 120 end },
        T.join("client_connected", opts.mapName, 300, 30),
        { check = "client_possessed", timeout = 60, cond = function() return T.cls(T.myPawn()) == T.CHAR end },
        { wait = 5 },
        { run = function() hook(); me0 = T.myPawn():K2_GetActorLocation(); G.managers(T, "possessed") end },
    }
    for _, t in ipairs(opts.targets) do
        local add = function(s) steps[#steps + 1] = s end
        if t.spawn then add({ run = function() spawnPickup(T.otherChar()) end }) end
        if t.observe then
            -- the host placed us next to its copy: what is there on our side?
            add({ check = "guest_moved_" .. t.id, timeout = 90, cond = function() return moved() end })
            add({ wait = 3 })
            add({ run = function()
                local a, d = G.nearest(T, t.class, T.myPawn():K2_GetActorLocation())
                log("PT|observe side=client %s nearest=%s d=%.0f", t.id, T.name(a), d)
                me0 = T.myPawn():K2_GetActorLocation()
                T.survey(t.id)
            end })
        else
            add({ check = "guest_near_" .. t.id, timeout = 90, cond = function()
                local ok, l = moved()
                if not ok then return false end
                local a, d = G.nearest(T, t.class, l)
                if a and d < 400 then ga = a; return true end
                if not seen[t.id] then seen[t.id] = true; log("PT|info guest moved, nearest %s %s d=%.0f me=%.0f,%.0f,%.0f", t.id, T.name(a), d, l.X, l.Y, l.Z) end
                return false
            end })
            add({ wait = 2 })
            add({ run = function()
                me0 = T.myPawn():K2_GetActorLocation()
                if MUTATE ~= "noaim" then aim() end
                log("PT|info guest target %s %s d=%.0f %s", t.id, T.name(ga), T.dist(T.myPawn(), ga), state(t, ga))
            end })
            add({ check = "guest_highlight_" .. t.id, timeout = 8, cond = function() return highlighted(t) end,
                  tick = function() if MUTATE ~= "noaim" then aim() end end })
            add({ run = function()
                before = state(t, ga)
                if MUTATE == "nopress" then return end
                local me = T.myPawn()
                me["Command Interact"](me, true)
                ExecuteInGameThreadWithDelay(150, function() pcall(function() me["Command Interact"](me, false) end) end)
            end })
            add({ check = "guest_effect_" .. t.id, timeout = 6, cond = function()
                local now = state(t, ga)
                if now ~= before then log("PT|info guest %s effect: %s -> %s", t.id, before, now) end
                return now ~= before
            end })
            add({ run = function() G.managers(T, "after-" .. t.id); closeMenu() end })
        end
    end
    return steps
end
