-- D13 probe (docs/research/arc-device.md), one game in a zone. Reads the ARC state (Gobbler charge, exit portals)
-- and runs the host half of a "summon gateway" intent: BP_StormManager_C."Select Exit Portal Actor"(portal), the
-- call the ARC screen makes after a completed press. Mutation: noselect (the call is skipped).
return function(T)
    local part, sm, portal

    local function charge()
        local has, item, man = {}, {}, {}
        T.first("BP_CarManager_C"):GetGobblerItem(has, item, man)
        local cur, max = {}, {}
        if part then part:GetAnchorCharge(cur, max) end
        return tostring(has.HasItem), cur.CurrentCharge, max.MaxCharge
    end

    return {
        T.onMap("RB_MainMenu", 90),
        { wait = 5 },
        { run = function() T.console("open " .. T.FOREST) end },
        T.onMap("Wilderness_Forest_01", 150),
        { wait = 30 },
        { check = "arc_parts_present", timeout = 30, cond = function()
            part, sm = T.first("BP_Carpart_Internal_GobblerScreen_C"), T.first("BP_StormManager_C")
            local exits = {}
            for _, p in ipairs(FindAllOf("BP_LevelTransition_ExitPortal_C") or {}) do
                if T.inWorld(p) then table.insert(exits, p) end
            end
            portal = exits[1]
            local has, cur, max = charge()
            T.log("PT|info arc screenPart=%s storm=%s exits=%d gobblerItem=%s charge=%s/%s ableToChoose=%s exitSelected=%s",
                T.name(part), T.name(sm), #exits, has, tostring(cur), tostring(max),
                tostring(part and part.AbleToChooseExit), tostring(part and part.ExitSelected))
            return part ~= nil and sm ~= nil and portal ~= nil
        end },
        { run = function()
            if T.MUTATE ~= "noselect" then sm["Select Exit Portal Actor"](sm, portal) end
            T.log("PT|info selected %s", T.name(portal))
        end },
        { wait = 3 },
        -- the screen part's OnExitPortalSelected handler ran: exit marked, gateway flagged on the route whiteboard
        { check = "gateway_selected_by_host_call", timeout = 15, cond = function()
            local tag = { TagName = FName("WB.ActiveRun.GatewaySelected") }
            local wb = StaticFindObject("/Script/PenDriverPro.Default__BaseProgressionManager"):GetRouteWhiteboard(T.world())
            local set = wb:IsValid() and wb:TagExists(tag, true)
            local has, cur, max = charge()
            T.log("PT|info after select exitSelected=%s gatewayTag=%s charge=%s/%s evolved=%s", tostring(part.ExitSelected),
                tostring(set), tostring(cur), tostring(max), T.name(sm.EvolvedGatewayExit))
            return part.ExitSelected == true and set == true
        end },
        { wait = 10 },
    }
end
