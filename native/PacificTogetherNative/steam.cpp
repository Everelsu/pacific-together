// X6: Steam through the game's own steam_api64.dll (flat API, SDK of SteamUser022 / Matchmaking009 / NetworkingMessages002).
// The game already ran SteamAPI_Init under appid 1458140 and pumps callbacks with RunCallbacks, so we never init, never
// switch to manual dispatch, and poll async results with ISteamUtils. Off until Lua calls PTNative_SteamEnable(true).
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

#include <cstddef>
#include <string>

#include "transport.hpp"

using RC::LuaMadeSimple::Lua;

static constexpr uint32_t APP_ID = 1458140;
static constexpr int CB_LOBBY_CREATED = 513, CB_LOBBY_ENTER = 504;

// SteamNetworkingIdentity is 136 bytes; SteamNetworkingMessage_t starts with data, size, conn, then the sender's identity
struct alignas(8) Identity
{
    uint8_t raw[136];
};
struct Message
{
    void* data;
    int size;
    uint32_t conn;
    int32_t id_type; // k_ESteamNetworkingIdentityType_SteamID = 16
    int32_t id_size;
    uint64_t id64;
};
struct LobbyCreated
{
    int32_t result;
    uint64_t lobby;
};
struct LobbyEnter
{
    uint64_t lobby;
    uint32_t permissions;
    bool locked;
    uint32_t response; // k_EChatRoomEnterResponseSuccess = 1
};
struct FriendGameInfo
{
    uint64_t game;
    uint32_t ip;
    uint16_t port, query_port;
    uint64_t lobby;
};
static_assert(sizeof(LobbyCreated) == 16 && sizeof(LobbyEnter) == 24 && sizeof(FriendGameInfo) == 24 && offsetof(Message, id64) == 24);

static struct
{
    void* (*SteamUser)();
    void* (*SteamFriends)();
    void* (*SteamMatchmaking)();
    void* (*SteamUtils)();
    void* (*SteamNetworkingMessages)();
    void* (*SteamNetworkingUtils)();
    uint64_t (*GetSteamID)(void*);
    uint32_t (*GetAppID)(void*);
    bool (*IsAPICallCompleted)(void*, uint64_t, bool*);
    bool (*GetAPICallResult)(void*, uint64_t, void*, int, int, bool*);
    uint64_t (*CreateLobby)(void*, int, int);
    uint64_t (*JoinLobby)(void*, uint64_t);
    void (*LeaveLobby)(void*, uint64_t);
    uint64_t (*GetLobbyOwner)(void*, uint64_t);
    int (*GetNumLobbyMembers)(void*, uint64_t);
    uint64_t (*GetLobbyMemberByIndex)(void*, uint64_t, int);
    bool (*SetLobbyData)(void*, uint64_t, const char*, const char*);
    const char* (*GetLobbyData)(void*, uint64_t, const char*);
    bool (*SetRichPresence)(void*, const char*, const char*);
    void (*ClearRichPresence)(void*);
    const char* (*GetFriendRichPresence)(void*, uint64_t, const char*);
    int (*GetFriendCount)(void*, int);
    uint64_t (*GetFriendByIndex)(void*, int, int);
    bool (*GetFriendGamePlayed)(void*, uint64_t, FriendGameInfo*);
    int (*SendMessageToUser)(void*, const Identity*, const void*, uint32_t, int, int);
    int (*ReceiveMessagesOnChannel)(void*, int, Message**, int);
    bool (*AcceptSessionWithUser)(void*, const Identity*);
    void (*SetSteamID64)(Identity*, uint64_t);
    void (*Release)(Message*);
    int (*GetRelayNetworkStatus)(void*, void*);
    void (*InitRelayNetworkAccess)(void*);
} s;
static void *g_user{}, *g_friends{}, *g_mm{}, *g_utils{}, *g_msgs{}, *g_netutils{};
static bool g_on{}, g_resolved{};
static uint64_t g_call{}, g_lobby{};
static int g_call_kind{};
static std::string g_lobby_status = "none";

