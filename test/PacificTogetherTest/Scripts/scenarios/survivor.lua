-- pt4-model survivor: the other player's body is the Rogue (survivor.lua), on both sides. Fixture-less garage, the guest joins by itself.
--   other_has_parts      the other character has a survivor part attached to each of the 17 bones with geometry (torso merged into pelvis and spine_03), visible
--   other_mannequin_invisible  its own mesh keeps the game's invisible material (the parts are what is drawn)
--   other_variant        the host sees the guest's variant (green cloth), the guest the host's (no green)
--   own_has_no_parts     our own body has none
--   part_on_bone         the parts sit on their bones (hand_r, foot_l, head, spine_03): within 3 uu
--   part_follows_walk    both sides move 300 uu; the other's hand part moved more than 100 uu and is on its bone again within 4 uu
-- Run: tools/run-test.ps1 -Scenario survivor -Headless      Mutation nosurvivor: survivor.lua off, the parts checks FAIL.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local BONES = { "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
        "thigh_l", "calf_l", "foot_l", "ball_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "thigh_r", "calf_r", "foot_r", "ball_r" }
    local function other() return T.ROLE == "host" and L.guestChar() or T.otherChar() end
    local function d3(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2 + (a.Z - b.Z) ^ 2) end
    local function worst(o, bones)
        local parts, w = L.survivorParts(o), 0
        for _, b in ipairs(bones) do
            local p = parts[b]
            if not p then return 1e9 end
            w = math.max(w, d3(p:K2_GetComponentLocation(), o.Mesh:GetSocketLocation(FName(b))))
        end
        return w
    end
    local ON = { "hand_r", "foot_l", "head", "spine_03" }
    local function handPos() local v = L.survivorParts(other()).hand_r:K2_GetComponentLocation(); return { X = v.X, Y = v.Y, Z = v.Z } end
    local steps = {}
    local function add(s) steps[#steps + 1] = s end
    -- AddMovementInput did not move either character in the garage: the host moves both characters 200 uu back and forth for 12 s
    -- (it replicates; the sides run out of step, so the other's hand is sampled over the whole window)
    local lo, hi, n = nil, nil, 0
    local function walk()
        return { check = "walk_" .. T.ROLE, timeout = 30, cond = function()
            -- a guest's own teleport is corrected by the host: the host moves both characters (the guest's through authority)
            if T.ROLE == "host" then
                for _, c in ipairs({ L.own(), L.guestChar() }) do
                    local l, f = c:K2_GetActorLocation(), c:GetActorForwardVector()
                    local k = (n % 2 == 0) and 200 or -200
                    c:K2_TeleportTo({ X = l.X + f.X * k, Y = l.Y + f.Y * k, Z = l.Z + 20 }, c:K2_GetActorRotation())
                end
            end
            n = n + 1
            local h = handPos()
            lo = lo and math.min(lo, h.X + h.Y) or h.X + h.Y
            hi = hi and math.max(hi, h.X + h.Y) or h.X + h.Y
            return n >= 12
        end }
    end
    add(T.onMap("RB_MainMenu", 90))
    if T.ROLE == "host" then
        add({ wait = 5 })
        add({ run = function() T.console("open " .. T.GARAGE .. "?listen") end })
        add({ check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end })
        add({ check = "host_two_pcs", timeout = 180, cond = function() return T.pcs() == 2 end })
        add({ check = "host_spawned_guest", timeout = 60, cond = function() return L.guestChar() ~= nil end })
    else
        add(T.join("client_connected_garage", "RB_Garage", 210, 30))
        add({ check = "client_possessed", timeout = 60, cond = function() return T.cls(T.myPawn()) == T.CHAR end })
        add({ check = "client_sees_host_body", timeout = 60, cond = function() return T.otherChar() ~= nil end })
    end
    local r = T.ROLE
    add({ wait = 8 })
    add({ check = r .. "_other_has_parts", timeout = 20, cond = function()
        local o = other()
        if not o then return false end
        local parts, n = L.survivorParts(o), 0
        for _, p in pairs(parts) do if p:IsVisible() and not p.bHiddenInGame then n = n + 1 end end
        T.log("PT|info survivor parts=%d mat=%s", n, L.material(o))
        return n >= 17
    end })
    -- the host draws the guest's variant (green Cloth), the guest the host's (red-brown Cloth): a thigh section greener than red
    add({ check = r .. "_other_variant", timeout = 10, cond = function()
        local p, green = L.survivorParts(other()).thigh_l, false
        if not p then return false end
        for i = 0, p:GetNumSections() - 1 do
            local m = p:GetMaterial(i)
            local c = m:IsValid() and m:K2_GetVectorParameterValue(FName("Color"))
            if c and c.G > c.R then green = true end
        end
        T.log("PT|info survivor other thigh green=%s", tostring(green))
        return green == (T.ROLE == "host")
    end })
    add({ check = r .. "_other_mannequin_invisible", timeout = 5, cond = function() return L.invisible(other()) end })
    add({ check = r .. "_own_has_no_parts", timeout = 5, cond = function() return next(L.survivorParts(L.own())) == nil end })
    add({ check = r .. "_part_on_bone", timeout = 10, cond = function()
        local w = worst(other(), ON)
        T.log("PT|info survivor worst offset %.2f", w)
        return w < 3
    end })
    add(walk())
    add({ wait = 6 })
    add({ check = r .. "_part_follows_walk", timeout = 20, cond = function()
        local w = worst(other(), ON)
        T.log("PT|info survivor settled worst %.2f hand range %.0f", w, (hi or 0) - (lo or 0))
        return w < 4 and (hi or 0) - (lo or 0) > 100
    end })
    add({ wait = 3 })
    return steps
end
