-- Immersion lane 2026-10-25: a map transition should look like one to both players. The host travels to the next leg (as through a
-- junction) with the guest in its zone; the host must keep the game's loading screen up after its own load until the guest has its
-- character (transition.lua), and the guest must show the game's loading screen from the moment its connection drops, through the
-- host's load and its own, until the host lets go; then it is removed.
-- Run: tools/run-test.ps1 -Scenario transition -Fixture coop-zone -Headless     Mutation: notransition (no hold, no guest screen)
-- Headless proves the widget state (FadeGoal, text, in viewport), not what is drawn: see docs/spikes/PT6-immersion.md for screenshots.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local log = T.log
    local got = {}
    local function has(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind] ~= nil
    end
    local function screen()
        local gi = T.first("DrivingGameInstance")
        local ls = gi and gi.LoadingScreenUserWidget
        return ls and ls:IsValid() and ls or nil
    end
    local function lsText() local ls = screen(); return ls and ls.CurrentStateText:GetText():ToString() or "" end
    local fixture = (os.getenv("PT_FIXTURE") or ""):match("[^,]+") or "coop-zone"

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture(fixture)) do add(s) end
        add({ check = "host_listen_zone", timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() and T.map() ~= "RB_Garage" end })
        add({ check = "host_guest_in_zone", timeout = 300, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 5 })
        local map0, held, heldText = nil, false, ""
        add({ run = function()
            map0 = T.map()
            -- the hold can be short (a guest that connected while the host spawned is ready within a second): sampled every 50 ms
            LoopInGameThreadWithDelay(50, function()
                pcall(function()
                    local ls = screen()
                    if ls and T.map() ~= map0 and T.myPawn() ~= nil and ls.FadeGoal == 1.0 and lsText():find("WAITING FOR", 1, true) then
                        if not held then log("PT|info host loading screen held: %s", lsText()) end
                        held, heldText = true, lsText()
                    end
                end)
            end)
            StaticFindObject("/Game/Systems/ScriptingLibraries/BFL_ProgressionHelpers.Default__BFL_ProgressionHelpers_C"):TravelToNextLeg(T.world())
        end })
        add({ check = "host_on_next_zone", timeout = 300, cond = function() return T.map() ~= map0 and T.netMode() == "listen" and L.gameplay(T.map()) and T.myPawn() ~= nil end })
        add({ check = "host_guest_back_in_zone", timeout = 300, cond = function() return L.guestChar() ~= nil end })
        add({ check = "host_held_loading_screen_for_guest", timeout = 20, cond = function() return held end })
        add({ check = "host_released_loading_screen", timeout = 20, cond = function()
            local ls = screen()
            return ls ~= nil and ls.FadeGoal == 0.0 and ls.StatusBox:GetRenderOpacity() == 0.0
        end })
        add({ check = "host_guest_done", timeout = 300, cond = function() return has("t.transdone") end })
        add({ wait = 3 })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    add({ check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() ~= "RB_Garage" and T.map() ~= "RB_MainMenu" and T.cls(T.myPawn()) == T.CHAR end })
    local map0, dropped, lsAtDrop, lsBeforePawn, textBeforePawn = nil, nil, false, false, ""
    add({ run = function()
        map0 = T.map()
        LoopInGameThreadWithDelay(50, function()
            pcall(function()
                local ls = screen()
                if not ls then return end
                local inView = ls:IsInViewport()
                -- the drop: the world loses its NetDriver (GameState and the world stay, netMode() is not to be trusted here)
                if T.map() == map0 and not T.world().NetDriver:IsValid() then
                    dropped = dropped or os.clock()
                    if inView then lsAtDrop = true end
                end
                if T.map() ~= map0 and T.map() ~= "RB_MainMenu" and T.myPawn() == nil and inView then lsBeforePawn, textBeforePawn = true, lsText() end
            end)
        end)
    end })
    add({ check = "client_dropped_for_host_load", timeout = 300, cond = function() return dropped ~= nil end })
    add({ wait = 2 })
    add({ check = "client_screen_shown_at_drop", timeout = 1, cond = function() log("PT|info guest screen at drop=%s", tostring(lsAtDrop)); return lsAtDrop end })
    add({ check = "client_on_next_zone", timeout = 600, cond = function() return T.netMode() == "client" and T.map() ~= map0 and T.map() ~= "RB_MainMenu" end })
    add({ check = "client_has_character", timeout = 300, cond = function() return T.cls(T.myPawn()) == T.CHAR end })
    add({ check = "client_screen_shown_until_placed", timeout = 1, cond = function() log("PT|info guest screen before pawn=%s text=%s", tostring(lsBeforePawn), textBeforePawn); return lsBeforePawn end })
    add({ check = "client_screen_removed_after_placed", timeout = 20, cond = function() local ls = screen(); return ls ~= nil and not ls:IsInViewport() end })
    add({ run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.transdone", "1") end })
    add({ wait = 3 })
    return steps
end
