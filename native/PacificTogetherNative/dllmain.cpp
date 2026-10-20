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

using namespace RC;
using namespace RC::Unreal;

auto pt_register_trace(const LuaMadeSimple::Lua& lua) -> void; // trace.cpp
auto pt_register_net(const LuaMadeSimple::Lua& lua) -> void;   // net.cpp

static constexpr const char* NATIVE_VERSION = "0.0.2";

// X1b: native travel (Browse -> LoadMap) drops ?listen, so the host would come back standalone.
// MSVC x64 passes the by-value FURL as a pointer to the caller's temporary (the callee destroys it), so we take it
// as FURL* and edit it before the real LoadMap. UE4SS's own LoadMap callbacks only get copies.
using LoadMapFn = bool (*)(UEngine*, FWorldContext*, FURL*, UObject*, FString*);
static LoadMapFn g_load_map{};
static bool g_keep_listen{};

static auto is_listening(UObject* world) -> bool
{
    if (!world) return false;
    auto driver = *world->GetValuePtrByPropertyNameInChain<UObject*>(STR("NetDriver"));
    return driver && !*driver->GetValuePtrByPropertyNameInChain<UObject*>(STR("ServerConnection"));
}

static auto keep_listen_load_map(UEngine* engine, FWorldContext* context, FURL* url, UObject* pending, FString* error) -> bool
{
    if (g_keep_listen && !pending)
    {
        bool has = false;
        for (auto& op : url->Op) has = has || _wcsicmp(*op, STR("listen")) == 0;
        // the main menu stays standalone (QuitToMenu)
        bool menu = wcsstr(*url->Map, STR("MainMenu")) != nullptr;
        bool listening = is_listening(context->GetThisCurrentWorld().Get());
        if (!has && !menu && listening) url->Op.Add(FString(STR("listen")));
        Output::send<LogLevel::Verbose>(STR("[PacificTogether] PT|native keeplisten map={} listening={} had={} added={}\n"),
                                        *url->Map, listening, has, !has && !menu && listening);
    }
    return g_load_map(engine, context, url, pending, error);
}

// LoadMap is virtual and Browse/TickWorldTravel call it through the vtable: swap the engine's slot, which keeps UE4SS's detour behind ours.
static auto patch_load_map(UEngine* engine) -> void
{
    auto offset = UEngine::VTableLayoutMap.at(STR("LoadMap"));
    auto slot = reinterpret_cast<void**>(*reinterpret_cast<uint8_t**>(engine) + offset);
    DWORD old{};
    if (!VirtualProtect(slot, sizeof(void*), PAGE_READWRITE, &old))
    {
        Output::send<LogLevel::Error>(STR("[PacificTogether] PT|error native vtable protect failed\n"));
        return;
    }
    g_load_map = reinterpret_cast<LoadMapFn>(*slot);
    *slot = reinterpret_cast<void*>(&keep_listen_load_map);
    VirtualProtect(slot, sizeof(void*), old, &old);
    Output::send<LogLevel::Verbose>(STR("[PacificTogether] PT|native loadmap patched slot=0x{:x} original={} ue4ss={}\n"), offset,
                                    reinterpret_cast<void*>(g_load_map), UEngine::LoadMapInternal.get_function_address());
}

class PacificTogetherNative : public CppUserModBase
{
  public:
    PacificTogetherNative() : CppUserModBase()
    {
        ModName = STR("PacificTogether");
        ModVersion = STR("0.0.2");
        ModDescription = STR("Pacific Together native layer");
        ModAuthors = STR("Pacific Together contributors");
        Output::send<LogLevel::Verbose>(STR("[PacificTogether] PT|native loaded\n"));
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
        }
    }
};

extern "C"
{
    __declspec(dllexport) CppUserModBase* start_mod() { return new PacificTogetherNative(); }
    __declspec(dllexport) void uninstall_mod(CppUserModBase* mod) { delete mod; }
}
