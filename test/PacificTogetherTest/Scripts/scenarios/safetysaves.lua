-- S7, the save writers `safety` does not trigger: the game's own save entry points (the DbgActEvt save events that run the
-- Blueprint save graph, Rinse called directly, the run-failure and save-and-quit branches of TravelToGarage) as a guest in a
-- session. The runner checks the guest's Saved\SaveGames + Saved\Config after each (PT|snap); the scenario checks
-- Content\Bookmarks (the bookmark event).
-- Mutation nosession: the guest never joins, so it is single player and the writes must show up (checks FAIL).
return function(T)
    local L = require("scenarios.safety_lib")
    local alone = T.MUTATE == "nosession"
    if T.ROLE == "host" then
        return {
            T.onMap("RB_MainMenu", 90),
            { wait = 5 },
            { run = function() T.console("open " .. T.GARAGE .. "?listen") end },
            { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
            alone and { wait = 20 } or { check = "host_two_pcs", timeout = 400, cond = function() return T.pcs() == 2 end },
            -- stay up while the guest runs its writers
            { wait = 200 },
        }
    end
    local sm = function() return T.saveMgr() end
    local function event(name) return function() local m = sm(); m[name](m); return name end end
    local called = {}
    local function call(tag, fn)
        return { run = function()
            local ok, r = pcall(fn)
            called[tag] = ok
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
        { check = "client_is_guest", timeout = 1, cond = function() return alone or T.netMode() == "client" end },
        { run = function() T.log("PT|info joined %s", T.mgrState()); T.snap("joined") end },
    }
    local writers = {
        { "evt_savegamenow", event("DbgActEvt_Save Game Now_Execute") },
        { "evt_savegame0", event("DbgActEvt_Save Game 0_Execute") },
        { "evt_checkpoint", event("DbgActEvt_Force Save Checkpoint_Execute") },
        { "evt_bookmark", event('DbgActEvt_MakeBookmark "bookmark"_Execute') },
        { "rinse", function() return sm():Rinse(sm():GetCurrentSlot(), 6, "") end },
        -- the run-failure branch (RunFinished_Failure, the death return): Rinse unless direct load
        { "travel_failure", function() return T.first("BP_ProgressionManager_C"):TravelToGarage(3, false, false, false, 1, {}) end },
    }
    local bmk
    steps[#steps + 1] = { run = function() bmk = L.saved():gsub("\\Saved$", "\\Content\\Bookmarks\\bookmark.bmk"); os.remove(bmk) end }
    local function snapAfter(tag)
        steps[#steps + 1] = { wait = 6 }
        steps[#steps + 1] = { run = function() T.snap(tag) end }
        steps[#steps + 1] = { wait = 4 } -- the runner snapshots within one 3 s poll
    end
    for _, w in ipairs(writers) do
        steps[#steps + 1] = call(w[1], w[2])
        snapAfter(w[1])
    end
    -- still in the session after all that? then the last writer: save and quit (SaveGame, then QuitToMenu = the guest leaves)
    -- return states 2 and 3 jump past the SaveAndQuit branch (BP_ProgressionManager TravelToGarage bytecode), so use 0
    steps[#steps + 1] = call("travel_saveandquit", function() return T.first("BP_ProgressionManager_C"):TravelToGarage(0, false, false, true, 1, {}) end)
    steps[#steps + 1] = { wait = 8 }
    steps[#steps + 1] = { run = function() T.snap("saveandquit") end }
    steps[#steps + 1] = { wait = 4 }
    steps[#steps + 1] = { check = "client_writers_called", timeout = 1, cond = function()
        for _, w in ipairs(writers) do assert(called[w[1]], w[1] .. " did not run") end
        return called.travel_saveandquit == true
    end }
    steps[#steps + 1] = { check = "client_no_bookmark_file", timeout = 1, cond = function() return L.read(bmk) == nil end }
    steps[#steps + 1] = { wait = 5 }
    return steps
end
