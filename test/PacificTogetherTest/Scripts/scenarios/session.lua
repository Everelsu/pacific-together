-- M2 session core with the real mod: the host loads maps the game's way (no ?listen from the test), the guest has
-- PT_JOIN set by the runner and never runs `open` itself. Covers S1, S3, S4 (accept), S5, S6, P1, X13 and the
-- cleanup before native travel. Mutations: nolisten (host's auto-listen off), kill (host test destroys the guest's
-- character once it is there), invisible (test puts the invisible material back), nocleanup (host test re-adds a remote character
-- after the mod's cleanup), leave (guest quits right after the first join), rename (the guest's name stays a hello).
local UEHelpers = require("UEHelpers")

return function(T)
    local L = require("scenarios.sessionlib")(T)
    local M = T.MUTATE

    -- runs after the mod's own LoadMap pre-hook (mods hook in load order): what is left for the engine to tear down?
    local atTeardown = { n = -1, maps = 0 }
    RegisterLoadMapPreHook(function(engine, worldp, url, pending)
        pcall(function()
            local w = worldp:get()
            if pending:get():IsValid() or not w:IsValid() or T.ROLE ~= "host" then return end
            if M == "nocleanup" then
                for _, pc in ipairs(L.remotePCs()) do
                    local me = T.myPawn()
                    if me then
                        local l = me:K2_GetActorLocation()
                        local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X, Y = l.Y + 200, Z = l.Z + 50 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
                        local gs = UEHelpers.GetGameplayStatics()
                        pc:Possess(gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(w, me:GetClass(), xf, 2, nil), xf))
                        T.log("PT|info nocleanup re-added a character for %s", T.name(pc))
                    end
                end
            end
            local n = 0
            for _, pc in ipairs(L.remotePCs()) do if pc.Pawn:IsValid() then n = n + 1 end end
            atTeardown.n, atTeardown.maps = n, atTeardown.maps + 1
            T.log("PT|info teardown map=%s remote pawns=%d", T.map(), n)
        end)
    end)

    if T.ROLE == "host" then
        local mark
        local function teardownClean(id) return { check = id, timeout = 5, cond = function() return atTeardown.maps > mark and atTeardown.n == 0 end } end
        return {
            T.onMap("RB_MainMenu", 90),
            { run = function() if M == "nolisten" then T.log("PT|info nolisten %s", tostring(PTNative_SetAutoListen(false))) end end },
            { check = "host_menu_standalone", timeout = 5, cond = function() return T.netMode() == "standalone" end },
            { wait = 5 },
            -- a plain map load from the menu; the mod must make it listen
            { run = function() T.console("open " .. T.GARAGE) end },
            { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.listening() and T.map() == "RB_Garage" end },
            { check = "host_guest_joined", timeout = 240, cond = function() return T.pcs() == 2 end },
            { check = "host_guest_possessed", timeout = 60, cond = function() return L.guestChar() ~= nil end },
            { run = function()
                if M == "kill" then L.guestChar():K2_DestroyActor() end
                if M == "invisible" then
                    local g, inv = L.guestChar(), StaticFindObject("/Game/Characters/Player/Art/Materials/M_PlayerCharacter_Invist.M_PlayerCharacter_Invist")
                    if g then for i = 0, g.Mesh:GetNumMaterials() - 1 do g.Mesh:SetMaterial(i, inv) end end
                end
            end },
            { wait = 3 },
            { check = "host_sees_guest", timeout = 20, cond = function() return L.hostSeesGuest() end },
            { run = function() T.log("PT|info garage %s name=%s", L.describe(), L.guestName()) end },
            { wait = 10 },
            -- the handshake rode on ServerChangeName; the guest's PlayerState must end up with its real name
            { check = "host_guest_named", timeout = 20, cond = function()
                local n = L.guestName()
                return n ~= "" and not n:find("PT|", 1, true)
            end },
            { check = "host_manager_still_own", timeout = 5, cond = function() return L.managerIsMine() end },
            -- the game's own travel (new game in slot 5) with the guest in
            { run = function() mark = atTeardown.maps; T.log("PT|info UserNewGame -> %s", tostring(T.saveMgr():UserNewGame(5, 1))) end },
            { check = "host_native_travel", timeout = 240, cond = function() return L.gameplay(T.map()) and T.map() ~= "RB_Garage" end },
            teardownClean("host_cleanup_before_travel"),
            { check = "host_listen_after_native_travel", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end },
            { check = "host_guest_back_after_travel", timeout = 180, cond = function() return L.guestChar() ~= nil end },
            { wait = 5 },
            { check = "host_sees_guest_after_travel", timeout = 20, cond = function() return L.hostSeesGuest() end },
            { run = function() T.log("PT|info %s %s", T.map(), L.describe()) end },
            { wait = 10 },
            { run = function() mark = atTeardown.maps; T.quitToMenu() end },
            { check = "host_menu_after_quit", timeout = 120, cond = function() return T.map() == "RB_MainMenu" and T.netMode() == "standalone" end },
            teardownClean("host_cleanup_before_quit"),
            { wait = 15 },
            -- loading a save from the menu: S1 again, the guest (waiting in its menu) comes back by itself
            { run = function() T.log("PT|info UserNewGame from menu -> %s", tostring(T.saveMgr():UserNewGame(5, 1))) end },
            { check = "host_listen_after_menu_load", timeout = 240, cond = function() return L.gameplay(T.map()) and T.netMode() == "listen" and T.listening() end },
            { check = "host_guest_back_after_menu", timeout = 240, cond = function() return L.guestChar() ~= nil end },
            { wait = 5 },
            { check = "host_sees_guest_after_menu", timeout = 20, cond = function() return L.hostSeesGuest() end },
            -- the guest leaves on purpose: its character goes, the host stays
            { check = "host_guest_left", timeout = 120, cond = function() return T.pcs() == 1 and #L.chars() == 1 end },
            { check = "host_alone_stays_up", timeout = 45, cond = L.holds(30, function() return T.netMode() == "listen" and T.pcs() == 1 end) },
        }
    end

    local function back(id) return { check = id, timeout = 300, cond = function() return T.netMode() == "client" and L.gameplay(T.map()) and L.guestSeesHost() end } end
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_joined_garage", timeout = 240, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" end },
        { check = "client_possessed", timeout = 60, cond = function() return T.cls(T.myPawn()) == T.CHAR end },
        { run = function() if M == "invisible" then
            local o, inv = T.otherChar(), StaticFindObject("/Game/Characters/Player/Art/Materials/M_PlayerCharacter_Invist.M_PlayerCharacter_Invist")
            if o then for i = 0, o.Mesh:GetNumMaterials() - 1 do o.Mesh:SetMaterial(i, inv) end end
        end end },
        { wait = 3 },
        { check = "client_sees_host", timeout = 20, cond = function() return L.guestSeesHost() end },
        { check = "client_manager_own", timeout = 10, cond = function() return L.managerIsMine() end },
        { run = function()
            T.log("PT|info garage %s", L.describe())
            if M == "leave" then T.quitToMenu() end
            if M == "rename" then T.localPC():ServerChangeName("PT|hello mod=renamed") end
        end },
        { check = "client_dropped_by_travel", timeout = 300, cond = function() return T.map() == "RB_MainMenu" end },
        back("client_rejoined_after_travel"),
        { run = function() T.log("PT|info %s %s", T.map(), L.describe()) end },
        { check = "client_dropped_by_quit", timeout = 300, cond = function() return T.map() == "RB_MainMenu" end },
        back("client_rejoined_after_menu"),
        { run = function() T.log("PT|info %s %s", T.map(), L.describe()) end },
        { wait = 10 },
        { run = function() T.quitToMenu() end },
        { check = "client_menu_after_leave", timeout = 60, cond = function() return T.map() == "RB_MainMenu" end },
        -- left on purpose: no rejoin
        { check = "client_stays_out", timeout = 75, cond = L.holds(60, function() return T.netMode() ~= "client" and T.map() == "RB_MainMenu" end) },
    }
end
