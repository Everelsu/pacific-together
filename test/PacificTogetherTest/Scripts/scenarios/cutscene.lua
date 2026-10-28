-- New-game opening skipped with E for both (cutscene.lua). The host starts a new game (slot 6) with the guest in; once both can skip
-- the opening (the intro level's CanSkip), the guest presses E (console "ptskip", the key's handler): the opening must end on both.
-- Run: tools/run-test.ps1 -Scenario cutscene -Headless      Mutation nocutscene: the module is off (checks FAIL).
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local got = {}
    local function g(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind]
    end
    local function canSkip()
        for _, l in ipairs(FindAllOf("LevelScriptActor") or {}) do
            local ok, c = pcall(function() return l:IsValid() and l.CanSkip and not l:GetFullName():find("/Engine/Transient", 1, true) end)
            if ok and c == true then return true end
        end
        return false
    end

    if T.ROLE == "host" then
        return {
            T.onMap("RB_MainMenu", 90),
            { wait = 5 },
            { run = function() T.console("open " .. T.GARAGE) end },
            { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.listening() and T.map() == "RB_Garage" end },
            { check = "host_guest_possessed", timeout = 240, cond = function() return L.guestChar() ~= nil end },
            { wait = 5 },
            { run = function() T.log("PT|info UserNewGame -> %s", tostring(T.saveMgr():UserNewGame(6, 1))) end },
            { check = "host_in_opening", timeout = 240, cond = function() return L.gameplay(T.map()) and T.map() ~= "RB_Garage" end },
            { check = "host_guest_back", timeout = 180, cond = function() return L.guestChar() ~= nil end },
            { check = "host_can_skip", timeout = 120, cond = canSkip },
            { check = "guest_can_skip", timeout = 120, cond = function() return g("t.can") == "1" end },
            { run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.press", "1") end },
            { check = "host_opening_skipped", timeout = 20, cond = function() return not canSkip() end },
            { check = "guest_opening_skipped", timeout = 20, cond = function() return g("t.can") == "0" end },
            { run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.done", "1") end },
            { wait = 3 },
        }
    end

    local mark
    local pressed = false
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end },
        { run = function() mark = L.mark() end },
        { check = "client_back_after_new_game", timeout = 300, cond = function() return L.reloadedNoMenu(mark) and T.netMode() == "client" end },
        { check = "guest_reports", timeout = 600, cond = function()
            PTNative_MsgToHost(T.localPC():GetAddress(), "t.can", canSkip() and "1" or "0")
            if g("t.press") and not pressed then pressed = true; T.console("ptskip") end
            return g("t.done") ~= nil
        end },
    }
end
