// Test-only socket counters for the game MCP's net_stats (tools/gamemcp/ext_observe.py).
// The engine's net driver keeps its packet/byte counters in plain C++ members that reflection cannot see, so we count at the socket
// layer instead: the first PTNative_NetStats() call redirects the game exe's ws2_32 imports sendto/recvfrom (IAT patch) to
// counting wrappers. Until that first call nothing is touched. Counts every UDP datagram of the process, not only the net driver's.
//   PTNative_NetStats(): "sendto_packets sendto_bytes recvfrom_packets recvfrom_bytes patched_slots" (cumulative since the first call)
#include <LuaMadeSimple/LuaMadeSimple.hpp>

#include <atomic>
#include <string>

#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <WinSock2.h>
#include <Windows.h>

using namespace RC;

namespace
{
std::atomic<long long> g_sent_pkts{0}, g_sent_bytes{0}, g_recv_pkts{0}, g_recv_bytes{0};
bool g_patched = false;
int g_hits = 0; // IAT slots redirected (0 = nothing counted)

using SendToFn = int(WSAAPI*)(SOCKET, const char*, int, int, const sockaddr*, int);
using RecvFromFn = int(WSAAPI*)(SOCKET, char*, int, int, sockaddr*, int*);
SendToFn g_real_sendto{};
RecvFromFn g_real_recvfrom{};

int WSAAPI counting_sendto(SOCKET s, const char* buf, int len, int flags, const sockaddr* to, int tolen)
{
    int r = g_real_sendto(s, buf, len, flags, to, tolen);
    if (r > 0) { ++g_sent_pkts; g_sent_bytes += r; }
    return r;
}

int WSAAPI counting_recvfrom(SOCKET s, char* buf, int len, int flags, sockaddr* from, int* fromlen)
{
    int r = g_real_recvfrom(s, buf, len, flags, from, fromlen);
    if (r > 0) { ++g_recv_pkts; g_recv_bytes += r; }
    return r;
}

// swaps every IAT slot of the exe that points at `real`; returns how many
auto patch_iat(void* real, void* wrapper) -> int
{
    auto* base = reinterpret_cast<BYTE*>(GetModuleHandleW(nullptr));
    auto* nt = reinterpret_cast<IMAGE_NT_HEADERS*>(base + reinterpret_cast<IMAGE_DOS_HEADER*>(base)->e_lfanew);
    auto& dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (!dir.VirtualAddress) return 0;
    int hits = 0;
    for (auto* d = reinterpret_cast<IMAGE_IMPORT_DESCRIPTOR*>(base + dir.VirtualAddress); d->Name; ++d)
    {
        for (auto* t = reinterpret_cast<IMAGE_THUNK_DATA*>(base + d->FirstThunk); t->u1.Function; ++t)
        {
            if (reinterpret_cast<void*>(t->u1.Function) != real) continue;
            DWORD old{};
            if (!VirtualProtect(&t->u1.Function, sizeof(void*), PAGE_READWRITE, &old)) continue;
            t->u1.Function = reinterpret_cast<ULONG_PTR>(wrapper);
            VirtualProtect(&t->u1.Function, sizeof(void*), old, &old);
            ++hits;
        }
    }
    return hits;
}
} // namespace

auto pt_register_net(const LuaMadeSimple::Lua& lua) -> void
{
    lua.register_function("PTNative_NetStats", [](const LuaMadeSimple::Lua& l) -> int {
        if (!g_patched)
        {
            g_patched = true;
            auto ws = GetModuleHandleW(L"ws2_32.dll");
            g_real_sendto = reinterpret_cast<SendToFn>(ws ? GetProcAddress(ws, "sendto") : nullptr);
            g_real_recvfrom = reinterpret_cast<RecvFromFn>(ws ? GetProcAddress(ws, "recvfrom") : nullptr);
            if (g_real_sendto) g_hits += patch_iat(reinterpret_cast<void*>(g_real_sendto), reinterpret_cast<void*>(&counting_sendto));
            if (g_real_recvfrom) g_hits += patch_iat(reinterpret_cast<void*>(g_real_recvfrom), reinterpret_cast<void*>(&counting_recvfrom));
        }
        l.set_string(std::to_string(g_sent_pkts.load()) + " " + std::to_string(g_sent_bytes.load()) + " " + std::to_string(g_recv_pkts.load()) + " " +
                     std::to_string(g_recv_bytes.load()) + " " + std::to_string(g_hits));
        return 1;
    });
}
