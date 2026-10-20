// Message channel between host and guest on the existing game connection, for intents and state (PLAN §3).
// Guest -> host rides APlayerController::ServerExecRPC(FString): reliable, ordered, and a no-op in shipping builds
// (PlayerController.cpp:1739). Host -> guest rides ClientMessage(FString): reliable, ordered; its implementation only
// prints to the console, so ours are dropped before it runs. Both follow the connection: direct IP or the Steam tunnel.
// A message is "kind" + bytes (no NUL), split into chunks "PT1|<kind>|<m or e>|<bytes>"; chunks of one connection arrive
// in order, so reassembly needs no ids. Each byte is one TCHAR, so bytes come back exactly.
// Received messages wait in an inbox; each Lua mod polls the kinds it owns (main mod "g.", test mod "t.").
//   PTNative_MsgToHost(localPcAddress, kind, data) -> bool      guest side, on its own PlayerController
//   PTNative_MsgToGuest(remotePcAddress, kind, data) -> bool    host side, on that guest's PlayerController
//   PTNative_MsgPoll(prefix) -> kind, data, fromAddress | nil   oldest message whose kind starts with prefix
//   PTNative_MsgStats() -> "sent=.. recv=.. chunks_out=.. chunks_in=.. dropped=.."
#include <DynamicOutput/DynamicOutput.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>
#include <Unreal/Hooks/Hooks.hpp>
#include <Unreal/UObject.hpp>
#include <Unreal/UObjectGlobals.hpp>
#include <Unreal/UFunction.hpp>
#include <Unreal/CoreUObject/UObject/Class.hpp>

#include <cstdlib>
#include <cstring>
#include <deque>
#include <map>
#include <string>
#include <utility>
#include <vector>

using namespace RC;
using namespace RC::Unreal;

