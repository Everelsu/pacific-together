-- Fixture saves (local/fixtures/<name>/, see docs/TESTING.md): tools/run-test.ps1 -Fixture <name>[,<name>] puts the .sav files into
-- the host copy's SaveGames and sets PT_FIXTURE. T.loadFixture(name) returns the steps that load that save through the game's own
-- UserLoadGame and finish once the fixture's map is up with the player's character in it. Each fixture has its own slot.
local FIXTURES = {
    garage = { slot = 7, map = "RB_Garage" },
    zone = { slot = 8, map = "Rural_Forest_Radio_Scylla_02" },
    gateway = { slot = 9, map = "Rural_Forest_Radio_Scylla_02" },
}

return function(T)
    T.FIXTURES = FIXTURES
    -- fromMenu (default true): wait for the main menu first; false chains after another fixture (the game loads from any map)
    function T.loadFixture(name, fromMenu)
        -- run-test.ps1 passes "name=slot:map,..." from a fixture's fixture.json (fixture_save fixtures, or a remade zone fixture
        -- on another run map: the game picks the zone at travel time); it wins over the table
        local slot, map = (os.getenv("PT_FIXTURE_SPEC") or ""):match("[^,]*" .. name:gsub("%p", "%%%0") .. "=(%d+):([^,]+)")
        local f = slot and { slot = tonumber(slot), map = map } or FIXTURES[name]
        assert(f, "unknown fixture " .. tostring(name))
        local steps = {}
        if fromMenu ~= false then steps[1] = T.onMap("RB_MainMenu", 90) end
        steps[#steps + 1] = { run = function()
            T.log("PT|info loadFixture %s slot=%d", name, f.slot)
            -- PT_MUTATE=nofixture: the load is never asked for, so the map check must fail
            if T.MUTATE ~= "nofixture" then T.saveMgr():UserLoadGame(f.slot, 1, 0) end
        end }
        steps[#steps + 1] = { check = "fixture_" .. name .. "_map", timeout = 120,
            cond = function() return T.map() == f.map and T.myPawn() ~= nil and T.first("BP_PlayerCarNew_C") ~= nil end }
        return steps
    end

    -- the ARC's charge as the game shows it (UMG_GobblerScreen text), nil when the ARC screen is missing
    function T.arcCharge()
        local scr = T.first("UMG_GobblerScreen_C")
        if not scr then return nil end
        scr:UpdateCurrentCharge()
        return tonumber(scr.CurrentChargeText:GetText():ToString())
    end
    -- biggest item container the game holds (the garage fixture is stocked by the DbgActEvt give events)
    function T.maxContainerItems()
        local n = 0
        for _, c in ipairs(FindAllOf("ItemContainer") or {}) do
            if c:IsValid() then n = math.max(n, c:GetNumItems()) end
        end
        return n
    end
end
