-- Q7: with no session (a host listening alone) the mod changes nothing: saves are written, the UI pause and the Chrono
-- Dilator work, no name tag exists. Q9 is the exception: the game's Sentry DSN is cleared while the mod is installed.
-- Run with -Clients 1. -Mutate join (-Clients 2): a guest joins first, so pause and dilator checks must FAIL.
return function(T)
    local L = require("scenarios.safety_lib")
    if T.ROLE == "client" then return { T.onMap("RB_MainMenu", 90), T.join("client_connected_garage", "RB_Garage", 210, 30), { wait = 60 } } end
    local warper, file, before
    return {
        T.onMap("RB_MainMenu", 90),
        { wait = 3 },
        { check = "solo_sentry_dsn_cleared", timeout = 1, cond = function() return StaticFindObject("/Script/Sentry.Default__SentrySettings").DsnUrl:ToString() == "" end },
        { run = function() T.console("open " .. T.GARAGE .. "?listen") end },
        { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
        T.MUTATE == "join" and { check = "host_two_pcs", timeout = 240, cond = function() return T.pcs() == 2 end } or { wait = 1 },
        { wait = 8 },
        { run = function()
            local slot = T.saveMgr():GetCurrentSlot()
            file = L.saved() .. "\\SaveGames\\" .. (slot == 0 and "odsave_scratch" or "odsave" .. slot) .. ".sav"
            before = L.read(file)
            T.log("PT|info SaveGame(%d) -> %s file=%s before=%s", slot, tostring(T.saveMgr():SaveGame(slot, "", 2)), file, tostring(before and #before))
        end },
        { check = "solo_save_written", timeout = 10, cond = function() local now = L.read(file); return now ~= nil and now ~= before end },
        { run = function() L.pause(T, true) end },
        { check = "solo_pause_works", timeout = 2, cond = function() return L.paused(T) end },
        { run = function() L.pause(T, false) end },
        { run = function() warper = L.startWarper(T) end },
        { wait = 4 },
        { check = "solo_dilator_works", timeout = 1, cond = function() T.log("PT|info dilation after 4 s: %.3f", L.dilation(T)); return L.dilation(T) < 0.9 end },
        { run = function() L.stopWarper(T, warper) end },
        { check = "solo_no_tags", timeout = 1, cond = function() return #L.tagsOn(T) == 0 end },
        -- Q9: the game's own Sentry start; -Mutate sentry lets it through, aimed at a dead local DSN (nothing leaves the PC)
        { run = function()
            if T.MUTATE == "sentry" then
                StaticFindObject("/Script/Sentry.Default__SentrySettings").DsnUrl = "http://00000000000000000000000000000000@127.0.0.1:9/1"
                PTNative_TestAllowSentry(true)
            end
            FindFirstOf("SentrySubsystem"):Initialize()
        end },
        { wait = 5 },
        { check = "solo_sentry_not_started", timeout = 1, cond = function()
            local n = L.children("crashpad_handler.exe")
            T.log("PT|info sentry_init refused=%s crashpad_handler=%s", tostring(PTNative_SentryInitBlocked()), tostring(n))
            return n == 0 and PTNative_SentryInitBlocked() > 0
        end },
    }
end
