-- Steam playtest 2026-10-23 bugs #6 and #11: the host had "Pause game while in inventories" on, opened a menu and the guest
-- froze and was snapped back; the host's Esc pause showed nothing on the guest. Garage fixture, the guest walks to and fro
-- with real movement input; the host measures how far the guest's character travels on the host:
--   1. option PauseWhileInMenus=2, the host opens the crafting grid (OpenCraftUI, the game's own path: with that option it
--      pauses the world): the world is not paused and the guest still advances;
--   2. the host's Esc menu (as pausemenu.lua): the world IS paused, the guest's overlay shows "Paused by host" (the last
--      child of the overlay box), and after the menu closes the label is gone and the guest moves again.
-- Run: tools/run-test.ps1 -Scenario pausehost -Fixture garage -Headless
-- Mutation nopause: the mod lets the inventory pause through and shows no label: the grid and label checks FAIL.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local got = {}
    local function has(kind)
        while true do
            local k = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = true
        end
        return got[kind]
    end
    local function paused() return StaticFindObject("/Script/Engine.Default__GameplayStatics"):IsGamePaused(T.world()) end

    if T.ROLE == "host" then
        local function im() return T.first("BP_InventoryManager_C") end
        local function menu()
            local w = T.localPC():GetHUD().PauseMenuWidget
            if w:IsValid() and w:IsInViewport() and w.PDP_PauseMenu:GetVisibility() == 0 then return w.PDP_PauseMenu end
        end
        -- summed horizontal steps of the guest's character as the host sees it, sampled once a second by the checks
        local last, dist = nil, 0
        local function moved(id)
            return { check = id, timeout = 12, cond = function()
                local c = L.guestChar()
                if c then
                    local p = c:K2_GetActorLocation()
                    if last then dist = dist + math.sqrt((p.X - last.X) ^ 2 + (p.Y - last.Y) ^ 2) end
                    last = p
                end
                T.log("PT|info pausehost %s travelled %.0f uu paused=%s", id, dist, tostring(paused()))
                return dist > 10 and not paused()
            end }
        end
        local steps = { T.onMap("RB_MainMenu", 90) }
        for _, s in ipairs(T.loadFixture("garage", false)) do steps[#steps + 1] = s end
        local function add(s) steps[#steps + 1] = s end
        local function reset() add({ run = function() last, dist = nil, 0 end }) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 300, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 5 })
        add({ run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.walk", "1") end })
        add({ wait = 3 })
        reset(); add(moved("guest_walks_baseline"))
        add({ run = function()
            local s = T.first("DrivingGameUserSettings")
            s.PauseWhileInMenus = 2
            s.bPauseWhileInMenus = true
            s.PauseWhileInMenus_ByProfile = 2
            T.log("PT|info pausehost getter=%s", tostring(s:GetPauseWhileInMenus()))
            im():OpenCraftUI(0, true, true)
        end })
        add({ check = "host_grid_open", timeout = 10, cond = function()
            local open = {}
            im():IsPlayerMenuOpen(open, {})
            T.log("PT|info pausehost grid open=%s paused=%s", tostring(open.IsOpen), tostring(paused()))
            return open.IsOpen == true
        end })
        add({ wait = 1 })
        reset(); add(moved("guest_walks_while_grid_open"))
        add({ run = function() im():RequestPlayerMenuClose() end })
        add({ wait = 3 })
        add({ run = function() pcall(function() T.localPC():InpActEvt_PauseMenu_K2Node_InputActionEvent_35({ KeyName = FName("Escape") }) end) end })
        add({ check = "host_esc_menu_pauses", timeout = 10, cond = function() return menu() ~= nil and paused() end })
        add({ check = "guest_label_shown", timeout = 20, cond = function() return has("t.labelon") end })
        add({ wait = 3 })
        add({ run = function() menu():ActionPauseMenu(true) end })
        add({ check = "host_esc_menu_closed", timeout = 10, cond = function() return menu() == nil and not paused() end })
        add({ check = "guest_label_cleared", timeout = 20, cond = function() return has("t.labeloff") end })
        reset(); add(moved("guest_walks_after_resume"))
        add({ run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.pausedone", "") end })
        add({ wait = 5 })
        return steps
    end

    local walking, t0 = false, os.clock()
    local function banner()
        for _, b in ipairs(FindAllOf("VerticalBox") or {}) do
            if b:IsValid() and b:GetFName():ToString() == "PTOverlayBox" then
                local t = b:GetChildAt(b:GetChildrenCount() - 1)
                return t:GetVisibility() ~= 1 and t:GetText():ToString() or ""
            end
        end
    end
    LoopInGameThreadWithDelay(50, function()
        pcall(function()
            if not walking then return end
            local me = T.myPawn()
            if me and T.cls(me) == T.CHAR then
                local sign = math.floor((os.clock() - t0) / 1.5) % 2 == 0 and 1 or -1
                me:AddMovementInput({ X = sign, Y = 0, Z = 0 }, 1.0, false)
            end
        end)
    end)
    local on, off = false, false
    local function tell(k) PTNative_MsgToHost(T.localPC():GetAddress(), k, "") end
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end },
        { check = "client_walks_on_order", timeout = 300, cond = function() if has("t.walk") then walking = true end return walking end },
        { check = "client_sees_label_while_host_paused", timeout = 300, cond = function()
            local b = banner()
            if b and b:find("Paused by host", 1, true) and not on then on = true; tell("t.labelon") end
            return on
        end },
        { check = "client_label_cleared_after_resume", timeout = 300, cond = function()
            if on and not off and banner() == "" then off = true; tell("t.labeloff") end
            return off
        end },
        { check = "client_through_end", timeout = 300, cond = function() return has("t.pausedone") end },
        { wait = 3 },
    }
end