template <class F> static auto resolve(HMODULE dll, F& slot, const char* name) -> bool
{
    slot = reinterpret_cast<F>(GetProcAddress(dll, name));
    if (!slot) pt_log("PT|error steam missing export %s", name);
    return slot != nullptr;
}

static auto resolve_all() -> bool
{
    // only the game's already loaded copy; loading one ourselves would mean a second, uninitialised Steam
    auto dll = GetModuleHandleW(L"steam_api64.dll");
    if (!dll) return pt_log("PT|error steam steam_api64.dll not loaded"), false;
    bool ok = true;
    ok &= resolve(dll, s.SteamUser, "SteamAPI_SteamUser_v022");
    ok &= resolve(dll, s.SteamFriends, "SteamAPI_SteamFriends_v017");
    ok &= resolve(dll, s.SteamMatchmaking, "SteamAPI_SteamMatchmaking_v009");
    ok &= resolve(dll, s.SteamUtils, "SteamAPI_SteamUtils_v010");
    ok &= resolve(dll, s.SteamNetworkingMessages, "SteamAPI_SteamNetworkingMessages_SteamAPI_v002");
    ok &= resolve(dll, s.SteamNetworkingUtils, "SteamAPI_SteamNetworkingUtils_SteamAPI_v004");
    ok &= resolve(dll, s.GetSteamID, "SteamAPI_ISteamUser_GetSteamID");
    ok &= resolve(dll, s.GetAppID, "SteamAPI_ISteamUtils_GetAppID");
    ok &= resolve(dll, s.IsAPICallCompleted, "SteamAPI_ISteamUtils_IsAPICallCompleted");
    ok &= resolve(dll, s.GetAPICallResult, "SteamAPI_ISteamUtils_GetAPICallResult");
    ok &= resolve(dll, s.CreateLobby, "SteamAPI_ISteamMatchmaking_CreateLobby");
    ok &= resolve(dll, s.JoinLobby, "SteamAPI_ISteamMatchmaking_JoinLobby");
    ok &= resolve(dll, s.LeaveLobby, "SteamAPI_ISteamMatchmaking_LeaveLobby");
    ok &= resolve(dll, s.GetLobbyOwner, "SteamAPI_ISteamMatchmaking_GetLobbyOwner");
    ok &= resolve(dll, s.GetNumLobbyMembers, "SteamAPI_ISteamMatchmaking_GetNumLobbyMembers");
    ok &= resolve(dll, s.GetLobbyMemberByIndex, "SteamAPI_ISteamMatchmaking_GetLobbyMemberByIndex");
    ok &= resolve(dll, s.SetLobbyData, "SteamAPI_ISteamMatchmaking_SetLobbyData");
    ok &= resolve(dll, s.GetLobbyData, "SteamAPI_ISteamMatchmaking_GetLobbyData");
    ok &= resolve(dll, s.SetRichPresence, "SteamAPI_ISteamFriends_SetRichPresence");
    ok &= resolve(dll, s.ClearRichPresence, "SteamAPI_ISteamFriends_ClearRichPresence");
    ok &= resolve(dll, s.GetFriendRichPresence, "SteamAPI_ISteamFriends_GetFriendRichPresence");
    ok &= resolve(dll, s.GetFriendCount, "SteamAPI_ISteamFriends_GetFriendCount");
    ok &= resolve(dll, s.GetFriendByIndex, "SteamAPI_ISteamFriends_GetFriendByIndex");
    ok &= resolve(dll, s.GetFriendGamePlayed, "SteamAPI_ISteamFriends_GetFriendGamePlayed");
    ok &= resolve(dll, s.SendMessageToUser, "SteamAPI_ISteamNetworkingMessages_SendMessageToUser");
    ok &= resolve(dll, s.ReceiveMessagesOnChannel, "SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel");
    ok &= resolve(dll, s.AcceptSessionWithUser, "SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser");
    ok &= resolve(dll, s.SetSteamID64, "SteamAPI_SteamNetworkingIdentity_SetSteamID64");
    ok &= resolve(dll, s.Release, "SteamAPI_SteamNetworkingMessage_t_Release");
    ok &= resolve(dll, s.GetRelayNetworkStatus, "SteamAPI_ISteamNetworkingUtils_GetRelayNetworkStatus");
    ok &= resolve(dll, s.InitRelayNetworkAccess, "SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess");
    if (!ok) return false;
    g_user = s.SteamUser(), g_friends = s.SteamFriends(), g_mm = s.SteamMatchmaking();
    g_utils = s.SteamUtils(), g_msgs = s.SteamNetworkingMessages(), g_netutils = s.SteamNetworkingUtils();
    pt_log("PT|native steam interfaces user=%p friends=%p matchmaking=%p utils=%p messages=%p netutils=%p", g_user, g_friends, g_mm, g_utils,
           g_msgs, g_netutils);
    return g_user && g_friends && g_mm && g_utils && g_msgs && g_netutils;
}

