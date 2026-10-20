-- P7: the shipping name tag. The host gives the guest a character 300 uu in front of it; each side must show a tag with
-- the other's PlayerState name on the other's character (never on its own), full strength near, faded in between
-- (NEAR 1500, FAR 5000) and hidden at 6000. -Mutate nosession: the guest never joins, so no tag may exist and the
-- tag checks FAIL. -Mutate shot: screenshots at each distance (run without -Headless).
return function(T)
    local L = require("scenarios.safety_lib")
    local alone = T.MUTATE == "nosession"
    local function tagCheck(id, wantAlpha)
        return { check = id, timeout = 6, cond = function()
            local o = T.otherChar()
            local tags = o and L.tagsOn(T, o) or {}
            local own = L.tagsOn(T, T.myPawn())
            local s = tags[1] and L.tagState(T, tags[1])
            -- what the fade should be at the tag's real distance from our camera (NEAR 1500, FAR 5000 in nametag.lua)
            local cl, tl = T.localPC().PlayerCameraManager:GetCameraLocation(), tags[1] and tags[1]:K2_GetActorLocation()
            local cd = tl and math.sqrt((cl.X - tl.X) ^ 2 + (cl.Y - tl.Y) ^ 2 + (cl.Z - tl.Z) ^ 2) or -1
            local want = math.floor(math.max(0, math.min(1, (5000 - cd) / 3500)) * 255 + 0.5)
            local name = o and o.PlayerState:IsValid() and o.PlayerState:GetPlayerName():ToString() or "?"
            T.log("PT|info tag %s n=%d own=%d text='%s' name='%s' alpha=%s want=%d hidden=%s mat=%s camd=%.0f", id, #tags, #own, s and s.text or "-", name,
                s and tostring(s.alpha) or "-", want, s and tostring(s.hidden) or "-", s and s.mat or "-", cd)
            if T.MUTATE == "shot" then T.shot(id) end
            return #tags == 1 and #own == 0 and s.text == name and name ~= "" and math.abs(s.alpha - want) <= 13 and wantAlpha(s.alpha, s.hidden)
        end }
    end
    local near = function(a, hidden) return a == 255 and not hidden end
    local mid = function(a, hidden) return a > 0 and a < 255 and not hidden end
    local far = function(a, hidden) return hidden end
    if T.ROLE == "host" then
        local guest
        -- the host moves the guest's character (authority) to d uu in front of its camera
        local function place(d)
            return { run = function()
                local pc, me = T.localPC(), T.myPawn()
                local cam = pc.PlayerCameraManager
                local cl, yaw = cam:GetCameraLocation(), cam:GetCameraRotation().Yaw
                -- walls: try four directions until the teleport finds room, then look at the guest
                for i = 0, 3 do
                    local y = yaw + 90 * i
                    local to = { X = cl.X + math.cos(math.rad(y)) * d, Y = cl.Y + math.sin(math.rad(y)) * d, Z = me:K2_GetActorLocation().Z }
                    if guest:K2_TeleportTo(to, { Pitch = 0, Yaw = y + 180, Roll = 0 }) then
                        pc:SetControlRotation({ Pitch = 0, Yaw = y, Roll = 0 })
                        T.log("PT|info place guest d=%d yaw=%.0f (try %d) dist=%.0f", d, y, i, T.dist(me, guest))
                        return
                    end
                end
                T.log("PT|info place guest d=%d: no room", d)
            end }
        end
        local steps = {
            T.onMap("RB_MainMenu", 90),
            { wait = 5 },
            { run = function() T.console("open " .. T.GARAGE .. "?listen") end },
            { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
        }
        if alone then
            steps[#steps + 1] = { wait = 20 }
            steps[#steps + 1] = { check = "host_no_tags_alone", timeout = 2, cond = function() return #L.tagsOn(T) == 0 end }
            steps[#steps + 1] = { check = "host_tag_near", timeout = 2, cond = function() return #L.tagsOn(T) == 1 end }
            return steps
        end
        for _, s in ipairs({
            { check = "host_two_pcs", timeout = 180, cond = function() return T.pcs() == 2 end },
            { wait = 10 },
            { check = "host_spawned_guest", timeout = 30, cond = function()
                local hostChar = T.myPawn()
                for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
                    if T.inWorld(pc) and not pc:IsLocalController() then
                        local cm = T.first("BP_MainCharacterManager_C")
                        local before = cm and cm.CharacterActor
                        local l = hostChar:K2_GetActorLocation()
                        local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X, Y = l.Y + 600, Z = l.Z + 60 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
                        local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
                        guest = gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(T.world(), hostChar:GetClass(), xf, 2, nil), xf)
                        pc:Possess(guest)
                        if cm and before and before:IsValid() then cm.CharacterActor = before end
                    end
                end
                return guest ~= nil and guest:IsValid()
            end },
            { wait = 5 },
            place(300), { wait = 3 }, tagCheck("host_tag_near", near),
            place(2800), { wait = 3 }, tagCheck("host_tag_mid", mid),
            place(6000), { wait = 3 }, tagCheck("host_tag_far", far),
            place(300), { wait = 3 }, tagCheck("host_tag_back", near),
            -- the guest checks the host's tag while it stands near
            { wait = 20 },
        }) do steps[#steps + 1] = s end
        return steps
    end
    if alone then return { T.onMap("RB_MainMenu", 90), { wait = 60 } } end
    return {
        T.onMap("RB_MainMenu", 90),
        T.join("client_connected_garage", "RB_Garage", 210, 30),
        { check = "client_possessed", timeout = 60, cond = function() return T.cls(T.myPawn()) == T.CHAR end },
        -- the host puts us near, far and near again (3 s each phase); check while near the first time
        { check = "client_near_host", timeout = 30, cond = function() local o = T.otherChar(); return o and T.dist(T.myPawn(), o) < 500 end },
        { wait = 2 },
        tagCheck("client_tag_on_host", near),
    }
end
