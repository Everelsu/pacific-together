-- S6 with the real mod: map changes with a guest connected, all through the game's own travel code.
-- Run: tools/run-test.ps1 -Scenario sessiontravel -Fixture garage -Headless [-Root .. -Port ..]
--   garage -> zone     BFL_ProgressionHelpers:TravelToNextLeg (the run start, BaseRouteState travel)
--   zone -> garage     gateway: the host picks an exit portal (StormManager "Select Exit Portal Actor"), then the portal's own
--                      call BP_ProgressionManager:TravelToGarage(2) (the portal's car-in-range trigger is not driven)
--   zone -> garage     death: BP_MainCharacterManager:OnPlayerDeathReturnTimer (checkpoint load or TravelToGarage(3))
--   zone -> garage     run failure: TravelToGarage(3), the call RunFinished_Failure makes
--   zone -> menu       the pause menu's save and quit: SaveGame(current slot, "", 1) + QuitToMenu (PDP_PauseMenu; its
--                      TravelToGarage(3, .., true) call is a garage return: return states 2 and 3 skip the SaveAndQuit
--                      branch), then the host resumes that mid-run save from the menu
-- Each time: the host's remote characters are gone before the teardown, the host listens on the new map and the guest is back
-- by itself, possessing a character, with the host's player controller still the host's manager character.
-- Mutation nokeep: after the first join the host turns auto-listen and keep-listen off, so the first map change drops the guest for good.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local M = T.MUTATE
    local slow = (M == "nokeep") and 0.25 or 1 -- a mutation must fail, not wait out every timeout
    local function to(s) return math.max(30, math.floor(s * slow)) end
    local function inZone() return L.gameplay(T.map()) and T.map() ~= "RB_Garage" end
    local function sceneReady() return T.myPawn() ~= nil and T.first("BP_PlayerCarNew_C") ~= nil end

    local atTeardown = { n = -1, maps = 0 }
    RegisterLoadMapPreHook(function(engine, worldp, url, pending)
        pcall(function()
            local w = worldp:get()
            if pending:get():IsValid() or not w:IsValid() or T.ROLE ~= "host" then return end
            local n = 0
            for _, pc in ipairs(L.remotePCs()) do if pc.Pawn:IsValid() then n = n + 1 end end
            atTeardown.n, atTeardown.maps = n, atTeardown.maps + 1
            T.log("PT|info teardown map=%s remote pawns=%d", T.map(), n)
        end)
    end)

    local function helpers() return StaticFindObject("/Game/Systems/ScriptingLibraries/BFL_ProgressionHelpers.Default__BFL_ProgressionHelpers_C") end
    local function pm() return T.first("BP_ProgressionManager_C") end
    local function selectGateway()
        local sm = T.first("BP_StormManager_C")
        for _, p in ipairs(FindAllOf("BP_LevelTransition_ExitPortal_C") or {}) do
            if p:IsValid() and not T.name(p):find("Engine/Transient", 1, true) then
                sm["Select Exit Portal Actor"](sm, p)
                T.log("PT|info gateway selected %s picked=%s", T.name(p), tostring(p.IsPickedExit))
                return
            end
        end
        T.log("PT|info no exit portal found")
    end

    -- guest sequence: the same steps on both sides, in the order the host changes maps
    local plan = {
        { id = "gateway", go = function() selectGateway(); pm():TravelToGarage(2, false, false, false, 1, {}) end },
        { id = "death", go = function() T.first("BP_MainCharacterManager_C"):OnPlayerDeathReturnTimer() end },
        { id = "failure", go = function() pm():TravelToGarage(3, false, false, false, 1, {}) end },
    }

    if T.ROLE == "host" then
        local mark
        local function teardownClean(id) return { check = id, timeout = 10, cond = function() return atTeardown.maps > mark and atTeardown.n == 0 end } end
        local function listens(id) return { check = id, timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() end } end
        local function guestBack(id) return { check = id, timeout = to(300), cond = function() return L.guestChar() ~= nil and L.managerIsMine() end } end
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen_garage", timeout = 30, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 5 })
        add({ run = function()
            if M == "nokeep" then
                T.log("PT|info nokeep autolisten=%s keep=%s", tostring(PTNative_SetAutoListen(false)), tostring(PTNative_SetKeepListen and PTNative_SetKeepListen(false)))
            end
            T.log("PT|info garage %s", L.describe())
        end })
        for _, p in ipairs(plan) do
            -- garage -> zone
            add({ run = function() mark = atTeardown.maps; T.log("PT|info %s: TravelToNextLeg", p.id); helpers():TravelToNextLeg(T.world()) end })
            add({ check = p.id .. "_host_in_zone", timeout = 240, cond = function() return inZone() and sceneReady() end })
            add(teardownClean(p.id .. "_cleanup_before_zone"))
            add(listens(p.id .. "_host_listens_zone"))
            add(guestBack(p.id .. "_guest_back_zone"))
            add({ wait = 8 })
            add({ run = function() T.log("PT|info %s zone %s", p.id, L.describe()) end })
            -- zone -> garage
            add({ run = function() mark = atTeardown.maps; T.log("PT|info %s: go", p.id); p.go() end })
            add({ check = p.id .. "_host_in_garage", timeout = 240, cond = function() return T.map() == "RB_Garage" and sceneReady() end })
            add(teardownClean(p.id .. "_cleanup_before_garage"))
            add(listens(p.id .. "_host_listens_garage"))
            add(guestBack(p.id .. "_guest_back_garage"))
            add({ wait = 8 })
            add({ run = function() T.log("PT|info %s garage %s", p.id, L.describe()) end })
        end
        -- save and quit mid-run: the host ends in the menu, resumes the run's save, the guest is back
        local quitSlot
        add({ run = function() mark = atTeardown.maps; helpers():TravelToNextLeg(T.world()) end })
        add({ check = "quit_host_in_zone", timeout = 240, cond = function() return inZone() and sceneReady() end })
        add(guestBack("quit_guest_back_zone"))
        add({ wait = 8 })
        add({ run = function()
            mark = atTeardown.maps
            local sm = T.saveMgr()
            quitSlot = sm.CurrentSaveSlot
            T.log("PT|info quit: SaveGame slot=%s ok=%s", tostring(quitSlot), tostring(sm:SaveGame(quitSlot, "", 1)))
            T.quitToMenu()
        end })
        add({ check = "quit_host_in_menu", timeout = 120, cond = function() return T.map() == "RB_MainMenu" and T.netMode() == "standalone" end })
        add(teardownClean("quit_cleanup_before_menu"))
        add({ wait = 15 })
        add({ run = function() T.saveMgr():UserLoadGame(quitSlot, 1, 0) end })
        add({ check = "quit_host_listens_zone", timeout = 240, cond = function() return inZone() and T.netMode() == "listen" and T.listening() end })
        add(guestBack("quit_guest_back_zone_resumed"))
        add({ wait = 5 })
        add({ check = "host_alive_at_end", timeout = 45, cond = L.holds(20, function() return T.netMode() == "listen" and T.pcs() == 2 end) })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    local function inMap(id, want)
        add({ check = id, timeout = to(300) + 240, cond = function()
            return T.netMode() == "client" and want(T.map()) and T.cls(T.myPawn()) == T.CHAR
        end })
    end
    local isGarage = function(m) return m == "RB_Garage" end
    local isZone = function(m) return L.gameplay(m) and m ~= "RB_Garage" end
    inMap("client_in_garage", isGarage)
    for _, p in ipairs(plan) do
        inMap(p.id .. "_client_in_zone", isZone)
        add({ run = function() T.log("PT|info %s client zone %s", p.id, L.describe()) end })
        inMap(p.id .. "_client_in_garage", isGarage)
    end
    inMap("quit_client_in_zone", isZone)
    add({ check = "quit_client_in_menu", timeout = 300, cond = function() return T.map() == "RB_MainMenu" end })
    inMap("quit_client_in_zone_resumed", isZone)
    add({ wait = 25 })
    return steps
end