static auto identity(uint64_t id) -> Identity
{
    Identity i{};
    s.SetSteamID64(&i, id);
    return i;
}

auto steam_send(uint64_t id, int channel, const void* data, uint32_t size, int flags) -> int
{
    if (!g_on) return -1;
    auto who = identity(id);
    uint64_t t0 = GetTickCount64();
    int r = s.SendMessageToUser(g_msgs, &who, data, size, flags, channel);
    // this runs inside the game's sendto: a stall here is a game-thread hitch
    if (uint64_t ms = GetTickCount64() - t0; ms > 50) pt_log("PT|native steam slow send ms=%llu result=%d size=%u", ms, r, size);
    return r;
}

auto steam_receive(int channel, void (*on_msg)(uint64_t, const uint8_t*, uint32_t)) -> void
{
    if (!g_on) return;
    Message* msgs[32];
    int n;
    while ((n = s.ReceiveMessagesOnChannel(g_msgs, channel, msgs, 32)) > 0)
    {
        for (int i = 0; i < n; ++i)
        {
            on_msg(msgs[i]->id_type == 16 ? msgs[i]->id64 : 0, static_cast<const uint8_t*>(msgs[i]->data), uint32_t(msgs[i]->size));
            s.Release(msgs[i]);
        }
    }
}

// one async lobby call at a time (create or join), finished here when Steam has the result
static auto poll_lobby() -> void
{
    bool failed = false;
    if (!g_call || !s.IsAPICallCompleted(g_utils, g_call, &failed)) return;
    char b[160];
    if (g_call_kind == CB_LOBBY_CREATED)
    {
        LobbyCreated r{};
        bool got = s.GetAPICallResult(g_utils, g_call, &r, sizeof(r), CB_LOBBY_CREATED, &failed);
        if (got && !failed && r.result == 1) g_lobby = r.lobby;
        snprintf(b, sizeof(b), "created got=%d failed=%d result=%d", got, failed, r.result);
    }
    else
    {
        LobbyEnter r{};
        bool got = s.GetAPICallResult(g_utils, g_call, &r, sizeof(r), CB_LOBBY_ENTER, &failed);
        if (got && !failed && r.response == 1) g_lobby = r.lobby;
        snprintf(b, sizeof(b), "entered got=%d failed=%d response=%u locked=%d", got, failed, r.response, r.locked);
    }
    g_call = 0, g_lobby_status = b;
    pt_log("PT|native steam lobby %s lobby=%llu", b, g_lobby);
}

static auto id_arg(const Lua& l) -> uint64_t { return strtoull(lua_str_arg(l).c_str(), nullptr, 10); }
static auto push_id(const Lua& l, uint64_t id) -> void { l.set_string(std::to_string(id)); }
// every PTNative_Steam* function except Enable returns nil while Steam is off
#define STEAM_ON() if (!g_on) { l.set_nil(); return 1; }

