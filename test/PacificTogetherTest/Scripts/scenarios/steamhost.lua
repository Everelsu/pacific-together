-- X6 two accounts, the host PC (-Clients 1, steps in docs/spikes/X6.md): friends-only lobby with rich presence, garage
-- listen server, UE traffic through the Steam tunnel (channel 0), echo service on channel 1. The guest runs steamguest.
return function(T)
    local me, lobby, guest, echoed, serving = nil, nil, nil, 0, nil
    local function show(v) return v == nil and "nil" or tostring(v) end
    -- every half second: accept and greet new lobby members (sending to a user also accepts their session), echo channel 1
    local function serve()
        local _, members = PTNative_SteamLobbyMembers()
        for id in (members or ""):gmatch("%d+") do
            if id ~= me and id ~= guest then
                guest = id
                T.log("PT|info steam guest %s joined the lobby, accept=%s hello=%s", id, show(PTNative_SteamAccept(id)), show(PTNative_SteamSend(id, 1, "hello from host", true)))
            end
        end
        if guest then PTNative_SteamAccept(guest) end
        while true do
            local from, text = PTNative_SteamReceive(1)
            if not from then break end
            echoed = echoed + 1
            T.log("PT|info steam host got from=%s '%s' -> echo %s", from, text, show(PTNative_SteamSend(from, 1, "echo " .. text, true)))
        end
    end
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "steam_on", timeout = 30, cond = function() return PTNative_SteamEnable(true) end },
        { run = function() me = PTNative_SteamId(); T.log("PT|info steam host id=%s", show(me)) end },
        { check = "steam_relay_current", timeout = 60, cond = function() return PTNative_SteamRelayStatus() == 100 end },
        { run = function() PTNative_SteamCreateLobby(2) end },
        { check = "steam_lobby_created", timeout = 30, cond = function() lobby = PTNative_SteamLobby(); return lobby ~= nil end },
        { run = function()
            T.log("PT|info steam lobby=%s data=%s", lobby, show(PTNative_SteamLobbyData("pt_version", "0.0.1")))
            PTNative_SteamRichPresence("status", "Pacific Together test host")
            PTNative_SteamRichPresence("connect", "+connect_lobby " .. lobby)
            serving = LoopInGameThreadWithDelay(500, function()
                local ok, err = pcall(serve)
                if not ok then T.log("PT|error steam serve %s", tostring(err)) end
            end)
        end },
        { check = "steam_tunnel_on", timeout = 10, cond = function() return PTNative_TunnelSteam(0) end },
        { run = function() T.console("open " .. T.GARAGE .. "?listen") end },
        { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
        { check = "steam_guest_in_lobby", timeout = 900, cond = function() return guest ~= nil end },
        { check = "steam_echo_served", timeout = 300, cond = function() return echoed >= 3 end },
        { check = "host_two_pcs", timeout = 300, cond = function() return T.pcs() == 2 end,
          tick = function(t) if t % 10 == 0 then T.log("PT|info %s %s", T.state(), PTNative_TunnelStats()) end end },
        { wait = 120 },
        { check = "host_two_pcs_held", timeout = 5, cond = function() return T.pcs() == 2 end },
        { run = function() T.log("PT|info tunnel final %s", PTNative_TunnelStats()) end },
        { wait = 30 },
        { run = function()
            CancelDelayedAction(serving)
            PTNative_SteamRichPresence()
            PTNative_SteamLeaveLobby()
        end },
    }
end
