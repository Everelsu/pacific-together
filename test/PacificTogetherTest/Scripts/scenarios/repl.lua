-- An open session for the live console (tools/repl.ps1). The host opens PT_MAP (default the garage) as a listen
-- server, the client joins, then both hold until `tools/repl.ps1 -Stop` (or the runner's -Seconds run out).
-- Run it in the background: run-test.ps1 -Scenario repl -Seconds 3600 [-Clients 1] [-Headless]
return function(T)
    local mapPath = os.getenv("PT_MAP") or T.GARAGE
    local mapName = mapPath:match("([^/]+)$")
    local hold = { check = "repl_session_stopped", timeout = 86400, cond = T.replStopped }
    local fixture = (os.getenv("PT_FIXTURE") or ""):match("[^,]+") -- first of a comma list
    if T.ROLE == "host" and fixture and fixture ~= "" then -- load the fixture save, stay standalone (no listen: a map reload would drop the loaded state)
        local steps = T.loadFixture(fixture)
        -- a selected gateway is not in the save: "...gateway" fixtures reopen it with the ARC screen's own call (nearest portal)
        if fixture:find("gateway") then
            steps[#steps + 1] = { wait = 5 }
            steps[#steps + 1] = { run = function()
                local car, best, bd = T.first("BP_PlayerCarNew_C"), nil, nil
                local c = car and car:K2_GetActorLocation()
                for _, p in ipairs(FindAllOf("BP_LevelTransition_ExitPortal_C") or {}) do
                    local l = p:K2_GetActorLocation()
                    local d = c and math.abs(l.X) > 1 and ((l.X - c.X) ^ 2 + (l.Y - c.Y) ^ 2)
                    if d and (not bd or d < bd) then best, bd = p, d end
                end
                local sm = T.first("BP_StormManager_C")
                if best and sm and not (sm.EvolvedGatewayExit and sm.EvolvedGatewayExit:IsValid()) then sm["Select Exit Portal Actor"](sm, best) end
                T.log("PT|info gateway reopened %s", tostring(best and math.sqrt(bd) / 100))
            end }
        end
        steps[#steps + 1] = hold
        return steps
    end
    if T.ROLE == "host" then
        return {
            T.onMap("RB_MainMenu", 90),
            { run = function() T.console("open " .. mapPath .. "?listen") end },
            { check = "repl_host_on_map", timeout = 180, cond = function() return T.map() == mapName and T.netMode() == "listen" end },
            hold,
        }
    end
    -- the shipping mod joins (PT_JOIN, run-test's AutoJoin) so it also rejoins after the host's map loads (junctions)
    return { T.onMap("RB_MainMenu", 90),
             { check = "repl_client_joined", timeout = 240, cond = function() return T.netMode() == "client" and T.map() ~= "RB_MainMenu" end },
             hold }
end