auto steam_register(const Lua& lua) -> void
{
    // PTNative_SteamEnable(bool): the Lua switch; true resolves the game's Steam interfaces and checks the appid. Returns whether Steam is usable
    lua.register_function("PTNative_SteamEnable", [](const Lua& l) -> int {
        bool want = l.get_stack_size() >= 1 && l.get_bool();
        if (want && !g_resolved) g_resolved = resolve_all();
        g_on = want && g_resolved;
        if (g_on)
        {
            uint32_t app = s.GetAppID(g_utils);
            s.InitRelayNetworkAccess(g_netutils);
            pt_log("PT|native steam on appid=%u", app);
            if (app != APP_ID) pt_log("PT|error steam appid %u is not %u", app, APP_ID), g_on = false;
        }
        l.set_bool(g_on);
        return 1;
    });
    lua.register_function("PTNative_SteamId", [](const Lua& l) -> int {
        STEAM_ON();
        push_id(l, s.GetSteamID(g_user));
        return 1;
    });
    // PTNative_SteamRelayStatus() -> ESteamNetworkingAvailability (100 = current, <0 = failed)
    lua.register_function("PTNative_SteamRelayStatus", [](const Lua& l) -> int {
        STEAM_ON();
        l.set_integer(s.GetRelayNetworkStatus(g_netutils, nullptr));
        return 1;
    });
    // PTNative_SteamCreateLobby(maxMembers): friends-only lobby (ELobbyType 1); poll PTNative_SteamLobby
    lua.register_function("PTNative_SteamCreateLobby", [](const Lua& l) -> int {
        STEAM_ON();
        int max = l.get_stack_size() >= 1 && l.is_number() ? int(l.get_number()) : 2;
        g_call = s.CreateLobby(g_mm, 1, max), g_call_kind = CB_LOBBY_CREATED, g_lobby_status = "creating";
        pt_log("PT|native steam CreateLobby call=%llu", g_call);
        l.set_bool(g_call != 0);
        return 1;
    });
    lua.register_function("PTNative_SteamJoinLobby", [](const Lua& l) -> int {
        STEAM_ON();
        uint64_t id = id_arg(l);
        g_call = s.JoinLobby(g_mm, id), g_call_kind = CB_LOBBY_ENTER, g_lobby_status = "joining";
        pt_log("PT|native steam JoinLobby %llu call=%llu", id, g_call);
        l.set_bool(g_call != 0);
        return 1;
    });
    // PTNative_SteamLobby() -> lobby id or nil, status of the last create/join
    lua.register_function("PTNative_SteamLobby", [](const Lua& l) -> int {
        STEAM_ON();
        poll_lobby();
        if (g_lobby) push_id(l, g_lobby);
        else l.set_nil();
        l.set_string(g_lobby_status);
        return 2;
    });
    // PTNative_SteamLobbyMembers() -> owner id, comma-separated member ids
    lua.register_function("PTNative_SteamLobbyMembers", [](const Lua& l) -> int {
        STEAM_ON();
        std::string members;
        for (int i = 0, n = s.GetNumLobbyMembers(g_mm, g_lobby); i < n; ++i)
            members += (i ? "," : "") + std::to_string(s.GetLobbyMemberByIndex(g_mm, g_lobby, i));
        push_id(l, s.GetLobbyOwner(g_mm, g_lobby));
        l.set_string(members);
        return 2;
    });
    // PTNative_SteamLobbyData(key[, value]): sets when a value is given; returns the lobby's value for key
    lua.register_function("PTNative_SteamLobbyData", [](const Lua& l) -> int {
        STEAM_ON();
        auto key = lua_str_arg(l);
        if (l.get_stack_size() >= 1 && l.is_string()) s.SetLobbyData(g_mm, g_lobby, key.c_str(), lua_str_arg(l).c_str());
        auto v = s.GetLobbyData(g_mm, g_lobby, key.c_str());
        l.set_string(v ? v : "");
        return 1;
    });
    lua.register_function("PTNative_SteamLeaveLobby", [](const Lua& l) -> int {
        STEAM_ON();
        if (g_lobby) s.LeaveLobby(g_mm, g_lobby), pt_log("PT|native steam left lobby %llu", g_lobby);
        g_lobby = 0, g_lobby_status = "left";
        l.set_bool(true);
        return 1;
    });
    // PTNative_SteamRichPresence(key, value) -> set ok, our own value read back; no arguments clears all keys
    lua.register_function("PTNative_SteamRichPresence", [](const Lua& l) -> int {
        STEAM_ON();
        if (l.get_stack_size() < 1)
        {
            s.ClearRichPresence(g_friends);
            l.set_bool(true);
            return 1;
        }
        auto key = lua_str_arg(l), value = lua_str_arg(l);
        bool ok = s.SetRichPresence(g_friends, key.c_str(), value.c_str());
        auto back = s.GetFriendRichPresence(g_friends, s.GetSteamID(g_user), key.c_str());
        l.set_bool(ok);
        l.set_string(back ? back : "");
        return 2;
    });
    // PTNative_SteamFriendLobby() -> lobby id and friend id of the first Steam friend in this game who is in a lobby, or nil
    lua.register_function("PTNative_SteamFriendLobby", [](const Lua& l) -> int {
        STEAM_ON();
        for (int i = 0, n = s.GetFriendCount(g_friends, 4); i < n; ++i) // k_EFriendFlagImmediate
        {
            uint64_t f = s.GetFriendByIndex(g_friends, i, 4);
            FriendGameInfo g{};
            if (s.GetFriendGamePlayed(g_friends, f, &g) && (g.game & 0xFFFFFF) == APP_ID && g.lobby)
            {
                push_id(l, g.lobby);
                push_id(l, f);
                return 2;
            }
        }
        l.set_nil();
        return 1;
    });
    // PTNative_SteamSend(id, channel, text, reliable) -> EResult (1 = OK)
    lua.register_function("PTNative_SteamSend", [](const Lua& l) -> int {
        STEAM_ON();
        uint64_t id = id_arg(l);
        int channel = l.get_stack_size() >= 1 && l.is_number() ? int(l.get_number()) : 0;
        auto text = lua_str_arg(l);
        bool reliable = l.get_stack_size() >= 1 && l.get_bool();
        // k_nSteamNetworkingSend_Reliable 8, else Unreliable|NoNagle; AutoRestartBrokenSession 32
        l.set_integer(steam_send(id, channel, text.data(), uint32_t(text.size()), (reliable ? 8 : 1) | 32));
        return 1;
    });
    // PTNative_SteamReceive(channel) -> sender id, text of one waiting message, or nil
    lua.register_function("PTNative_SteamReceive", [](const Lua& l) -> int {
        STEAM_ON();
        int channel = l.get_stack_size() >= 1 && l.is_number() ? int(l.get_number()) : 0;
        Message* m{};
        if (s.ReceiveMessagesOnChannel(g_msgs, channel, &m, 1) < 1)
        {
            l.set_nil();
            return 1;
        }
        push_id(l, m->id_type == 16 ? m->id64 : 0);
        l.set_string(static_cast<const char*>(m->data), size_t(m->size));
        s.Release(m);
        return 2;
    });
    // PTNative_SteamAccept(id) -> whether a pending session from that user was accepted (false if none is pending)
    lua.register_function("PTNative_SteamAccept", [](const Lua& l) -> int {
        STEAM_ON();
        auto who = identity(id_arg(l));
        l.set_bool(s.AcceptSessionWithUser(g_msgs, &who));
        return 1;
    });
}
