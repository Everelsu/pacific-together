-- X4 in a zone (interact.lua): a loot container both sides have, and an abandoned-car door that only the host's
-- run spawn pass creates (observe only: survey both sides with the guest standing at the host's copy).
local interact = require("scenarios.interact")
return function(T)
    return interact(T, { map = T.FOREST, mapName = "Wilderness_Forest_01", hostDelay = 20, targets = {
        { id = "loot", class = "BP_Lootable_Backpack_Civilian_C" },
        { id = "cardoor", class = "BP_TemplatePart_Door_C", observe = true },
    } })
end
