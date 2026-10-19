-- D19 + D17 probe (docs/research/tourists.md, arc-marker.md). Host in the garage spawns a guest character and a
-- Tourist (BP_Hazard_Landmine_C). Checks the game's own view test (camera 0 only), the guest's camera as the host
-- sees it, a CreepCheck post-hook that counts the guest's view, and a map icon added to the other player.
-- Mutations: noguestview (host never turns the guest), nohook (hook counts but never overrides), nomarker.
local MINE = "/Game/Gameplay/Hazards/Landmine/BP_Hazard_Landmine.BP_Hazard_Landmine_C"
local ICON = "/Script/MinimapPlugin.MapIconComponent"
local UEHelpers = require("UEHelpers")

return function(T)
    local M = T.MUTATE

    local function wrap(a) a = a % 360; return a > 180 and a - 360 or a end
    local function fwd(r)
        local p, y = math.rad(r.Pitch), math.rad(r.Yaw)
        return { X = math.cos(p) * math.cos(y), Y = math.cos(p) * math.sin(y), Z = math.sin(p) }
    end
    -- the game's test (CreepCheck): within 2000 uu of the camera and dot(camera->mine, camera forward) > 0.3 = seen
    local function sees(loc, rot, target)
        local d = { X = target.X - loc.X, Y = target.Y - loc.Y, Z = target.Z - loc.Z }
        local len = math.sqrt(d.X ^ 2 + d.Y ^ 2 + d.Z ^ 2)
        if len > 2000 or len < 1 then return false, len, 0 end
        local f = fwd(rot)
        local dot = (d.X * f.X + d.Y * f.Y + d.Z * f.Z) / len
        return dot > 0.3, len, dot
    end
    local function remotePCs()
        local r = {}
        for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
            if T.inWorld(pc) and not pc:IsLocalController() then table.insert(r, pc) end
        end
        return r
    end
    local function couldCreep(m) local out = {}; m:CreepCheck(out); return out.CouldCreep end

    -- D17: a map icon on the other player's character, styled like the car's icon
    local function addMarker(char)
        local car
        for _, c in ipairs(FindAllOf("BP_PlayerCarNew_C") or {}) do if T.inWorld(c) and c.MapIcon:IsValid() then car = c; break end end
        local cls = StaticFindObject(ICON)
        local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local icon = char:AddComponentByClass(cls, false, xf, false)
        if car then
            local s = car.MapIcon
            icon.IconTexture, icon.IconMaterial_UMG, icon.IconMaterial_Canvas = s.IconTexture, s.IconMaterial_UMG, s.IconMaterial_Canvas
            icon:SetIconSize(s.IconSize, s.IconSizeUnit)
            icon:SetIconZOrder(s.IconZOrder + 1)
        end
        icon:SetIconDrawColor({ R = 0.2, G = 0.8, B = 1.0, A = 1.0 })
        icon:SetIconVisible(true)
        T.log("PT|info marker added %s car=%s carIcon=%s", T.name(icon), T.name(car), car and T.name(car.MapIcon) or "none")
        return icon
    end
    local function trackerHas(icon)
        local lib = StaticFindObject("/Script/MinimapPlugin.Default__MapFunctionLibrary")
        local tr = lib:GetMapTracker(T.world())
        if not tr:IsValid() then T.log("PT|info no map tracker"); return false end
        local n, found, car = 0, false, false
        local want = icon and icon:IsValid() and icon:GetFullName() or "?"
        -- UE4SS hands a returned TArray to Lua as a table of wrapped elements
        for _, e in ipairs(tr:GetMapIcons() or {}) do
            n = n + 1
            local ok, v = pcall(function() return e:get() end)
            local ic = ok and v or e
            local fn = ic:GetFullName()
            if fn == want then found = true end
            if fn:find("BP_PlayerCarNew_C") then car = true end
        end
        T.log("PT|info tracker %s icons=%d hasCarIcon=%s hasMarker=%s", T.name(tr), n, tostring(car), tostring(found))
        return found
    end
    local marker, idle
    local markerStep = { check = T.ROLE .. "_marker_registered", timeout = 20, cond = function()
        local o = T.otherChar()
        if not o then return false end
        if not marker and M ~= "nomarker" then marker = addMarker(o) end
        return trackerHas(marker)
    end }

    if T.ROLE ~= "host" then
        return {
            T.onMap("RB_MainMenu", 90),
            T.join("client_connected_garage", "RB_Garage", 210, 30),
            { check = "client_possessed", timeout = 60, cond = function() return T.cls(T.myPawn()) == T.CHAR end },
            { wait = 5 },
            markerStep,
            { run = function() idle = os.time() end },
            -- stay connected while the host runs the Tourist checks; log our own camera for comparison
            { check = "client_stayed", timeout = 200, cond = function() return os.time() - idle >= 150 end, tick = function(t)
                if t % 10 == 0 then
                    local pcm = T.localPC().PlayerCameraManager
                    local r, l = pcm:GetCameraRotation(), pcm:GetCameraLocation()
                    T.log("PT|info guest own camera yaw=%.1f pitch=%.1f loc=%.0f,%.0f,%.0f", r.Yaw, r.Pitch, l.X, l.Y, l.Z)
                end
            end },
        }
    end

    local guestPC, guest, mine, start, want
    local hook = { calls = 0, overrides = 0 }
    local function guestView()
        local pcm = guestPC.PlayerCameraManager
        return pcm:GetCameraLocation(), pcm:GetCameraRotation()
    end
    local function turnGuest(yaw) guestPC:ClientSetRotation({ Pitch = 0, Yaw = yaw, Roll = 0 }, false) end
    local function setHostYaw(yaw) T.localPC():SetControlRotation({ Pitch = 0, Yaw = yaw, Roll = 0 }) end
    local function mineLoc() return mine.Body:K2_GetComponentLocation() end
    local function moved() local l = mine:K2_GetActorLocation(); return math.sqrt((l.X - start.X) ^ 2 + (l.Y - start.Y) ^ 2) end

    local frozenSince
    return {
        T.onMap("RB_MainMenu", 90),
        { wait = 5 },
        { run = function() T.console("open " .. T.GARAGE .. "?listen") end },
        { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
        { check = "host_two_pcs", timeout = 180, cond = function() return T.pcs() == 2 end },
        { wait = 10 },
        { check = "host_spawned_guest", timeout = 30, cond = function()
            local hostChar = T.myPawn()
            guestPC = remotePCs()[1]
            if not hostChar or not guestPC then return false end
            local cm = T.first("BP_MainCharacterManager_C")
            local before = cm and cm.CharacterActor
            local l = hostChar:K2_GetActorLocation()
            local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X, Y = l.Y + 600, Z = l.Z + 60 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
            local gs = UEHelpers.GetGameplayStatics()
            guest = gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(T.world(), hostChar:GetClass(), xf, 2, nil), xf)
            guestPC:Possess(guest)
            if cm and before and before:IsValid() and cm.CharacterActor:GetFullName() ~= before:GetFullName() then cm.CharacterActor = before end
            return guest:IsValid() and guestPC.Pawn:IsValid() and guestPC.Pawn:GetFullName() == guest:GetFullName()
        end },
        { wait = 8 },
        { check = "host_spawned_tourist", timeout = 20, cond = function()
            local cls = StaticFindObject(MINE)
            if not cls:IsValid() then LoadAsset(MINE); cls = StaticFindObject(MINE) end
            T.log("PT|info tourist class %s", T.name(cls))
            if not cls:IsValid() then return false end
            setHostYaw(0)
            local l = T.myPawn():K2_GetActorLocation()
            local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X - 800, Y = l.Y, Z = l.Z - 80 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
            local gs = UEHelpers.GetGameplayStatics()
            mine = gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(T.world(), cls, xf, 2, nil), xf)
            T.log("PT|info tourist %s at %.0f,%.0f,%.0f host %.0f,%.0f,%.0f guest d=%.0f", T.name(mine), xf.Translation.X, xf.Translation.Y, xf.Translation.Z, l.X, l.Y, l.Z, T.dist(guest, mine))
            return mine:IsValid()
        end },
        { wait = 3 },
        -- the game's own test, called from Lua: host faces +X, the Tourist is 800 uu behind it
        { check = "creepcheck_true_when_host_looks_away", timeout = 10, cond = function()
            local pcm = T.localPC().PlayerCameraManager
            local s, len, dot = sees(pcm:GetCameraLocation(), pcm:GetCameraRotation(), mineLoc())
            T.log("PT|info host view seen=%s d=%.0f dot=%.2f creep=%s", tostring(s), len, dot, tostring(couldCreep(mine)))
            return couldCreep(mine) == true
        end },
        { run = function() setHostYaw(180) end },
        { check = "creepcheck_false_when_host_looks", timeout = 10, cond = function() return couldCreep(mine) == false end },
        { run = function()
            setHostYaw(0)
            local g, m = guest:K2_GetActorLocation(), mineLoc()
            want = math.deg(math.atan(m.Y - g.Y, m.X - g.X))
            if M ~= "noguestview" then turnGuest(want) end
            T.log("PT|info turning guest to yaw=%.1f", want)
        end },
        -- the guest's camera reaches the host's copy of its PlayerCameraManager (ServerUpdateCamera)
        { check = "guest_camera_on_host", timeout = 15, cond = function()
            local l, r = guestView()
            local aim = guest:GetBaseAimRotation()
            local s, len, dot = sees(l, r, mineLoc())
            T.log("PT|info guest cam on host yaw=%.1f want=%.1f aimYaw=%.1f loc=%.0f,%.0f,%.0f sees=%s d=%.0f dot=%.2f", r.Yaw, want, aim.Yaw, l.X, l.Y, l.Z, tostring(s), len, dot)
            return math.abs(wrap(r.Yaw - want)) < 5 and s
        end },
        { run = function()
            RegisterHook(MINE .. ":CreepCheck", function(self, could)
                hook.calls = hook.calls + 1
                if M == "nohook" or not could:get() then return end
                local m = self:get()
                for _, pc in ipairs(remotePCs()) do
                    local pcm = pc.PlayerCameraManager
                    if pcm:IsValid() and sees(pcm:GetCameraLocation(), pcm:GetCameraRotation(), m.Body:K2_GetComponentLocation()) then
                        could:set(false); hook.overrides = hook.overrides + 1; return
                    end
                end
            end)
            T.log("PT|info CreepCheck hook installed; Lua-called CreepCheck now -> %s (calls=%d)", tostring(couldCreep(mine)), hook.calls)
            start = mine:K2_GetActorLocation()
            mine.Creep = true
            mine.CreepedToCamera = false
            mine:StartCreepTimer()
            frozenSince = os.time()
        end },
        -- host looks away, the guest looks at it: the game's 0.2 s timer runs CreepCheck, our hook says "seen"
        { check = "tourist_frozen_while_guest_looks", timeout = 14, cond = function()
            if moved() > 20 then frozenSince = math.huge end
            return os.time() - frozenSince >= 8 and hook.calls >= 10
        end, tick = function(t) T.log("PT|info frozen t=%d moved=%.0f calls=%d overrides=%d", t, moved(), hook.calls, hook.overrides) end },
        { run = function() turnGuest(wrap(want + 180)) end },
        -- control: nobody looks, so it must creep (shows the frozen check could fail)
        { check = "tourist_creeps_when_nobody_looks", timeout = 20, cond = function() return moved() > 20 end,
          tick = function(t) T.log("PT|info unseen t=%d moved=%.0f calls=%d overrides=%d", t, moved(), hook.calls, hook.overrides) end },
        markerStep,
        { wait = 5 },
    }
end
