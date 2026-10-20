-- X6 solo (-Clients 1): what one Steam account in one game can check: the switch is off by default, the game's Steam
-- interfaces under appid 1458140, our SteamID, the relay network, a friends-only lobby with data, rich presence, a
-- message to ourselves. Cleans up (rich presence cleared, lobby left). Mutations: nosteam (the switch stays off, every
-- Steam check fails), steamearly (the switch is turned on before the off-by-default check).
return function(T)
    local me, lobby, status
    local function show(v) return v == nil and "nil" or tostring(v) end
    return {
        T.onMap("RB_MainMenu", 90),
        { run = function() if T.MUTATE == "steamearly" then PTNative_SteamEnable(true) end end },
        { check = "steam_off_by_default", timeout = 30, cond = function() return PTNative_SteamId ~= nil and PTNative_SteamId() == nil end },
        { check = "steam_on", timeout = 10, cond = function() return T.MUTATE ~= "nosteam" and PTNative_SteamEnable(true) end },
        { check = "steam_own_id", timeout = 10, cond = function()
            me = PTNative_SteamId()
            T.log("PT|info steam id=%s", show(me))
            return me ~= nil and me:match("^7656119%d+$") ~= nil
        end },
        -- SDR relay for an appid whose developer set nothing up for P2P
        { check = "steam_relay_current", timeout = 60, cond = function()
            local r = PTNative_SteamRelayStatus()
            T.log("PT|info steam relay status=%s", show(r))
            return r == 100
        end },
        { run = function() T.log("PT|info steam CreateLobby -> %s", show(PTNative_SteamCreateLobby(2))) end },
        { check = "steam_lobby_created", timeout = 30, cond = function()
            lobby, status = PTNative_SteamLobby()
            return lobby ~= nil
        end },
        { run = function() T.log("PT|info steam lobby=%s status=%s", show(lobby), show(status)) end },
        { check = "steam_lobby_owner_me", timeout = 10, cond = function()
            local owner, members = PTNative_SteamLobbyMembers()
            T.log("PT|info steam lobby owner=%s members=%s", show(owner), show(members))
            return me ~= nil and owner == me and members == me
        end },
        { check = "steam_lobby_data", timeout = 10, cond = function() return PTNative_SteamLobbyData("pt_version", "0.0.1") == "0.0.1" end },
        { check = "steam_rich_presence", timeout = 10, cond = function()
            local ok1, back1 = PTNative_SteamRichPresence("status", "Pacific Together test")
            local ok2, back2 = PTNative_SteamRichPresence("connect", "+connect_lobby " .. tostring(lobby))
            T.log("PT|info steam rich presence status=%s read='%s' connect=%s read='%s'", show(ok1), show(back1), show(ok2), show(back2))
            return ok1 == true and ok2 == true
        end },
        -- whether ISteamNetworkingMessages delivers to our own SteamID (the solo stand-in for a second account)
        { run = function()
            T.log("PT|info steam self send reliable -> %s", show(PTNative_SteamSend(me, 1, "self-ping reliable", true)))
            T.log("PT|info steam self send unreliable -> %s", show(PTNative_SteamSend(me, 1, "self-ping unreliable", false)))
        end },
        { wait = 10 },
        { run = function()
            local n = 0
            for _ = 1, 10 do
                local from, text = PTNative_SteamReceive(1)
                if not from then break end
                n = n + 1
                T.log("PT|info steam self received from=%s text='%s'", show(from), show(text))
            end
            T.log("PT|info steam self received %d messages, relay=%s", n, show(PTNative_SteamRelayStatus()))
            -- a burst like the tunnel's: the native layer logs any send slower than 50 ms
            local ok = 0
            for i = 1, 50 do if PTNative_SteamSend(me, 2, "burst " .. i, false) == 1 then ok = ok + 1 end end
            T.log("PT|info steam self burst sent=50 ok=%d", ok)
        end },
        { wait = 5 },
        { run = function()
            local n = 0
            while PTNative_SteamReceive(2) do n = n + 1 end
            T.log("PT|info steam self burst received=%d", n)
        end },
        { run = function()
            PTNative_SteamRichPresence()
            PTNative_SteamLeaveLobby()
        end },
        { check = "steam_cleaned_up", timeout = 10, cond = function()
            local _, back = PTNative_SteamRichPresence("status", "")
            return PTNative_SteamLobby() == nil and back == ""
        end },
    }
end
