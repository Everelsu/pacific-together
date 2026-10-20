-- X13 diagnostic, one game: which loaded materials could draw the other player's body instead of WorldGridMaterial?
-- Logs every material of the garage whose name hints at a person, and what the own character's meshes use.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local hints = { "player", "character", "skin", "body", "human", "cloth", "jacket", "arm", "hand", "glove", "mannequin", "survivor" }
    local function scan()
        local n = 0
        for _, cls in ipairs({ "Material", "MaterialInstanceConstant" }) do
            for _, m in ipairs(FindAllOf(cls) or {}) do
                local name = T.name(m)
                local low = name:lower()
                for _, h in ipairs(hints) do
                    if low:find(h, 1, true) then T.log("PT|info mat %s", name); n = n + 1; break end
                end
            end
        end
        for _, c in ipairs(FindAllOf("SkeletalMeshComponent") or {}) do
            if T.inWorld(c) and T.name(c):find("PDP_MainCharacter", 1, true) then
                for i = 0, c:GetNumMaterials() - 1 do T.log("PT|info own %s slot %d %s", T.name(c), i, T.name(c:GetMaterial(i))) end
            end
        end
        T.log("PT|info mats listed=%d", n)
    end
    return {
        T.onMap("RB_MainMenu", 90),
        { wait = 5 },
        { run = function() T.console("open " .. T.GARAGE) end },
        { check = "mats_garage", timeout = 120, cond = function() return T.map() == "RB_Garage" and L.own() ~= nil end },
        { wait = 10 },
        { run = scan },
    }
end
