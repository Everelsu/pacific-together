-- Hot reload of the main mod's Lua (tools/repl.ps1 -Reload) in a live two-player session: each side restarts the Lua mod
-- RELOADS times, main.dll (its own mod, PacificTogetherNative) stays loaded, and the reloaded mod still carries the
-- guest through the host's native travel. Mutations: noreload (nothing restarted: the reload checks fail), nowait
-- (RestartMod without PTNative_ReloadLua: the game thread keeps firing hooks during the uninstall; crashed the host in 1
-- of 4 runs, so it does not reliably fail).
local RELOADS = 5

return function(T)
    local L = require("scenarios.sessionlib")(T)
    local M = T.MUTATE

    -- the UE4SS log of this copy (cwd is Binaries/Win64)
    local function count(pattern)
        local f = io.open("ue4ss/UE4SS.log", "rb")
        if not f then return -1 end
        local text, n, i = f:read("a"), 0, 1
        f:close()
        while true do
            local s = text:find(pattern, i, true)
            if not s then return n end
            n, i = n + 1, s + 1
        end
    end
    local BOOT, CPP = "[PacificTogether] PT|boot", "Stopping C++ mod"
    local boots, cpps

    local function reloads(side)
        local steps = { { run = function() boots, cpps = count(BOOT), count(CPP) end } }
        for _ = 1, RELOADS do
            steps[#steps + 1] = { run = function()
                if M == "noreload" then return end
                -- nowait: plain RestartMod, the game thread keeps running during the uninstall
                if M ~= "nowait" and not PTNative_ReloadLua() then T.log("PT|info reload already under way") end
                RestartMod("PacificTogether")
            end }
            steps[#steps + 1] = { wait = 2 }
        end
        steps[#steps + 1] = { check = side .. "_lua_reloaded", timeout = 20, cond = function() return count(BOOT) >= boots + RELOADS end }
        steps[#steps + 1] = { check = side .. "_dll_kept", timeout = 5, cond = function() return count(CPP) == cpps and PTNative_Version ~= nil end }
        return steps
    end
    local function append(a, b) for _, s in ipairs(b) do a[#a + 1] = s end; return a end

    if T.ROLE == "host" then
        local steps = {
            T.onMap("RB_MainMenu", 90),
            { wait = 5 },
            { run = function() T.console("open " .. T.GARAGE) end },
            { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.listening() and T.map() == "RB_Garage" end },
            { check = "host_guest_joined", timeout = 240, cond = function() return T.pcs() == 2 end },
            { check = "host_guest_possessed", timeout = 60, cond = function() return L.guestChar() ~= nil end },
            { wait = 3 },
        }
        append(steps, reloads("host"))
        return append(steps, {
            { check = "host_session_survives_reload", timeout = 5, cond = function() return T.netMode() == "listen" and T.pcs() == 2 and L.hostSeesGuest() end },
            -- give the guest time to finish its own reloads
            { wait = 10 },
            -- only the reloaded mod keeps the host listening and brings the guest along
            { run = function() T.log("PT|info UserNewGame -> %s", tostring(T.saveMgr():UserNewGame(5, 1))) end },
            { check = "host_native_travel", timeout = 240, cond = function() return L.gameplay(T.map()) and T.map() ~= "RB_Garage" end },
            { check = "host_listen_after_travel", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end },
            { check = "host_guest_back_after_travel", timeout = 180, cond = function() return L.guestChar() ~= nil end },
            { wait = 5 },
            { check = "host_sees_guest_after_travel", timeout = 20, cond = function() return L.hostSeesGuest() end },
            { wait = 10 },
        })
    end

    local mark
    local steps = {
        T.onMap("RB_MainMenu", 90),
        { check = "client_joined_garage", timeout = 240, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" end },
        { check = "client_possessed", timeout = 60, cond = function() return T.cls(T.myPawn()) == T.CHAR end },
        { wait = 3 },
    }
    append(steps, reloads("client"))
    return append(steps, {
        { check = "client_session_survives_reload", timeout = 5, cond = function() return T.netMode() == "client" and L.guestSeesHost() end },
        { run = function() mark = L.mark() end },
        { check = "client_dropped_by_travel", timeout = 300, cond = function() return L.reloadedNoMenu(mark) end },
        { check = "client_rejoined_after_travel", timeout = 300, cond = function() return T.netMode() == "client" and L.gameplay(T.map()) and L.guestSeesHost() end },
        { wait = 10 },
    })
end
