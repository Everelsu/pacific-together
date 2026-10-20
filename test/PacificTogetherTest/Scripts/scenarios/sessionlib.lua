-- Shared checks for the session* scenarios (M2). They look at game state only; the shipping mod does the work.
return function(T)
    local L = {}
    -- guest: since PTNative_SetRejoin a host's map change or drop reloads us straight back to the host, not via the menu
    local loads, menus = 0, 0
    RegisterLoadMapPostHook(function() pcall(function()
        loads = loads + 1
        if T.map() == "RB_MainMenu" then menus = menus + 1 end
    end) end)
    function L.mark() return { loads = loads, menus = menus } end
    -- the world was reloaded since the mark, and never into the menu
    function L.reloadedNoMenu(m)
        assert(menus == m.menus, "went through the main menu")
        return loads > m.loads
    end
    function L.chars()
        local r = {}
        for _, c in ipairs(FindAllOf("BaseCharacter") or {}) do if T.inWorld(c) then r[#r + 1] = c end end
        return r
    end
    function L.invisible(c) return c.Mesh:IsValid() and T.name(c.Mesh:GetMaterial(0)):find("Invist", 1, true) ~= nil end
    function L.material(c) return (c and c.Mesh:IsValid()) and T.name(c.Mesh:GetMaterial(0)) or "none" end
    -- host: the remote PCs of this world and the characters they possess
    function L.remotePCs()
        local r = {}
        for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
            if T.inWorld(pc) and not pc:IsLocalController() then r[#r + 1] = pc end
        end
        return r
    end
    function L.guestChar()
        for _, pc in ipairs(L.remotePCs()) do
            if T.inWorld(pc.Pawn) and T.cls(pc.Pawn) == T.CHAR then return pc.Pawn end
        end
    end
    function L.guestName()
        local pc = L.remotePCs()[1]
        local ps = pc and pc.PlayerState
        return (ps and ps:IsValid()) and ps:GetPlayerName():ToString() or ""
    end
    function L.manager() return T.first("BP_MainCharacterManager_C") end
    -- our own character: the pawn, or the manager's character while we drive (the intro starts in the car)
    function L.own()
        local me = T.myPawn()
        if me and T.cls(me) == T.CHAR then return me end
        local cm = L.manager()
        return cm and cm.CharacterActor:IsValid() and cm.CharacterActor or nil
    end
    function L.managerIsMine()
        local cm, me = L.manager(), L.own()
        return cm ~= nil and me ~= nil and cm.CharacterActor:IsValid() and cm.CharacterActor:GetFullName() == me:GetFullName()
    end
    -- the host's view: guest possessed, next to us, drawn visible; our own body untouched; manager still ours
    function L.hostSeesGuest()
        local g, me = L.guestChar(), L.own()
        return g ~= nil and me ~= nil and T.dist(me, g) < 600 and not L.invisible(g) and L.invisible(me) and L.managerIsMine()
    end
    -- the guest's view: possessed a character, the host's body visible, own body invisible
    function L.guestSeesHost()
        local me, o = T.myPawn(), T.otherChar()
        return me ~= nil and T.cls(me) == T.CHAR and o ~= nil and not L.invisible(o) and L.invisible(me)
    end
    function L.describe()
        local me, o, g = T.myPawn(), T.otherChar(), (T.ROLE == "host") and L.guestChar() or nil
        local cm = L.manager()
        return string.format("me=%s(%s) other=%s(%s) guest=%s d=%s manager=%s", T.cls(me), L.material(me), T.cls(o), L.material(o),
            T.cls(g), (me and o) and string.format("%.0f", T.dist(me, o)) or "-", T.name(cm and cm.CharacterActor))
    end
    -- for a check that must stay true for a while: true once `secs` passed with ok() never false
    function L.holds(secs, ok)
        local t0, bad
        return function()
            t0 = t0 or os.time()
            if not ok() then bad = bad or T.state() end
            assert(not bad, "broke: " .. tostring(bad))
            return os.time() - t0 >= secs
        end
    end
    local GAMEPLAY = function(m) return not ({ RB_MainMenu = 1, none = 1 })[m] end
    L.gameplay = GAMEPLAY
    return L
end
