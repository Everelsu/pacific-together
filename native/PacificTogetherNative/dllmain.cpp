#include <Mod/CppUserModBase.hpp>
#include <DynamicOutput/DynamicOutput.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <Unreal/Hooks/Hooks.hpp>
#include <Unreal/UEngine.hpp>
#include <Unreal/FWorldContext.hpp>
#include <Unreal/World.hpp>
#include <Unreal/FURL.hpp>

#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

#include "transport.hpp"

using namespace RC;
using namespace RC::Unreal;

auto pt_register_trace(const LuaMadeSimple::Lua& lua) -> void; // trace.cpp
auto pt_register_net(const LuaMadeSimple::Lua& lua) -> void;   // net.cpp
auto pt_register_mute(const LuaMadeSimple::Lua& lua) -> void;  // mute.cpp

static constexpr const char* NATIVE_VERSION = "0.0.4";

namespace pt_guard // guard.cpp
{
    auto install() -> void;
    auto register_lua(const LuaMadeSimple::Lua& l) -> void;
}

// X1b: native travel (Browse -> LoadMap) drops ?listen, so the host would come back standalone.
// MSVC x64 passes the by-value FURL as a pointer to the caller's temporary (the callee destroys it), so we take it
// as FURL* and edit it before the real LoadMap. UE4SS's own LoadMap callbacks only get copies.
using LoadMapFn = bool (*)(UEngine*, FWorldContext*, FURL*, UObject*, FString*);
static LoadMapFn g_load_map{};
static bool g_keep_listen{};
// S1: the host listens on every gameplay map, also the first one loaded from the standalone menu
static bool g_auto_listen{};

static auto is_listening(UObject* world) -> bool
{
    if (!world) return false;
    auto driver = *world->GetValuePtrByPropertyNameInChain<UObject*>(STR("NetDriver"));
    return driver && !*driver->GetValuePtrByPropertyNameInChain<UObject*>(STR("ServerConnection"));
}

static auto keep_listen_load_map(UEngine* engine, FWorldContext* context, FURL* url, UObject* pending, FString* error) -> bool
{
    if ((g_keep_listen || g_auto_listen) && !pending)
    {
        bool has = false;
        for (auto& op : url->Op) has = has || _wcsicmp(*op, STR("listen")) == 0;
        // the main menu stays standalone (QuitToMenu)
        bool menu = wcsstr(*url->Map, STR("MainMenu")) != nullptr;
        bool listening = is_listening(context->GetThisCurrentWorld().Get());
        bool add = !has && !menu && (listening || g_auto_listen);
        if (add) url->Op.Add(FString(STR("listen")));
        Output::send<LogLevel::Verbose>(STR("[PacificTogether] PT|native keeplisten map={} listening={} had={} added={}\n"),
                                        *url->Map, listening, has, add);
    }
    return g_load_map(engine, context, url, pending, error);
}

// Guest: the host's map change closes our connection and the engine browses to "?closed" = the main menu. While a
// session is wanted, browse straight back to the host instead: we wait on the old map until the host has loaded (no menu).
// A failed reconnect browses without "closed" and still ends in the menu, where session.lua's join() takes over.
using BrowseFn = int (*)(UEngine*, FWorldContext*, FURL*, FString*);
static BrowseFn g_browse{};
static std::wstring g_rejoin_host; // "ip" or "ip:port"; empty = off (PTNative_SetRejoin)

static auto rejoin_browse(UEngine* engine, FWorldContext* context, FURL* url, FString* error) -> int
{
    bool closed = false;
    for (auto& op : url->Op) closed = closed || _wcsicmp(*op, STR("closed")) == 0;
    if (closed && url->Host.Len() == 0 && !g_rejoin_host.empty())
    {
        auto host = g_rejoin_host;
        int port = 7777;
        if (auto colon = host.rfind(L':'); colon != std::wstring::npos)
        {
            port = _wtoi(host.c_str() + colon + 1);
            host = host.substr(0, colon);
        }
        url->Host = FString(host.c_str());
        url->Port = port;
        url->Op.Empty();
        Output::send<LogLevel::Verbose>(STR("[PacificTogether] PT|native rejoin browse {}:{} instead of the menu\n"), host, port);
    }
    return g_browse(engine, context, url, error);
}

// Swaps one virtual of the engine; Browse/TickWorldTravel call LoadMap and Browse through the vtable. UE4SS's detour stays behind ours.
static auto patch_slot(UEngine* engine, const wchar_t* name, void* mine) -> void*
{
    auto offset = UEngine::VTableLayoutMap.at(name);
    auto slot = reinterpret_cast<void**>(*reinterpret_cast<uint8_t**>(engine) + offset);
    DWORD old{};
    if (!VirtualProtect(slot, sizeof(void*), PAGE_READWRITE, &old))
    {
        Output::send<LogLevel::Error>(STR("[PacificTogether] PT|error native vtable protect failed {}\n"), name);
        return nullptr;
    }
    auto original = *slot;
    *slot = mine;
    VirtualProtect(slot, sizeof(void*), old, &old);
    Output::send<LogLevel::Verbose>(STR("[PacificTogether] PT|native {} patched slot=0x{:x} original={}\n"), name, offset, original);
    return original;
}

