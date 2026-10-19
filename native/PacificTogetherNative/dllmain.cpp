#include <Mod/CppUserModBase.hpp>
#include <DynamicOutput/DynamicOutput.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>

using namespace RC;

static constexpr const char* NATIVE_VERSION = "0.0.1";

class PacificTogetherNative : public CppUserModBase
{
  public:
    PacificTogetherNative() : CppUserModBase()
    {
        ModName = STR("PacificTogether");
        ModVersion = STR("0.0.1");
        ModDescription = STR("Pacific Together native layer");
        ModAuthors = STR("Pacific Together contributors");
        Output::send<LogLevel::Verbose>(STR("[PacificTogether] PT|native loaded\n"));
    }

    // Called after the Lua mod of the same name starts. Hook callbacks run in their own Lua state, so register everywhere.
    auto on_lua_start(LuaMadeSimple::Lua& lua, LuaMadeSimple::Lua& main_lua, LuaMadeSimple::Lua& async_lua, LuaMadeSimple::Lua* hook_lua) -> void override
    {
        for (auto* l : {&lua, &main_lua, &async_lua, hook_lua})
        {
            if (l) l->register_function("PTNative_Version", [](const LuaMadeSimple::Lua& l) -> int {
                l.set_string(NATIVE_VERSION);
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
