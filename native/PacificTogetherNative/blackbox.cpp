// Crash black box: which UFunctions were running on the game thread when the game died. ProcessEvent pre/post callbacks
// keep the stack of active calls (pointers only) and a ring of the last finished ones; guard.cpp appends
// pt_blackbox_dump() to our crash marker. Names are resolved only then, each behind SEH, because the process is broken.
//   PTNative_BlackBox() -> the same text, for tests
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <Unreal/Hooks/Hooks.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>

#include <atomic>
#include <cstdio>
#include <string>

#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

using namespace RC;
using namespace RC::Unreal;

namespace
{
struct Call
{
    UObject* context;
    UFunction* function;
};
constexpr int STACK = 64, RING = 24;
Call g_stack[STACK]{};
int g_depth = 0; // may exceed STACK; deeper calls are counted, not stored
Call g_ring[RING]{};
std::atomic<unsigned> g_ring_next{0};
DWORD g_game_thread = 0;

auto on_pre(Hook::TCallbackIterationData<void>&, UObject* context, UFunction* function, void*) -> void
{
    if (GetCurrentThreadId() != g_game_thread) return;
    if (g_depth < STACK) g_stack[g_depth] = {context, function};
    ++g_depth;
}

auto on_post(Hook::TCallbackIterationData<void>&, UObject* context, UFunction* function, void*) -> void
{
    if (GetCurrentThreadId() != g_game_thread || g_depth == 0) return;
    --g_depth;
    g_ring[g_ring_next++ % RING] = {context, function};
}

auto name_into(UObject* o, char* out, size_t n) -> void
{
    auto w = o->GetFullName();
    size_t i = 0;
    for (; i + 1 < n && i < w.size(); ++i) out[i] = w[i] < 128 ? static_cast<char>(w[i]) : '?';
    out[i] = 0;
}

// no C++ objects here, so SEH is allowed
auto safe_name(UObject* o, char* out, size_t n) -> void
{
    if (!o) { strcpy_s(out, n, "none"); return; }
    __try { name_into(o, out, n); }
    __except (EXCEPTION_EXECUTE_HANDLER) { sprintf_s(out, n, "<unreadable %p>", static_cast<void*>(o)); }
}

auto line(const Call& c) -> std::string
{
    char fn[300], obj[300];
    safe_name(c.function, fn, sizeof(fn));
    safe_name(c.context, obj, sizeof(obj));
    return std::string(fn) + "  on  " + obj;
}
} // namespace

auto pt_blackbox_dump() -> std::string
{
    std::string out = "Running on the game thread at the crash (outermost first), depth " + std::to_string(g_depth) + ":\r\n";
    for (int i = 0; i < g_depth && i < STACK; ++i) out += "  " + line(g_stack[i]) + "\r\n";
    out += "Last finished calls (oldest first):\r\n";
    unsigned next = g_ring_next.load();
    for (unsigned i = next > RING ? next - RING : 0; i < next; ++i) out += "  " + line(g_ring[i % RING]) + "\r\n";
    return out;
}

// LoadMap runs on the game thread (on_unreal_init does not): dllmain calls this from its LoadMap pre-callback
auto pt_blackbox_set_game_thread() -> void
{
    if (!g_game_thread) g_game_thread = GetCurrentThreadId();
}

auto pt_blackbox_install() -> void
{
    Hook::RegisterProcessEventPreCallback(on_pre, {false, true, STR("PacificTogether"), STR("BlackBoxPre")});
    Hook::RegisterProcessEventPostCallback(on_post, {false, true, STR("PacificTogether"), STR("BlackBoxPost")});
}

auto pt_register_blackbox(const LuaMadeSimple::Lua& lua) -> void
{
    lua.register_function("PTNative_BlackBox", [](const LuaMadeSimple::Lua& l) -> int {
        l.set_string(pt_blackbox_dump());
        return 1;
    });
}
