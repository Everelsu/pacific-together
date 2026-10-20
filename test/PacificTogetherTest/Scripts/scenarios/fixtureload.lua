-- Loads every fixture save (garage, zone, gateway) with the game's own load path and checks what each one is.
-- Run: tools/run-test.ps1 -Scenario fixtureload -Fixture garage,zone,gateway -Clients 1 -Headless
-- Mutations: nofixture (nothing is loaded: the map checks fail), wrongfixture (the "gateway" step loads the zone save: the charge check fails).
return function(T)
    if T.ROLE ~= "host" then return { T.onMap("RB_MainMenu", 90) } end
    local steps = {}
    local function add(list) for _, s in ipairs(list) do steps[#steps + 1] = s end end
    local function check(id, cond) steps[#steps + 1] = { check = id, timeout = 1, cond = cond } end
    local GARAGE_LIKE_STOCK = 300 -- the stocked garage holds 457 items in its biggest container; a fresh garage 71

    add(T.loadFixture("garage"))
    check("garage_stocked", function() return T.maxContainerItems() >= GARAGE_LIKE_STOCK end)

    add(T.loadFixture("zone", false))
    check("zone_is_run_map", function() return T.map() ~= "RB_Garage" and #(FindAllOf("BP_LevelTransition_ExitPortal_C") or {}) > 0 end)
    check("zone_arc_not_full", function() return (T.arcCharge() or 99) < 7 end)

    add(T.loadFixture(T.MUTATE == "wrongfixture" and "zone" or "gateway", false))
    check("gateway_arc_charged", function() return (T.arcCharge() or 0) >= 7 end)
    return steps
end
