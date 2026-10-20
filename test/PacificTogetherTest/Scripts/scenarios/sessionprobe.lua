-- Diagnostic: after the mod spawned the guest's character, which game managers point at it? (single-reference
-- managers adopting the newest character would leave dangling references when it is removed)
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local function scan(tag, target)
        local tn, hits, n = target:GetFullName(), 0, 0
        for _, cls in ipairs({ "BaseManager", "GameInstance", "GameStateBase", "HUD", "PlayerController", "UserWidget", "ActorComponent" }) do
            for _, o in ipairs(FindAllOf(cls) or {}) do
                if o:IsValid() and not o:GetFullName():find("Default__", 1, true) then
                    n = n + 1
                    pcall(function()
                        o:GetClass():ForEachProperty(function(p)
                            local ok, v = pcall(function() return o[p:GetFName():ToString()] end)
                            if ok and type(v) == "userdata" and v.IsValid and pcall(function() return v:IsValid() end) and v:IsValid() and v.GetFullName and v:GetFullName() == tn then
                                hits = hits + 1
                                T.log("PT|info probe %s %s.%s -> %s", tag, o:GetFullName(), p:GetFName():ToString(), tn)
                            end
                        end)
                    end)
                end
            end
        end
        T.log("PT|info probe %s scanned=%d hits=%d", tag, n, hits)
    end
    if T.ROLE == "host" then
        return {
            T.onMap("RB_MainMenu", 90),
            { wait = 5 },
            { run = function() T.console("open " .. T.GARAGE) end },
            { check = "host_guest_possessed", timeout = 300, cond = function() return L.guestChar() ~= nil end },
            { wait = 10 },
            { run = function() scan("guest", L.guestChar()); scan("own", L.own()) end },
            { wait = 5 },
        }
    end
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_possessed", timeout = 300, cond = function() return T.cls(T.myPawn()) == T.CHAR end },
        { wait = 40 },
    }
end
