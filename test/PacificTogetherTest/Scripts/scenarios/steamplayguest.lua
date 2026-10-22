-- M6 real two-account test, the guest PC (-Clients 1, steps in docs/spikes/X6.md). Finds the friend's lobby (friends list, or
-- PT_STEAM_LOBBY=<id>), hands the connect string to the shipping mod (the same text Steam's Join game puts on the command line),
-- and checks the join that steam.lua does over Steam messages. The host PC runs steamplayhost.
return function(T)
    local function stats() return PTNative_TunnelStats and PTNative_TunnelStats() or "" end
    local function stat(k) return tonumber(stats():match(k .. "=(%d+)")) or 0 end
    -- own name first, then every PlayerState of the world (a guest has no controller of the host, but replicates its PlayerState)
    local function names()
        local pc, out = T.localPC(), {}
        local gs = T.world().GameState
        if gs:IsValid() then
            local a = gs.PlayerArray
            for i = 1, #a do if a[i]:IsValid() then out[#out + 1] = a[i]:GetPlayerName():ToString() end end
        end
        return "me:" .. (pc and pc.PlayerState:IsValid() and pc.PlayerState:GetPlayerName():ToString() or "?") .. " all:" .. table.concat(out, ",")
    end
    local sent = false
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "steam_on_by_the_mod", timeout = 60, cond = function() return PTNative_SteamId ~= nil and PTNative_SteamId() ~= nil end },
        -- PT_STEAM_WAIT_INVITE=1: do not feed the mod anything, wait for an overlay invite / Join game to arrive as a Steam callback (GameLobbyJoinRequested)
        { check = "steam_found_friend_lobby", timeout = 900, cond = function()
            if os.getenv("PT_STEAM_WAIT_INVITE") == "1" then T.log("PT|info waiting for an invite"); return true end
            local lobby, friend = PTNative_SteamFriendLobby()
            lobby = os.getenv("PT_STEAM_LOBBY") or lobby
            if not lobby then return false end
            T.log("PT|info steam lobby=%s friend=%s", lobby, tostring(friend))
            local f = assert(io.open(os.getenv("PT_STEAM_INBOX"), "w"))
            f:write("+connect_lobby ", lobby, "\n"); f:close()
            return true
        end },
        { check = "steam_joined_lobby", timeout = 900, cond = function() return PTNative_SteamLobby() ~= nil end },
        { check = "steam_tunnel_peer_mapped", timeout = 60, cond = function() return stats():find("link=steam", 1, true) ~= nil and stat("peers") >= 1 end },
        { check = "guest_connected_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" end,
          tick = function(t) if t % 10 == 0 then T.log("PT|info %s %s", T.state(), stats()) end end },
        { check = "guest_own_name_is_persona", timeout = 60, cond = function()
            T.log("PT|info steam persona=%s names=%s", tostring(PTNative_SteamPersona()), names())
            return names():find("me:" .. PTNative_SteamPersona(), 1, true) ~= nil
        end },
        { wait = 120 },
        { check = "guest_still_connected", timeout = 5, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" end },
        { check = "tunnel_carried_guest", timeout = 10, cond = function()
            T.log("PT|info tunnel final %s", stats())
            return stat("in") > 20 and stat("out") > 20
        end },
    }
end
