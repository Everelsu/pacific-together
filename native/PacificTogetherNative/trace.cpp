// Test-only tracing for the game MCP (tools/gamemcp): records ProcessEvent calls whose UFunction full name matches a filter.
// The hook exists only between PTNative_TraceStart and PTNative_TraceStop, so it costs nothing while tracing is off.
//   PTNative_TraceStart(filter, max): filter = substrings separated by '|' (case-insensitive); keeps the last `max` calls
//   PTNative_TraceRead(): returns "dropped=N" and one line per call "microseconds<TAB>function<TAB>object", then clears the buffer
//   PTNative_TraceStop()
// Only calls that go through the engine's ProcessEvent are seen (native code calling a UFunction, Lua calls, delegates);
// Blueprint-to-Blueprint calls inside the script VM are not.
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <Unreal/Hooks/Hooks.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>

#include <algorithm>
#include <deque>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

using namespace RC;
using namespace RC::Unreal;

namespace
{
std::mutex g_mutex;
std::vector<std::wstring> g_filters;
std::unordered_map<UFunction*, bool> g_match; // per UFunction: does its name match; avoids building the name on every call
std::deque<std::string> g_lines;
size_t g_max = 500;
size_t g_dropped = 0;
Hook::GlobalCallbackId g_id = 0;
bool g_on = false;

auto lower(std::wstring s) -> std::wstring
{
    std::transform(s.begin(), s.end(), s.begin(), [](wchar_t c) { return static_cast<wchar_t>(towlower(c)); });
    return s;
}

auto micros() -> long long
{
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return c.QuadPart * 1000000 / f.QuadPart;
}

auto narrow(const std::wstring& w) -> std::string
{
    std::string s;
    s.reserve(w.size());
    for (wchar_t c : w) s += c < 128 ? static_cast<char>(c) : '?';
    return s;
}

auto on_process_event(Hook::TCallbackIterationData<void>&, UObject* context, UFunction* function, void*) -> void
{
    std::lock_guard lock(g_mutex);
    if (!g_on || !function) return;
    auto it = g_match.find(function);
    if (it == g_match.end())
    {
        auto name = lower(function->GetFullName());
        bool hit = std::any_of(g_filters.begin(), g_filters.end(), [&](const auto& f) { return name.find(f) != std::wstring::npos; });
        it = g_match.emplace(function, hit).first;
    }
    if (!it->second) return;
    if (g_lines.size() >= g_max) { g_lines.pop_front(); ++g_dropped; }
    g_lines.push_back(std::to_string(micros()) + "\t" + narrow(function->GetFullName()) + "\t" + (context ? narrow(context->GetFullName()) : "none"));
}

auto stop() -> void
{
    std::lock_guard lock(g_mutex);
    g_on = false;
    if (g_id) { Hook::UnregisterCallback(g_id); g_id = 0; }
}
} // namespace

auto pt_register_trace(const LuaMadeSimple::Lua& lua) -> void
{
    lua.register_function("PTNative_TraceStart", [](const LuaMadeSimple::Lua& l) -> int {
        auto filter = std::string(l.get_string());
        auto max = l.get_integer(2);
        stop();
        std::lock_guard lock(g_mutex);
        g_filters.clear();
        size_t pos = 0;
        while (pos <= filter.size())
        {
            auto bar = filter.find('|', pos);
            auto part = filter.substr(pos, bar == std::string::npos ? std::string::npos : bar - pos);
            if (!part.empty()) g_filters.push_back(lower(std::wstring(part.begin(), part.end())));
            if (bar == std::string::npos) break;
            pos = bar + 1;
        }
        g_match.clear();
        g_lines.clear();
        g_dropped = 0;
        g_max = max > 0 ? static_cast<size_t>(max) : 500;
        g_on = !g_filters.empty();
        if (g_on) g_id = Hook::RegisterProcessEventPreCallback(on_process_event, {false, true, STR("PacificTogether"), STR("Trace")});
        l.set_bool(g_on);
        return 1;
    });
    lua.register_function("PTNative_TraceRead", [](const LuaMadeSimple::Lua& l) -> int {
        std::lock_guard lock(g_mutex);
        std::string out = "dropped=" + std::to_string(g_dropped) + " tracing=" + (g_on ? "on" : "off");
        for (auto& line : g_lines) out += "\n" + line;
        g_lines.clear();
        g_dropped = 0;
        l.set_string(out);
        return 1;
    });
    lua.register_function("PTNative_TraceStop", [](const LuaMadeSimple::Lua& l) -> int {
        stop();
        l.set_bool(true);
        return 1;
    });
}
