-- PT1 crash (playtest 1, P0): the host opens the pause menu with a guest in the garage. The playtest host crashed right
-- away (AV reading 0x178, PenDriverPro+0x3160a56). Two rounds, with "Pause game while in menus" on and then off: the host
-- opens the menu through its PlayerController's PauseMenu input event (CanOpenPauseMenu -> BP_UIManager Set Pause Menu
-- Opened), keeps it open, opens Settings from it, closes the menu through the menu's own PauseMenu action; the guest stays.
-- Run: tools/run-test.ps1 -Scenario pausemenu -Fixture garage -Headless
-- Mutation nopausefix: the mod gives the guest's controller no PlayerInput on the host: the host crashes, the run FAILS.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local HOLD = 30

    local got = {}
    local function has(kind)
        while true do
            local k = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = true
        end
        return got[kind]
    end

    if T.ROLE == "host" then
        local function ui() return T.first("BP_UIManager_C") end
        -- the HUD keeps the menu in the viewport; PDP_PauseMenu_Main SetVisible sets the inner menu Visible (0) or Collapsed
        local function menu()
            local w = T.localPC():GetHUD().PauseMenuWidget
            if w:IsValid() and w:IsInViewport() and w.PDP_PauseMenu:GetVisibility() == 0 then return w.PDP_PauseMenu end
        end
        local function paused() return StaticFindObject("/Script/Engine.Default__GameplayStatics"):IsGamePaused(T.world()) end
        local function open()
            -- the Esc key's input event on the host's controller, the way the game routes it
            local ok, err = pcall(function() T.localPC():InpActEvt_PauseMenu_K2Node_InputActionEvent_35({ KeyName = FName("Escape") }) end)
            T.log("PT|info pausemenu open by input ok=%s %s paused=%s", tostring(ok), tostring(err or ""), tostring(paused()))
        end
        local function close()
            local m = menu()
            local ok, err = pcall(function() m:ActionPauseMenu(true) end)
            T.log("PT|info pausemenu close by menu action ok=%s %s", tostring(ok), tostring(err or ""))
            if not ok then ui()["Set Pause Menu Opened"](ui(), false) end
        end
        local function settings()
            local ok, err = pcall(function() menu():BndEvt__PDP_MenuItem_Settings_K2Node_ComponentBoundEvent_6_Pressed__DelegateSignature(FName("Settings")) end)
            T.log("PT|info pausemenu settings ok=%s %s", tostring(ok), tostring(err or ""))
        end
        local function option(on)
            local s = T.first("DrivingGameUserSettings")
            s.PauseWhileInMenus = on and 1 or 0
            s.bPauseWhileInMenus = on
            T.log("PT|info pausemenu option PauseWhileInMenus=%d", s.PauseWhileInMenus)
        end
        local steps = {
            T.onMap("RB_MainMenu", 90),
        }
        for _, s in ipairs(T.loadFixture("garage", false)) do steps[#steps + 1] = s end
        local function add(s) steps[#steps + 1] = s end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 300, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 5 })
        for _, on in ipairs({ true, false }) do
            local tag = on and "on" or "off"
            add({ run = function() option(on); open() end })
            add({ check = "host_menu_open_" .. tag, timeout = 10, cond = function() return menu() ~= nil and paused() end })
            add({ wait = HOLD })
            add({ run = settings })
            add({ wait = 5 })
            add({ check = "host_menu_held_" .. tag, timeout = 5, cond = function() return L.guestChar() ~= nil end })
            add({ run = function() pcall(function() menu():OnSettingsClosed() end); close() end })
            add({ check = "host_menu_closed_" .. tag, timeout = 10, cond = function()
                T.log("PT|info pausemenu closed? menu=%s paused=%s", tostring(menu() ~= nil), tostring(paused()))
                return menu() == nil and not paused()
            end })
            add({ wait = 5 })
        end
        add({ check = "host_guest_still_here", timeout = 10, cond = function() return L.guestChar() ~= nil end })
        add({ run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.pausedone", "") end })
        add({ wait = 5 })
        return steps
    end

    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end },
        { check = "client_through_host_pauses", timeout = 300, cond = function() return has("t.pausedone") end },
        { wait = 3 },
    }
end
