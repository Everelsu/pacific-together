-- X4 in a zone (interact.lua), observe only: the host places the guest at the host's lootable backpack and at an
-- abandoned-car door that only the host's run spawn pass creates; each side logs what it has there and surveys.
-- (Interacting failed: the guest's lootables are other actors in other places, run 20261020-113846-laneC-interactzone.)
local interact = require("scenarios.interact")
return function(T)
    return interact(T, { map = T.FOREST, mapName = "Wilderness_Forest_01", hostDelay = 20, hostTail = 30, targets = {
        { id = "loot", class = "BP_Lootable_Backpack_Civilian_C", observe = true },
        { id = "cardoor", class = "BP_TemplatePart_Door_C", observe = true },
    } })
end
