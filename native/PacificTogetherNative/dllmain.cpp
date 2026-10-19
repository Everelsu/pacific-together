#include <Mod/CppUserModBase.hpp>
#include <DynamicOutput/DynamicOutput.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <Unreal/Hooks/Hooks.hpp>
#include <Unreal/UEngine.hpp>
#include <Unreal/FWorldContext.hpp>
#include <Unreal/World.hpp>
#include <Unreal/FURL.hpp>
#include <Unreal/AActor.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UFunction.hpp>

#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

using namespace RC;
using namespace RC::Unreal;

static constexpr const char* NATIVE_VERSION = "0.0.3";

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

// S5: when a guest's connection closes, APlayerController::Destroyed destroys the guest's character while it is still
// possessed, and the host crashes. Unpossess first (the order the Lua cleanup uses before travel), then destroy.
using DestroyedFn = void (*)(UObject*);
static DestroyedFn g_pc_destroyed{};

static auto call(UObject* obj, const TCHAR* fn) -> void
{
    if (auto f = obj->GetFunctionByNameInChain(fn)) obj->ProcessEvent(f, nullptr);
}

static auto guarded_pc_destroyed(UObject* pc) -> void
{
    auto pawn = pc->GetValuePtrByPropertyNameInChain<UObject*>(STR("Pawn"));
    auto player = pc->GetValuePtrByPropertyNameInChain<UObject*>(STR("Player"));
    auto role = pc->GetValuePtrByPropertyNameInChain<uint8_t>(STR("Role"));
    // ROLE_Authority with no UPlayer = a remote player leaving the server
    if (pawn && *pawn && player && !*player && role && *role == 3)
    {
        auto p = *pawn;
        Output::send<LogLevel::Verbose>(STR("[PacificTogether] PT|native leaving player {} unpossess {}\n"), pc->GetFullName(), p->GetFullName());
        call(pc, STR("UnPossess"));
        call(p, STR("K2_DestroyActor"));
    }
    g_pc_destroyed(pc);
}

// BP controllers use the vtable of their native parent, so the CDO's vtable is every instance's
static auto patch_pc_destroyed() -> void
{
    auto cdo = UObjectGlobals::StaticFindObject<UObject*>(nullptr, nullptr, STR("/Script/PenDriverPro.Default__BasePlayerController"));
    if (!cdo)
    {
        Output::send<LogLevel::Error>(STR("[PacificTogether] PT|error native no BasePlayerController CDO\n"));
        return;
    }
    auto offset = AActor::VTableLayoutMap.at(STR("Destroyed"));
    auto slot = reinterpret_cast<void**>(*reinterpret_cast<uint8_t**>(cdo) + offset);
    DWORD old{};
    if (!VirtualProtect(slot, sizeof(void*), PAGE_READWRITE, &old)) return;
    g_pc_destroyed = reinterpret_cast<DestroyedFn>(*slot);
    *slot = reinterpret_cast<void*>(&guarded_pc_destroyed);
    VirtualProtect(slot, sizeof(void*), old, &old);
    Output::send<LogLevel::Verbose>(STR("[PacificTogether] PT|native controller destroyed patched slot=0x{:x}\n"), offset);
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
        ModVersion = STR("0.0.3");
        ModDescription = STR("Pacific Together native layer");
        ModAuthors = STR("Pacific Together contributors");
        Output::send<LogLevel::Verbose>(STR("[PacificTogether] PT|native loaded\n"));
    }

    auto on_unreal_init() -> void override
    {
        // the first LoadMap (boot -> menu) hands us the live engine; patch its vtable then
        Hook::RegisterLoadMapPreCallback([](auto&, UEngine* engine, FWorldContext&, FURL, UPendingNetGame*, FString&) {
            if (!g_load_map) patch_load_map(engine);
            if (!g_pc_destroyed) patch_pc_destroyed();
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
        }
    }
};

extern "C"
{
    __declspec(dllexport) CppUserModBase* start_mod() { return new PacificTogetherNative(); }
    __declspec(dllexport) void uninstall_mod(CppUserModBase* mod) { delete mod; }
}
