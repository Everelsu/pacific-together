-- S7 + G5 with the shipping safety module: a guest who played their own save (slot 6) joins the host's garage and runs
-- every save writer the game has; the runner checks their Saved\SaveGames + Saved\Config after each (PT|snap), the
-- scenario checks Content\Bookmarks (MakeBookmark).
-- The host, with the guest connected, pauses through the game's UI path and starts a Chrono Dilator.
-- -Mutate nosession: the guest never joins, so it is single player and every check must FAIL (writes happen, pause and
-- dilation work). -Mutate nofileguard: native file guard off after joining; the writers without a slot then write.
return function(T)
    local L = require("scenarios.safety_lib")
    local alone = T.MUTATE == "nosession"
    if T.ROLE == "host" then
        local warper
        return {
            T.onMap("RB_MainMenu", 90),
            { wait = 5 },
            { run = function() T.console("open " .. T.GARAGE .. "?listen") end },
            { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
            alone and { wait = 20 } or { check = "host_two_pcs", timeout = 400, cond = function() return T.pcs() == 2 end },
            { wait = 10 },
            { run = function() L.pause(T, true) end },
            { check = "host_pause_blocked", timeout = 2, cond = function() return not L.paused(T) end },
            { run = function() L.pause(T, false) end },
            { run = function() warper = L.startWarper(T) end },
            { wait = 4 },
            { check = "host_dilator_blocked", timeout = 1, cond = function()
                T.log("PT|info dilation after 4 s: %.3f", L.dilation(T))
                return L.dilation(T) > 0.99
            end },
            { run = function() L.stopWarper(T, warper) end },
            -- stay up while the guest runs its writers
            alone and { wait = 5 } or { check = "host_guest_still_here", timeout = 300, cond = function() return T.pcs() == 2 end },
            { wait = 200 },
        }
    end
    local function call(tag, fn)
        return { run = function()
            local ok, r = pcall(fn)
            T.log("PT|info %s -> ok=%s %s blocked=%s", tag, tostring(ok), tostring(r), tostring(PTNative_SaveGuardBlocked and PTNative_SaveGuardBlocked()))
        end }
    end
    local steps = {
        T.onMap("RB_MainMenu", 90),
        { wait = 5 },
        { run = function() T.log("PT|info own game: UserNewGame(6, STORY) -> %s", tostring(T.saveMgr():UserNewGame(6, 1))) end },
        { check = "client_own_game", timeout = 240, cond = function() return not ({ RB_MainMenu = 1, none = 1 })[T.map()] end },
        { wait = 20 },
        { run = function() T.quitToMenu() end },
        { check = "client_back_in_menu", timeout = 180, cond = function() return T.map() == "RB_MainMenu" end },
        { wait = 5 },
        { run = function() T.log("PT|info menu %s", T.mgrState()); T.snap("menu") end },
        alone and { wait = 5 } or T.join("client_connected_garage", "RB_Garage", 300, 30),
        { wait = 20 },
        { check = "client_is_guest", timeout = 1, cond = function() return T.netMode() == "client" end },
        { run = function()
            if T.MUTATE == "nofileguard" then T.log("PT|info file guard off -> %s", tostring(PTNative_SetSaveGuard(false))) end
            T.log("PT|info joined %s", T.mgrState()); T.snap("joined")
        end },
    }
    local writers = {
        { "autosave", function() local d = T.first("BP_AutoSaveDirector_C"); d:FlagAutosave(); d:CheckFlagAndTrigger(); return T.name(d) end },
        { "savegame", function() return T.saveMgr():SaveGame(T.saveMgr():GetCurrentSlot(), "", 2) end },
        { "saveslot6", function() return T.saveMgr():SaveGame(6, "", 1) end },
        { "gameplaysettings", function() return T.saveMgr():WriteGameplaySettingsToSlot(6) end },
        { "usersettings", function() return T.saveMgr():WriteUserSettings() end },
        { "checkpoint", function() T.saveMgr():SaveCheckpoint(); return "" end },
        { "bookmark", function() return T.saveMgr():MakeBookmark(FName("pt_test"), true, false) end },
        { "delete", function() return T.saveMgr():DeleteGame(6, true) end },
    }
    -- MakeBookmark writes <copy>\PenDriverPro\Content\Bookmarks\<name>.bmk, outside the runner's snapshots
    local bmk
    steps[#steps + 1] = { run = function() bmk = L.saved():gsub("\\Saved$", "\\Content\\Bookmarks\\pt_test.bmk"); os.remove(bmk) end }
    for _, w in ipairs(writers) do
        steps[#steps + 1] = call(w[1], w[2])
        steps[#steps + 1] = { wait = 6 }
        steps[#steps + 1] = { run = function() T.snap(w[1]) end }
        steps[#steps + 1] = { wait = 4 } -- the runner snapshots within one 3 s poll
    end
    steps[#steps + 1] = { check = "client_no_bookmark_file", timeout = 1, cond = function() return L.read(bmk) == nil end }
    steps[#steps + 1] = { wait = 5 }
    return steps
end
