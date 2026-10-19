-- X6 two accounts, the guest PC (-Clients 1, steps in docs/spikes/X6.md): finds the host's lobby through the friends
-- list (or PT_STEAM_LOBBY), joins it, echoes over channel 1, then joins the host's garage at 10.77.0.1 through the Steam
-- tunnel and stays two minutes. The host runs steamhost.
return function(T)
    local me, host, lobby, echoes, n, nextOpen = nil, nil, nil, 0, 0, 0
    local port = T.HOST:match(":(%d+)$")
    local function show(v) return v == nil and "nil" or tostring(v) end
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "steam_on", timeout = 30, cond = function() return PTNative_SteamEnable(true) end },
        { run = function() me = PTNative_SteamId(); T.log("PT|info steam guest id=%s", show(me)) end },
        { check = "steam_relay_current", timeout = 60, cond = function() return PTNative_SteamRelayStatus() == 100 end },
        { check = "steam_found_friend_lobby", timeout = 600, cond = function()
            local friend
            lobby, friend = PTNative_SteamFriendLobby()
            lobby = os.getenv("PT_STEAM_LOBBY") or lobby
            if lobby then T.log("PT|info steam lobby=%s friend=%s", lobby, show(friend)) end
            return lobby ~= nil
        end },
        { run = function() PTNative_SteamJoinLobby(lobby) end },
        { check = "steam_lobby_joined", timeout = 60, cond = function()
            local id, status = PTNative_SteamLobby()
            T.log("PT|info steam join status=%s", show(status))
            return id == lobby
        end },
        { check = "steam_host_is_owner", timeout = 10, cond = function()
            local members
            host, members = PTNative_SteamLobbyMembers()
            T.log("PT|info steam owner=%s members=%s data=%s", show(host), show(members), show(PTNative_SteamLobbyData("pt_version")))
            return host ~= nil and host ~= me
        end },
        { check = "steam_echo", timeout = 120, cond = function() return echoes >= 3 end, tick = function()
            n = n + 1
            T.log("PT|info steam ping %d -> %s", n, show(PTNative_SteamSend(host, 1, "ping " .. n, true)))
            while true do
                local from, text = PTNative_SteamReceive(1)
                if not from then break end
                if text:match("^echo ") then echoes = echoes + 1 end
                T.log("PT|info steam guest got from=%s '%s'", from, text)
            end
        end },
        { run = function()
            -- X11: the first open may wait on the host's relay session
            StaticFindObject("/Script/OnlineSubsystemUtils.Default__IpNetDriver").ResolutionConnectionTimeout = 120
            T.log("PT|info tunnel steam=%s peer=%s", show(PTNative_TunnelSteam(0)), show(PTNative_TunnelPeer("10.77.0.1", "steam:" .. host)))
        end },
        { check = "guest_connected_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" end,
          tick = function(t)
              if t % 10 == 0 then T.log("PT|info %s %s", T.state(), PTNative_TunnelStats()) end
              if t < nextOpen or T.map() ~= "RB_MainMenu" or T.netMode() == "client" then return end
              nextOpen = t + 130
              T.console("open 10.77.0.1:" .. port)
          end },
        { wait = 120 },
        { check = "guest_still_connected", timeout = 5, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" end },
        { run = function()
            T.log("PT|info tunnel final %s", PTNative_TunnelStats())
            PTNative_SteamLeaveLobby()
        end },
    }
end
