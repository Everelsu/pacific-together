-- S5 abrupt disconnect with the real mod. Life 1 of the guest joins, then the runner kills its process (no QuitToMenu,
-- no close: the host only sees the connection die). The host must stay up, lose the guest's player controller and
-- character, and a new guest process (life 2, same PT_JOIN) must join again and get a character. Life 2 then leaves
-- the polite way (QuitToMenu) and the host must clean up the same way.
-- sessionabrupt: in the garage. sessionabruptzone: the host loads the zone fixture (a run map) first: -Fixture zone.
-- Mutation nokill: the guest is never killed, so the host's "guest gone" check fails.
return function(T, zone)
    local L = require("scenarios.sessionlib")(T)
    local life = tonumber(os.getenv("PT_LIFE") or "1")
    local mapName = zone and "Rural_Forest_Radio_Scylla_02" or "RB_Garage"
    local function alone() return T.netMode() == "listen" and T.listening() and T.pcs() == 1 and #L.chars() == 1 end
    -- in the garage the guest stands next to the host's character; in a zone the host may sit in the car, so only the pairing counts
    local function hostSees() return zone and (L.guestChar() ~= nil and L.managerIsMine()) or L.hostSeesGuest() end
    local function guestSees() return zone and (T.cls(T.myPawn()) == T.CHAR) or L.guestSeesHost() end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        if zone then
            for _, s in ipairs(T.loadFixture("zone")) do add(s) end
        else
            add(T.onMap("RB_MainMenu", 90))
            add({ wait = 5 })
            add({ run = function() T.console("open " .. T.GARAGE) end })
        end
        add({ check = "host_listen", timeout = 120, cond = function() return T.netMode() == "listen" and T.listening() and T.map() == mapName end })
        add({ check = "host_guest_in_1", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 8 })
        add({ check = "host_sees_guest_1", timeout = 20, cond = hostSees })
        -- the guest's process dies now (its test asks the runner)
        add({ check = "host_abrupt_guest_gone", timeout = 200, cond = function()
            T.log("PT|info abrupt wait pcs=%d chars=%d remotes=%d", T.pcs(), #L.chars(), #L.remotePCs())
            return alone()
        end })
        add({ check = "host_abrupt_stays_up", timeout = 45, cond = L.holds(20, alone) })
        add({ run = function() T.log("PT|runner relaunch side=client n=1") end })
        add({ check = "host_guest_in_2", timeout = 300, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 8 })
        add({ check = "host_sees_guest_2", timeout = 20, cond = hostSees })
        add({ run = function() T.log("PT|info guest rejoined %s", L.describe()) end })
        -- life 2 quits to the menu on purpose
        add({ check = "host_polite_guest_gone", timeout = 200, cond = function()
            T.log("PT|info polite wait pcs=%d chars=%d remotes=%d", T.pcs(), #L.chars(), #L.remotePCs())
            return alone()
        end })
        add({ check = "host_polite_stays_up", timeout = 45, cond = L.holds(20, alone) })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    local function add(s) steps[#steps + 1] = s end
    add({ check = "client_in_" .. life, timeout = 240, cond = function() return T.netMode() == "client" and T.map() == mapName and guestSees() end })
    if life == 1 then
        add({ wait = 10 })
        add({ run = function()
            T.log("PT|info client dies now")
            if T.MUTATE ~= "nokill" then T.log("PT|runner kill side=client n=1") end
        end })
        add({ wait = 600 })
    else
        add({ wait = 10 })
        add({ run = function() T.quitToMenu() end })
        add({ check = "client_menu_after_leave", timeout = 60, cond = function() return T.map() == "RB_MainMenu" end })
        -- the leave is deliberate: no rejoin
        add({ check = "client_stays_out", timeout = 60, cond = L.holds(30, function() return T.netMode() ~= "client" end) })
    end
    return steps
end
