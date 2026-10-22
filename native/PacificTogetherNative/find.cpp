// Object lookup by full path through the engine's hash tables only.
// UE4SS's StaticFindObject falls back to a scan of every object by full name when the hash misses: 25-45 ms per miss in a
// zone (measured 2026-10-22), and the mod looks up not-yet-loaded classes in loops (hook retries, LoadAsset checks).
//   PTNative_Find(path) -> UObject | nil     never scans while the hash tables are up (UE4SS self test passed)
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <LuaType/LuaUObject.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UObjectHashTables.hpp>
#include <Unreal/UnrealInitializer.hpp>

using namespace RC;
using namespace RC::Unreal;

auto pt_register_find(const LuaMadeSimple::Lua& lua) -> void
{
    lua.register_function("PTNative_Find", [](const LuaMadeSimple::Lua& l) -> int {
        auto path = ensure_str(l.get_string());
        UObject* found = UnrealInitializer::ShouldUseHashTables()
                ? FUObjectHashTables::StaticFindObjectByPath(nullptr, path.c_str())
                : UObjectGlobals::StaticFindObject(nullptr, nullptr, path);
        if (!found) { l.set_nil(); return 1; }
        LuaType::auto_construct_object(l, found);
        return 1;
    });
}
