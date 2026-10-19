-- X13 look check with the real mod (needs rendering, run without -Headless): the guest auto-joins, the host puts the
-- guest 300 uu in front of its camera, both sides screenshot the other player's body and log its materials.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local function mats(c)
        local r = {}
        for i = 0, c.Mesh:GetNumMaterials() - 1 do r[#r + 1] = T.name(c.Mesh:GetMaterial(i)) end
        local ok, d = pcall(function()
            local s, sk = {}, c.Mesh.SkeletalMesh
            for i = 1, #sk.Materials do s[#s + 1] = T.name(sk.Materials[i].MaterialInterface) end
            return table.concat(s, "|")
        end)
        return table.concat(r, "|") .. " meshDefaults=" .. (ok and d or ("err " .. tostring(d)))
    end
    if T.ROLE == "host" then
        local g
        return {
            T.onMap("RB_MainMenu", 90),
            { wait = 5 },
            { run = function() T.console("open " .. T.GARAGE) end },
            { check = "host_guest_possessed", timeout = 300, cond = function() g = L.guestChar(); return g ~= nil end },
            { wait = 5 },
            { check = "host_placed_guest", timeout = 10, cond = function()
                local pc = T.localPC()
                local cam = pc.PlayerCameraManager
                local cl, yaw = cam:GetCameraLocation(), cam:GetCameraRotation().Yaw
                for i = 0, 3 do
                    local y = yaw + 90 * i
                    local to = { X = cl.X + math.cos(math.rad(y)) * 300, Y = cl.Y + math.sin(math.rad(y)) * 300, Z = T.myPawn():K2_GetActorLocation().Z }
                    if g:K2_TeleportTo(to, { Pitch = 0, Yaw = y + 180, Roll = 0 }) then
                        if i > 0 then pc:SetControlRotation({ Pitch = 0, Yaw = y, Roll = 0 }) end
                        return true
                    end
                end
                return false
            end },
            { wait = 4 },
            { run = function() T.log("PT|info guest mats %s; own %s", mats(g), mats(L.own())); T.shot("guest") end },
            { wait = 15 },
        }
    end
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_possessed", timeout = 300, cond = function() return T.cls(T.myPawn()) == T.CHAR end },
        { check = "client_placed", timeout = 60, cond = function() local o = T.otherChar(); return o ~= nil and T.dist(T.myPawn(), o) < 400 end },
        { wait = 4 },
        { run = function()
            local me, o = T.myPawn(), T.otherChar()
            T.localPC():SetControlRotation({ Pitch = 0, Yaw = T.yawTo(me, o), Roll = 0 })
        end },
        { wait = 2 },
        { run = function() T.log("PT|info host mats %s; own %s", mats(T.otherChar()), mats(T.myPawn())); T.shot("host") end },
        { wait = 10 },
    }
end
