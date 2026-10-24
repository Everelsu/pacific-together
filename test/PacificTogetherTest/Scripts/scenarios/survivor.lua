-- pt4-model survivor: the other player's body is Djecka's survivor (survivor.lua), on both sides. Fixture-less garage, the guest joins by itself.
--   other_has_parts      the other character has a survivor part attached to each of the 20 bones with geometry, visible
--   other_mannequin_invisible  its own mesh keeps the game's invisible material (the parts are what is drawn)
--   own_has_no_parts     our own body has none
--   part_on_bone         the parts sit on their bones (hand_r, foot_l, head, spine_02): within 3 uu
--   part_follows_walk    both sides walk 3 s; the other's hand part moved more than 100 uu and is on its bone again within 4 uu
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
    local ON = { "hand_r", "foot_l", "head", "spine_02" }
    local before
    local function handPos() return L.survivorParts(other()).hand_r:K2_GetComponentLocation() end
    local steps = {}
    local function add(s) steps[#steps + 1] = s end
    local function walk(secs)
        local t0
        return { check = "walk_" .. T.ROLE, timeout = secs + 10, cond = function()
            local me = L.own()
            t0 = t0 or os.clock()
            me:AddMovementInput(me:GetActorForwardVector(), 1.0, false)
            return os.clock() - t0 > secs
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
        return n >= 20
    end })
    add({ check = r .. "_other_mannequin_invisible", timeout = 5, cond = function() return L.invisible(other()) end })
    add({ check = r .. "_own_has_no_parts", timeout = 5, cond = function() return next(L.survivorParts(L.own())) == nil end })
    add({ check = r .. "_part_on_bone", timeout = 10, cond = function()
        local w = worst(other(), ON)
        T.log("PT|info survivor worst offset %.2f", w)
        return w < 3
    end })
    add({ run = function() before = handPos() end })
    add(walk(3))
    add({ wait = 1.5 })
    add({ check = r .. "_part_follows_walk", timeout = 20, cond = function()
        local o = other()
        local moved, w = d3(before, handPos()), worst(o, ON)
        T.log("PT|info survivor walk moved %.0f worst %.2f", moved, w)
        return moved > 100 and w < 4
    end })
    add({ wait = 3 })
    return steps
end
