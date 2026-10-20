-- Diagnostic, one game: spawn a second PDP_MainCharacter_C next to ours the way the session mod does, wait, destroy it;
-- many times. Does destroying a second character crash without any networking? PT_MUTATE: mat (draw it visible
-- like the mod does), ai (possess it with its default controller first).
local UEHelpers = require("UEHelpers")

return function(T)
    local L = require("scenarios.sessionlib")(T)
    local N, cycles, c, phaseAt = 15, 0, nil, 0
    local function spawn()
        local me = L.own()
        local l = me:K2_GetActorLocation()
        local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X, Y = l.Y + 150, Z = l.Z + 50 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
        local gs = UEHelpers.GetGameplayStatics()
        c = gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(T.world(), me:GetClass(), xf, 2, nil), xf)
        local cm = L.manager()
        if cm then cm.CharacterActor = me end
        if T.MUTATE == "mat" then
            local grid = StaticFindObject("/Engine/EngineMaterials/WorldGridMaterial.WorldGridMaterial")
            for i = 0, c.Mesh:GetNumMaterials() - 1 do c.Mesh:SetMaterial(i, grid) end
        end
        if T.MUTATE == "ai" then c:SpawnDefaultController() end
        T.log("PT|info churn spawn %d %s controller=%s", cycles + 1, T.name(c), T.name(c.Controller))
    end
    return {
        T.onMap("RB_MainMenu", 90),
        { wait = 5 },
        { run = function() T.console("open " .. T.GARAGE) end },
        { check = "churn_garage", timeout = 120, cond = function() return T.map() == "RB_Garage" and L.own() ~= nil end },
        { wait = 10 },
        { check = "churn_cycles", timeout = N * 15 + 60, cond = function() return cycles >= N end, tick = function(t)
            if t < phaseAt then return end
            if not c then
                spawn(); phaseAt = t + 8
            else
                T.log("PT|info churn destroy %d", cycles + 1)
                c:K2_DestroyActor(); c = nil; cycles = cycles + 1; phaseAt = t + 2
            end
        end },
        { check = "churn_alive", timeout = 10, cond = function() return #L.chars() == 1 end },
    }
end
