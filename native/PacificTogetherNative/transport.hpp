#pragma once
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <DynamicOutput/DynamicOutput.hpp>
#include <Helpers/String.hpp>
#include <LuaMadeSimple/LuaMadeSimple.hpp>

// "[PacificTogether] " + printf-style line into UE4SS.log
inline void pt_log(const char* fmt, ...)
{
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    RC::Output::send<RC::LogLevel::Verbose>(STR("[PacificTogether] {}\n"), RC::to_wstring(buf));
}

// Lua string argument copied out (LuaMadeSimple pops it and returns a view); "" when absent or not a string
inline std::string lua_str_arg(const RC::LuaMadeSimple::Lua& l)
{
    if (l.get_stack_size() < 1 || !l.is_string()) return {};
    return std::string(l.get_string());
}

// X5: UE's UDP traffic to fake 10.77.x.y peers goes over a link (loopback UDP or Steam) instead of the wire.
auto transport_register(const RC::LuaMadeSimple::Lua& lua) -> void;
// The tunnel's Steam link (steam.cpp). steam_send returns the EResult; steam_receive calls on_msg per message.
auto steam_send(uint64_t id, int channel, const void* data, uint32_t size, int flags) -> int;
auto steam_receive(int channel, void (*on_msg)(uint64_t from, const uint8_t* data, uint32_t size)) -> void;
// X6: lobby, rich presence and ISteamNetworkingMessages through the game's own steam_api64.dll
auto steam_register(const RC::LuaMadeSimple::Lua& lua) -> void;
