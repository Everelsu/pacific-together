-- S5 with the real mod: the guest is dropped from the host N times (the host sends it back to its menu, as a network
-- drop would); each time the host must survive the guest's character going away and the guest's mod must rejoin by
-- itself. Mutation: kick (the drop is a ClientWasKicked refusal, so the guest's mod must stay out and rejoin fails).
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local N = 6

    if T.ROLE == "host" then
        local steps = {
            T.onMap("RB_MainMenu", 90),
            { wait = 5 },
            { run = function() T.console("open " .. T.GARAGE) end },
            { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
        }
        for i = 1, N do
            table.insert(steps, { check = "host_guest_in_" .. i, timeout = 240, cond = function() return L.guestChar() ~= nil end })
            table.insert(steps, { wait = 8 })
            table.insert(steps, { run = function()
                for _, pc in ipairs(L.remotePCs()) do
                    local text = FText("Pacific Together test: dropped " .. i)
                    if T.MUTATE == "kick" then pc:ClientWasKicked(text) end
                    pc:ClientReturnToMainMenuWithTextReason(text)
                    T.log("PT|info dropped guest %d %s", i, T.name(pc))
                end
            end })
            -- the guest's character goes with its connection; we stay up and alone
            table.insert(steps, { check = "host_guest_gone_" .. i, timeout = 60, cond = function() return T.pcs() == 1 and #L.chars() == 1 and T.listening() end })
        end
        table.insert(steps, { wait = 5 })
        return steps
    end

    local steps = { T.onMap("RB_MainMenu", 90) }
    for i = 1, N do
        table.insert(steps, { check = "client_in_" .. i, timeout = 240, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and L.guestSeesHost() end })
        table.insert(steps, { check = "client_dropped_" .. i, timeout = 60, cond = function() return T.map() == "RB_MainMenu" end })
    end
    return steps
end
