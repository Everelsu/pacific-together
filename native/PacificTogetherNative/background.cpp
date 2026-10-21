// Test runs only (PT_SCENARIO set, PT_FOREGROUND unset): a test game never keeps the owner's focus or mouse.
// Headless games hide their window; windowed ones stay visible behind the other windows (screenshots still render).
// The game activates its window on creation and on some map loads: hand the foreground back to whoever had it.
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>

#include <chrono>
#include <cstdlib>
#include <cwchar>
#include <set>
#include <thread>

namespace
{
    bool g_hide{};
    std::set<HWND> g_placed;

    auto ours(HWND w) -> bool
    {
        DWORD pid{};
        GetWindowThreadProcessId(w, &pid);
        return pid == GetCurrentProcessId();
    }

    auto is_game(HWND w) -> bool
    {
        wchar_t cls[64]{};
        GetClassNameW(w, cls, 64);
        return wcscmp(cls, L"UnrealWindow") == 0;
    }

    BOOL CALLBACK place(HWND w, LPARAM)
    {
        if (!ours(w) || !IsWindowVisible(w) || g_placed.count(w)) return TRUE;
        if (g_hide) ShowWindow(w, SW_HIDE);
        else SetWindowPos(w, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        g_placed.insert(w);
        return TRUE;
    }
}

auto pt_background_install() -> void
{
    if (!std::getenv("PT_SCENARIO") || std::getenv("PT_FOREGROUND")) return;
    g_hide = wcsstr(GetCommandLineW(), L"-nullrhi") != nullptr;
    std::thread([] {
        HWND prev{};
        bool chosen{}; // the owner clicked into this windowed game: leave it focused until they leave it
        for (;;)
        {
            EnumWindows(place, 0);
            HWND fg = GetForegroundWindow();
            bool mine = fg && ours(fg);
            if (fg && !mine && !is_game(fg)) prev = fg;
            if (!mine) chosen = false;
            else if (!g_hide && (GetAsyncKeyState(VK_LBUTTON) & 0x8000)) chosen = true;
            if (mine && !chosen && prev && IsWindow(prev))
            {
                ClipCursor(nullptr);
                SetForegroundWindow(prev);
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }).detach();
}
