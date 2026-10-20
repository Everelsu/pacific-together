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
    return { T.onMap("RB_MainMenu", 90), T.join("repl_client_joined", mapName, 240, 30), hold }
end