namespace
{
constexpr size_t CHUNK = 1000;       // bytes per RPC
constexpr size_t MAX_MSG = 32 * 1024; // 33 chunks: far below UE's 256 outstanding reliable bunches per channel
constexpr size_t MAX_INBOX = 4096;
constexpr const wchar_t* MAGIC = L"PT1|";

struct Msg
{
    std::string kind, data;
    uintptr_t from;
};

UFunction* g_to_host{};
UFunction* g_to_guest{};
bool g_sending = false; // our own ProcessEvent calls pass through the pre-callback too
bool g_capture = true;
std::deque<Msg> g_inbox;
std::map<std::pair<uintptr_t, std::string>, std::string> g_partial;
long long g_sent = 0, g_recv = 0, g_chunks_out = 0, g_chunks_in = 0, g_dropped = 0;

auto resolve() -> bool
{
    if (!g_to_host) g_to_host = UObjectGlobals::StaticFindObject<UFunction*>(nullptr, nullptr, STR("/Script/Engine.PlayerController:ServerExecRPC"));
    if (!g_to_guest) g_to_guest = UObjectGlobals::StaticFindObject<UFunction*>(nullptr, nullptr, STR("/Script/Engine.PlayerController:ClientMessage"));
    return g_to_host && g_to_guest;
}

auto valid_kind(std::string_view k) -> bool
{
    if (k.empty() || k.size() > 32) return false;
    for (char c : k)
        if (!(isalnum(static_cast<unsigned char>(c)) || c == '.' || c == '_' || c == '-')) return false;
    return true;
}

// Both RPCs take the FString first, at offset 0; the rest of ClientMessage's parameters stay zero (Type None, lifetime 0).
auto send(UObject* pc, UFunction* fn, const std::string& kind, const std::string& data) -> bool
{
    if (!pc || !fn || !valid_kind(kind) || data.size() > MAX_MSG || data.find('\0') != std::string::npos) return false;
    std::vector<unsigned char> parms(std::max<size_t>(fn->GetStructureSize(), sizeof(FString)), 0);
    size_t pos = 0;
    do
    {
        auto part = data.substr(pos, CHUNK);
        pos += part.size();
        std::wstring s = MAGIC;
        s.append(kind.begin(), kind.end());
        s += pos < data.size() ? L"|m|" : L"|e|";
        for (unsigned char b : part) s += static_cast<wchar_t>(b);
        auto* str = new (parms.data()) FString(s.c_str());
        g_sending = true;
        pc->ProcessEvent(fn, parms.data());
        g_sending = false;
        str->~FString();
        ++g_chunks_out;
    } while (pos < data.size());
    ++g_sent;
    return true;
}

auto on_pre(Hook::TCallbackIterationData<void>& it, UObject* context, UFunction* function, void* parms) -> void
{
    if (g_sending || !g_capture || !parms || !function || (function != g_to_host && function != g_to_guest)) return;
    auto& chars = static_cast<FString*>(parms)->GetCharArray();
    const wchar_t* s = chars.GetData();
    size_t len = s ? wcslen(s) : 0;
    if (len < 8 || wcsncmp(s, MAGIC, 4) != 0) return;
    it.PreventOriginalFunctionCall();
    ++g_chunks_in;
    // PT1|<kind>|<m|e>|<bytes>
    std::wstring_view v(s + 4, len - 4);
    auto bar = v.find(L'|');
    if (bar == std::wstring_view::npos || bar + 3 > v.size() || v[bar + 2] != L'|') { ++g_dropped; return; }
    std::string kind(v.begin(), v.begin() + bar);
    bool last = v[bar + 1] == L'e';
    auto key = std::make_pair(reinterpret_cast<uintptr_t>(context), kind);
    // shortcut: a message cut off by a dropped connection waits here; a new controller at the same address and kind would
    // get it as a prefix. Upgrade (reset on login) if that shows up.
    auto& buf = g_partial[key];
    if (buf.size() > MAX_MSG) { buf.clear(); ++g_dropped; }
    for (auto c : v.substr(bar + 3)) buf += static_cast<char>(c & 0xFF);
    if (!last) return;
    if (g_inbox.size() >= MAX_INBOX) { g_inbox.pop_front(); ++g_dropped; }
    g_inbox.push_back({kind, std::move(buf), key.first});
    g_partial.erase(key);
    ++g_recv;
}

auto ensure_hook() -> void
{
    static bool done = false;
    if (done || !resolve()) return;
    done = true;
    // test runs only: the scenario's mutation proves the checks need this layer
    if (auto m = std::getenv("PT_MUTATE"); m && std::string(m) == "nocapture") g_capture = false;
    Hook::RegisterProcessEventPreCallback(on_pre, {false, false, STR("PacificTogether"), STR("Msg")});
}

auto lua_send(const LuaMadeSimple::Lua& l, bool to_host) -> int
{
    ensure_hook();
    auto address = static_cast<uintptr_t>(l.get_integer());
    auto kind = std::string(l.get_string());
    auto data = std::string(l.get_string());
    l.set_bool(send(reinterpret_cast<UObject*>(address), to_host ? g_to_host : g_to_guest, kind, data));
    return 1;
}
} // namespace

auto pt_register_msg(const LuaMadeSimple::Lua& lua) -> void
{
    // registered at every Lua start; the hook goes in as soon as the UFunctions exist, so a guest's first message is caught
    ensure_hook();
    lua.register_function("PTNative_MsgToHost", [](const LuaMadeSimple::Lua& l) -> int { return lua_send(l, true); });
    lua.register_function("PTNative_MsgToGuest", [](const LuaMadeSimple::Lua& l) -> int { return lua_send(l, false); });
    lua.register_function("PTNative_MsgPoll", [](const LuaMadeSimple::Lua& l) -> int {
        ensure_hook();
        auto prefix = std::string(l.get_string());
        for (auto it = g_inbox.begin(); it != g_inbox.end(); ++it)
        {
            if (it->kind.compare(0, prefix.size(), prefix) != 0) continue;
            auto m = std::move(*it);
            g_inbox.erase(it);
            l.set_string(m.kind);
            l.set_string(m.data);
            l.set_integer(static_cast<int64_t>(m.from));
            return 3;
        }
        return 0;
    });
    lua.register_function("PTNative_MsgStats", [](const LuaMadeSimple::Lua& l) -> int {
        auto s = "sent=" + std::to_string(g_sent) + " recv=" + std::to_string(g_recv) + " chunks_out=" + std::to_string(g_chunks_out) +
                 " chunks_in=" + std::to_string(g_chunks_in) + " dropped=" + std::to_string(g_dropped) + " inbox=" + std::to_string(g_inbox.size());
        l.set_string(s);
        return 1;
    });
}
