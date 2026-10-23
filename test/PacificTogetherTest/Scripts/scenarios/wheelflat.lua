-- pt3 #9: a flat tyre on the host's car is flat on the guest's car manager too (handling, audio, scan read GetPartFlat there).
-- The host gives the front right wheel the game's own SE_FlatTire status effect (it calls SetPartFlat); the guest must report that slot flat.
-- Run: tools/run-test.ps1 -Scenario wheelflat -Fixture zone -Headless
-- Mutation noflat: wheelflat.lua is off: the guest's wheel stays whole.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local mapName = "Rural_Forest_Radio_Scylla_02"
    local function flat(n)
        local cm, o = T.first("BP_CarManager_C"), {}
        cm:GetPartFlat({ TagName = FName("Car.Equip.Essentials." .. n) }, o)
        return o["Is Flat"] == true
    end
    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("zone")) do add(s) end
        add({ check = "host_listen", timeout = 120, cond = function() return T.netMode() == "listen" and T.listening() and T.map() == mapName end })
        add({ check = "host_guest_in", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 10 })
        add({ run = function()
            local cm, sm, o = T.first("BP_CarManager_C"), T.first("BP_StatusEffectManager_C"), {}
            cm:GetItemInstanceEquippedInSlot({ TagName = FName("Car.Equip.Essentials.WheelFR") }, o, {})
            sm:AddItemStatusEffect(o.Instance, StaticFindObject("/Game/Gameplay/StatusEffects/StatusEffects/FlatTire/SE_FlatTire.SE_FlatTire_C"))
        end })
        add({ check = "host_wheel_flat", timeout = 10, cond = function() return flat("WheelFR") end })
        add({ wait = 25 })
        return steps
    end
    local steps = { T.onMap("RB_MainMenu", 90) }
    steps[#steps + 1] = { check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == mapName and T.cls(T.myPawn()) == T.CHAR end }
    steps[#steps + 1] = { check = "guest_wheel_flat", timeout = 90, cond = function() return flat("WheelFR") and not flat("WheelFL") end }
    steps[#steps + 1] = { wait = 3 }
    return steps
end
