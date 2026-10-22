-- M6 Steam session (steam.lua, session.lua, backpack.lua), -Clients 2 on one Steam account (docs/spikes/PT2-steam.md).
-- Host: the shipping mod opens a friends-only lobby by itself when a map listens (S1, D14), sets lobby data and the rich
-- presence "connect" string, puts the persona on the host's player. Guest: no PT_JOIN; the runner has PT_STEAM=1 and a
-- steam-inbox.txt path, the host test writes the connect string it read back from Steam into it (what Steam's command line
-- would carry), the guest mod parses it, joins the lobby, maps the host as 10.77.0.1 and connects through the tunnel.
-- With PT_STEAM_UDP=<port> set in the runner's shell the tunnel's link is loopback UDP instead of Steam messages (two
-- processes of one account cannot message each other, X6); everything else is the same code.
-- Mutation nosteamjoin: steam.lua does nothing, every check after the first FAILS.
return function(T)
    local port = T.HOST:match(":(%d+)$")
    local lobby
    local function stats() return PTNative_TunnelStats and PTNative_TunnelStats() or "" end
    local function stat(k) return tonumber(stats():match(k .. "=(%d+)")) or 0 end
    local function logText()
        local f = io.open("ue4ss/UE4SS.log", "rb")
        if not f then return "" end
        local t = f:read("a"); f:close()
        return t
    end
    -- every PlayerState of the world (a guest has no PlayerController of the host, but replicates its PlayerState)
    local function names()
        local out, gs = {}, T.world().GameState
        if gs:IsValid() then
            local a = gs.PlayerArray
            for i = 1, #a do if a[i]:IsValid() then out[#out + 1] = a[i]:GetPlayerName():ToString() end end
        end
        return out
    end
    local function allPersona()
        local p, n = PTNative_SteamPersona and PTNative_SteamPersona(), names()
        T.log("PT|info steam persona=%s names=%s", tostring(p), table.concat(n, ","))
        if not p or p == "" or #n < 2 then return false end
        for _, x in ipairs(n) do if x ~= p then return false end end
        return true
    end
    -- the mod enabled Steam by itself (PT_STEAM=1): nothing here calls PTNative_SteamEnable
    local modOn = { check = "steam_on_by_the_mod", timeout = 60, cond = function() return PTNative_SteamId ~= nil and PTNative_SteamId() ~= nil end }

    if T.ROLE == "host" then
        return {
            T.onMap("RB_MainMenu", 90),
            modOn,
            { wait = 5 },
            { check = "steam_no_lobby_in_menu", timeout = 5, cond = function() return PTNative_SteamLobby() == nil end },
            -- a plain map load; the mod's auto-listen makes it a host and steam.lua opens the lobby
            { run = function() T.console("open " .. T.GARAGE) end },
            { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
            { check = "steam_lobby_on_load", timeout = 90, cond = function() lobby = PTNative_SteamLobby(); return lobby ~= nil end },
            { check = "steam_lobby_data", timeout = 30, cond = function()
                local v, p = PTNative_SteamLobbyData("pt_version"), PTNative_SteamLobbyData("pt_port")
                T.log("PT|info steam lobby data version=%s port=%s", v, p)
                return v:match("^%d+%.%d+%.%d+") ~= nil and p == port
            end },
            { check = "steam_rich_presence_connect", timeout = 30, cond = function()
                local _, back = PTNative_SteamRichPresence("connect")
                T.log("PT|info steam connect='%s'", back)
                return back == "+connect_lobby " .. lobby
            end },
            -- the lobby we just created came back through a callback the mod registered on the game's Steam
            { check = "steam_callback_delivered", timeout = 30, cond = function()
                T.log("PT|info steam events %s", PTNative_SteamEventStats())
                return (tonumber(PTNative_SteamEventStats():match("504=(%d+)")) or 0) >= 1
            end },
            { check = "steam_tunnel_up_on_host", timeout = 10, cond = function() return not stats():find("link=none", 1, true) end },
            { run = function()
                local _, connect = PTNative_SteamRichPresence("connect")
                local f = assert(io.open(os.getenv("PT_STEAM_INBOX"), "w"))
                f:write(connect, "\n"); f:close()
                T.log("PT|info steam inbox written '%s'", connect)
            end },
            { check = "host_guest_joined", timeout = 300, cond = function() return T.pcs() == 2 end },
            { check = "host_names_from_steam", timeout = 60, cond = allPersona },
            { check = "host_guest_keyed_by_steamid", timeout = 120, cond = function() return logText():find("PT|bp host answers 7656119%d+ ") ~= nil end },
            { wait = 20 },
            { check = "host_guest_held", timeout = 5, cond = function() return T.pcs() == 2 end },
            { check = "tunnel_carried_host", timeout = 10, cond = function()
                T.log("PT|info tunnel final %s", stats())
                return stat("in") > 20 and stat("out") > 20 and stat("peers") >= 1
            end },
        }
    end
    return {
        T.onMap("RB_MainMenu", 90),
        modOn,
        { check = "steam_joined_lobby_from_connect_string", timeout = 240, cond = function()
            local l, status = PTNative_SteamLobby()
            T.log("PT|info steam guest lobby=%s status=%s", tostring(l), tostring(status))
            return l ~= nil
        end },
        { check = "steam_tunnel_peer_mapped", timeout = 60, cond = function() return not stats():find("link=none", 1, true) and stat("peers") >= 1 end },
        { check = "guest_connected_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" end,
          tick = function(t) if t % 10 == 0 then T.log("PT|info %s %s", T.state(), stats()) end end },
        { check = "guest_names_from_steam", timeout = 90, cond = allPersona },
        { wait = 20 },
        { check = "guest_still_connected", timeout = 5, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" end },
        { check = "tunnel_carried_guest", timeout = 10, cond = function()
            T.log("PT|info tunnel final %s", stats())
            return stat("in") > 20 and stat("out") > 20 and stat("peers") >= 1
        end },
    }
end
