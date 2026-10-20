// Test-only tracing for the game MCP (tools/gamemcp): records ProcessEvent calls whose UFunction full name matches a filter.
// The hook exists only between PTNative_TraceStart and PTNative_TraceStop, so it costs nothing while tracing is off.
//   PTNative_TraceStart(filter, max, flags): filter = substrings separated by '|' (case-insensitive); keeps the last `max` calls.
//     flags (optional): 1 = add a 4th column with the call's parameter values ("Name=value, ..."), 2 = also record a "<-function" line
//     after the call with its return/out values. Values come from the property's ExportTextItem; capped per call (12 params, 160 chars each,
//     arrays/maps/sets/big structs summarised). Property lists are cached per UFunction.
//   PTNative_TraceRead(): returns "dropped=N" and one line per call "microseconds<TAB>function<TAB>object[<TAB>args]", then clears the buffer
//   PTNative_TraceStop()
// Only calls that go through the engine's ProcessEvent are seen (native code calling a UFunction, Lua calls, delegates);
// Blueprint-to-Blueprint calls inside the script VM are not.
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <Unreal/Hooks/Hooks.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>
#include <Unreal/CoreUObject/UObject/UnrealType.hpp>
#include <Unreal/FString.hpp>

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
struct FnInfo
{
    bool hit{};
    std::vector<FProperty*> in, out; // parameters read before the call / return and out values read after it
};
std::unordered_map<UFunction*, FnInfo> g_match; // per UFunction: does its name match; avoids building the name on every call
int g_flags = 0;                                // 1 = args, 2 = return/out values
thread_local bool t_busy = false;               // a callback that re-enters ProcessEvent must not take the mutex again
std::deque<std::string> g_lines;
size_t g_max = 500;
size_t g_dropped = 0;
Hook::GlobalCallbackId g_id = 0, g_id_post = 0;
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

auto clean(std::string s, size_t max) -> std::string
{
    for (auto& c : s) if (c == '\t' || c == '\n' || c == '\r') c = ' ';
    if (s.size() > max) s = s.substr(0, max) + "...";
    return s;
}

auto fmt_value(FProperty* p, void* parms) -> std::string
{
    auto* ptr = p->ContainerPtrToValuePtr<void>(parms);
    if (CastField<FArrayProperty>(p)) return "<array n=" + std::to_string(static_cast<FScriptArray*>(ptr)->Num()) + ">";
    if (CastField<FMapProperty>(p)) return "<map>";
    if (CastField<FSetProperty>(p)) return "<set>";
    if (auto* sp = CastField<FStructProperty>(p); sp && sp->GetStruct() && sp->GetStruct()->GetStructureSize() > 256)
        return "<struct " + narrow(sp->GetStruct()->GetName()) + ">";
    FString text;
    p->ExportTextItem(text, ptr, nullptr, nullptr, 0);
    return clean(narrow(std::wstring(*text)), 160);
}

auto fmt_params(const std::vector<FProperty*>& props, void* parms) -> std::string
{
    std::string out;
    size_t n = 0;
    for (auto* p : props)
    {
        if (++n > 12 || out.size() > 700) { out += ", ..."; break; }
        if (!out.empty()) out += ", ";
        out += narrow(p->GetName()) + "=" + fmt_value(p, parms);
    }
    return out;
}

auto lookup(UFunction* function) -> FnInfo&
{
    auto it = g_match.find(function);
    if (it != g_match.end()) return it->second;
    FnInfo info;
    auto name = lower(function->GetFullName());
    info.hit = std::any_of(g_filters.begin(), g_filters.end(), [&](const auto& f) { return name.find(f) != std::wstring::npos; });
    if (info.hit && g_flags)
    {
        for (FProperty* p : TFieldRange<FProperty>(function, EFieldIterationFlags::IncludeDeprecated))
        {
            if (!p->HasAnyPropertyFlags(CPF_Parm)) continue;
            bool ret = p->HasAnyPropertyFlags(CPF_ReturnParm);
            bool out = p->HasAnyPropertyFlags(CPF_OutParm) && !p->HasAnyPropertyFlags(CPF_ConstParm);
            (ret || out ? info.out : info.in).push_back(p);
        }
    }
    return g_match.emplace(function, std::move(info)).first->second;
}

auto record(UObject* context, UFunction* function, void* parms, bool post) -> void
{
    if (t_busy) return;
    t_busy = true;
    std::lock_guard lock(g_mutex);
    if (g_on && function)
    {
        auto& info = lookup(function);
        const auto& props = post ? info.out : info.in;
        if (info.hit && !(post && props.empty()))
        {
            if (g_lines.size() >= g_max) { g_lines.pop_front(); ++g_dropped; }
            auto line = std::to_string(micros()) + "\t" + (post ? "<-" : "") + narrow(function->GetFullName()) + "\t" +
                        (context ? narrow(context->GetFullName()) : "none");
            if (parms && (post || (g_flags & 1))) line += "\t" + fmt_params(props, parms);
            g_lines.push_back(std::move(line));
        }
    }
    t_busy = false;
}

auto on_pre(Hook::TCallbackIterationData<void>&, UObject* context, UFunction* function, void* parms) -> void { record(context, function, parms, false); }
auto on_post(Hook::TCallbackIterationData<void>&, UObject* context, UFunction* function, void* parms) -> void { record(context, function, parms, true); }

auto stop() -> void
{
    std::lock_guard lock(g_mutex);
    g_on = false;
    if (g_id) { Hook::UnregisterCallback(g_id); g_id = 0; }
    if (g_id_post) { Hook::UnregisterCallback(g_id_post); g_id_post = 0; }
}
} // namespace

auto pt_register_trace(const LuaMadeSimple::Lua& lua) -> void
{
    lua.register_function("PTNative_TraceStart", [](const LuaMadeSimple::Lua& l) -> int {
        auto filter = std::string(l.get_string());
        // get_* pops the argument it reads: each next argument is at index 1 again (get_integer(2) used to read a missing 3rd argument, so max was always 500)
        auto max = l.get_integer();
        auto flags = static_cast<int>(l.get_integer()); // 0 when absent
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
        g_flags = flags;
        g_on = !g_filters.empty();
        if (g_on) g_id = Hook::RegisterProcessEventPreCallback(on_pre, {false, true, STR("PacificTogether"), STR("Trace")});
        if (g_on && (flags & 2)) g_id_post = Hook::RegisterProcessEventPostCallback(on_post, {false, true, STR("PacificTogether"), STR("TracePost")});
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