static auto patch_load_map(UEngine* engine) -> void
{
    g_load_map = reinterpret_cast<LoadMapFn>(patch_slot(engine, STR("LoadMap"), reinterpret_cast<void*>(&keep_listen_load_map)));
    // patch_load_map runs again while LoadMap is unpatched: never wrap Browse twice
    if (!g_browse) g_browse = reinterpret_cast<BrowseFn>(patch_slot(engine, STR("Browse"), reinterpret_cast<void*>(&rejoin_browse)));
}

// S4: the Steam build id of the running game, through the game's own steam_api64.dll; 0 when Steam is not up
static auto game_build() -> int
{
    auto steam = GetModuleHandleW(L"steam_api64.dll");
    if (!steam) return 0;
    auto apps = reinterpret_cast<void* (*)()>(GetProcAddress(steam, "SteamAPI_SteamApps_v008"));
    auto build_id = reinterpret_cast<int (*)(void*)>(GetProcAddress(steam, "SteamAPI_ISteamApps_GetAppBuildId"));
    void* self = apps ? apps() : nullptr;
    return self && build_id ? build_id(self) : 0;
}

class PacificTogetherNative : public CppUserModBase
{
  public:
    PacificTogetherNative() : CppUserModBase()
    {
        ModName = STR("PacificTogether");
        ModVersion = STR("0.0.4");
        ModDescription = STR("Pacific Together native layer");
        ModAuthors = STR("Pacific Together contributors");
        Output::send<LogLevel::Verbose>(STR("[PacificTogether] PT|native loaded\n"));
        pt_guard::install();
    }

    auto on_unreal_init() -> void override
    {
        // the first LoadMap (boot -> menu) hands us the live engine; patch its vtable then
        Hook::RegisterLoadMapPreCallback([](auto&, UEngine* engine, FWorldContext&, FURL, UPendingNetGame*, FString&) {
            if (!g_load_map) patch_load_map(engine);
        }, {true, true, STR("PacificTogether"), STR("PatchLoadMap")});
    }

    // Called after every Lua mod starts; ours and the test mod (PacificTogetherTest) get the functions.
    // Hook callbacks run in their own Lua state, so register everywhere.
    auto on_lua_start(StringViewType mod_name, LuaMadeSimple::Lua& lua, LuaMadeSimple::Lua& main_lua, LuaMadeSimple::Lua& async_lua, LuaMadeSimple::Lua* hook_lua)
            -> void override
    {
        if (!mod_name.starts_with(STR("PacificTogether"))) return;
        for (auto* l : {&lua, &main_lua, &async_lua, hook_lua})
        {
            if (!l) continue;
            pt_register_trace(*l);
            pt_register_net(*l);
            pt_register_mute(*l);
            pt_guard::register_lua(*l);
            l->register_function("PTNative_Version", [](const LuaMadeSimple::Lua& l) -> int {
                l.set_string(NATIVE_VERSION);
                return 1;
            });
            // PTNative_SetKeepListen(bool): while on, native travel from a listening host keeps listening. Returns whether LoadMap is patched.
            l->register_function("PTNative_SetKeepListen", [](const LuaMadeSimple::Lua& l) -> int {
                g_keep_listen = l.get_bool();
                l.set_bool(g_load_map != nullptr);
                return 1;
            });
            // PTNative_SetRejoin("ip[:port]" or ""): while set, a dropped connection browses back to that host instead of the menu.
            // Returns whether Browse is patched.
            l->register_function("PTNative_SetRejoin", [](const LuaMadeSimple::Lua& l) -> int {
                auto host = std::string(l.get_string());
                g_rejoin_host.assign(host.begin(), host.end());
                l.set_bool(g_browse != nullptr);
                return 1;
            });
            l->register_function("PTNative_GameBuild", [](const LuaMadeSimple::Lua& l) -> int {
                l.set_integer(game_build());
                return 1;
            });
            // PTNative_SetAutoListen(bool): while on, every non-menu map the host loads (not a client join) listens. Returns whether LoadMap is patched.
            l->register_function("PTNative_SetAutoListen", [](const LuaMadeSimple::Lua& l) -> int {
                g_auto_listen = l.get_bool();
                l.set_bool(g_load_map != nullptr);
                return 1;
            });
            transport_register(*l);
            steam_register(*l);
        }
    }
};

extern "C"
{
    __declspec(dllexport) CppUserModBase* start_mod() { return new PacificTogetherNative(); }
    __declspec(dllexport) void uninstall_mod(CppUserModBase* mod) { delete mod; }
}
