-- Q7 single player with the mod installed (one game, no PT_JOIN): the session is open (S1, D14) but nothing else
-- changes: one controller, one character, ours, drawn invisible as in the vanilla game, the manager points at it,
-- through the game's own new game, native travel and quit. Mutation: spawn (the test adds a second character).
local UEHelpers = require("UEHelpers")

return function(T)
    local L = require("scenarios.sessionlib")(T)
    local function vanilla()
        local cs, me = L.chars(), L.own()
        return T.pcs() == 1 and #cs == 1 and me ~= nil and cs[1]:GetFullName() == me:GetFullName() and L.invisible(me) and L.managerIsMine()
    end
    local function spawnExtra()
        if T.MUTATE ~= "spawn" then return end
        local me = L.own()
        local l = me:K2_GetActorLocation()
        local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X, Y = l.Y + 300, Z = l.Z + 50 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local gs = UEHelpers.GetGameplayStatics()
        gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(T.world(), me:GetClass(), xf, 2, nil), xf)
    end
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "solo_menu_standalone", timeout = 5, cond = function() return T.netMode() == "standalone" end },
        { wait = 5 },
        { run = function() T.log("PT|info UserNewGame -> %s", tostring(T.saveMgr():UserNewGame(5, 1))) end },
        { check = "solo_new_game", timeout = 240, cond = function() return L.gameplay(T.map()) and L.own() ~= nil end },
        { check = "solo_session_open", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end },
        { wait = 15 },
        { run = spawnExtra },
        { wait = 3 },
        { check = "solo_vanilla_new_game", timeout = 5, cond = vanilla },
        { run = function() T.log("PT|info %s %s", T.map(), L.describe()) end },
        { run = function() T.console("open " .. T.GARAGE) end },
        { check = "solo_garage", timeout = 120, cond = function() return T.map() == "RB_Garage" and T.myPawn() ~= nil end },
        { wait = 15 },
        { check = "solo_vanilla_garage", timeout = 5, cond = vanilla },
        { run = function() T.quitToMenu() end },
        { check = "solo_menu_after_quit", timeout = 120, cond = function() return T.map() == "RB_MainMenu" and T.netMode() == "standalone" end },
        { wait = 5 },
    }
end
