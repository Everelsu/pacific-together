-- M6 real two-account test, the host PC (-Clients 1, steps in docs/spikes/X6.md). The shipping mod does everything (steam.lua):
-- this only loads the garage and checks what it did. The guest PC runs steamplayguest. UE's traffic goes over Steam messages.
return function(T)
    local lobby
    local function stats() return PTNative_TunnelStats and PTNative_TunnelStats() or "" end
    local function stat(k) return tonumber(stats():match(k .. "=(%d+)")) or 0 end
    local function names()
        local out = {}
        for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
            if T.inWorld(pc) and pc.PlayerState:IsValid() then out[#out + 1] = (pc:IsLocalController() and "me:" or "guest:") .. pc.PlayerState:GetPlayerName():ToString() end
        end
        return table.concat(out, ",")
    end
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "steam_on_by_the_mod", timeout = 60, cond = function() return PTNative_SteamId ~= nil and PTNative_SteamId() ~= nil end },
        { wait = 5 },
        { run = function() T.console("open " .. T.GARAGE) end },
        { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
        { check = "steam_lobby_on_load", timeout = 90, cond = function() lobby = PTNative_SteamLobby(); return lobby ~= nil end },
        { check = "steam_rich_presence_connect", timeout = 30, cond = function()
            local _, back = PTNative_SteamRichPresence("connect")
            T.log("PT|info steam lobby=%s connect='%s' (the friends list should offer Join game now)", lobby, back)
            return back == "+connect_lobby " .. lobby
        end },
        { check = "host_guest_joined", timeout = 1200, cond = function() return T.pcs() == 2 end },
        { check = "host_own_name_is_persona", timeout = 30, cond = function()
            T.log("PT|info steam persona=%s names=%s", tostring(PTNative_SteamPersona()), names())
            return names():find("me:" .. PTNative_SteamPersona(), 1, true) ~= nil
        end },
        { run = function() T.log("PT|info steam names (the guest must be its Steam name, not its PC name): %s", names()) end },
        { wait = 120 },
        { check = "host_guest_held", timeout = 5, cond = function() return T.pcs() == 2 end },
        { check = "tunnel_carried_host", timeout = 10, cond = function()
            T.log("PT|info tunnel final %s", stats())
            return stats():find("link=steam", 1, true) ~= nil and stat("in") > 20 and stat("out") > 20
        end },
    }
end
