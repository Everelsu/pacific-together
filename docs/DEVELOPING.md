# Developer setup

Documentation-only edits need no game or native toolchain. Lua/gameplay testing needs the game, Git, Python and
PowerShell; a matching prebuilt native DLL avoids the C++ toolchain. See the Lua-only path below.

## Prerequisites

- Pacific Drive on Steam, build 21896301 (hash in [../CLAUDE.md](../CLAUDE.md)), Steam running.
- Visual Studio 2022 Build Tools with the C++ workload:
  `winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"`
- Rust: `winget install --id Rustlang.Rustup`, then `rustup default stable-msvc`.
- GitHub account linked to Epic Games (epicgames.com -> Apps and Accounts -> GitHub), invite to
  https://github.com/EpicGames accepted. Needed for UE4SS's `deps/first/Unreal` (Re-UE4SS/UEPseudo).
- GitHub CLI (`winget install --id GitHub.cli`), then `gh auth login` (HTTPS) and `gh auth setup-git`, so git can
  fetch the Epic-gated submodule over HTTPS with your login.
- `git config --global core.longpaths true`: UE4SS's `deps/first/Unreal` has file paths over 260 characters; without
  it the checkout fails with "Filename too long". Clone into a short path (e.g. `C:\dev\pacific-together`).
- Fetching the submodules uses `-c url."https://github.com/".insteadOf="git@github.com:"` (below) because UE4SS's
  `.gitmodules` uses SSH addresses. If you have an SSH key on GitHub, a plain `git submodule update --init --recursive` works too.

### Lua-only setup (no C++ toolchain)

Tasks that don't touch `native/` (Lua features and gameplay tests) need only the game,
git, Python and PowerShell. Skip Visual Studio, Rust, the Epic link and the submodules: clone, then take `main.dll` from
a matching dev preview zip (`game/ue4ss/Mods/PacificTogetherNative/dlls/main.dll`) into `mod/PacificTogetherNative/dlls/`.
Continue at "Test copies and tests". If native code changed since that zip, obtain a matching build.

## Clone and build

```
git clone https://github.com/ikeepcalm/pacific-together.git
cd pacific-together
git -c url."https://github.com/".insteadOf="git@github.com:" submodule update --init --recursive
tools\build-native.cmd
```

`native/RE-UE4SS` is pinned to the commit of the UE4SS build we run (8333063, release
`UE4SS_v3.0.1-1181-g83330635`). Our DLL links against it and loads in that official release (spike X9).
The build copies the DLL to `mod/PacificTogetherNative/dlls/main.dll`: its own UE4SS mod, so reloading the Lua mod
never unloads it. Repeated Lua reloads can still crash; restart for validation.

CLion: open `native/` as a CMake project, toolchain Visual Studio (amd64), generator Ninja,
build type `Game__Shipping__Win64`, target `PacificTogetherNative`.

## Fast mod build in worktrees

With the main checkout's `native/build` already built, run from a worktree:

```
powershell -File tools/build-mod-fast.ps1 [-Out <path/main.dll>] [-MainBuild <dir>]
```

This reuses the main build's compile/link commands and UE4SS libraries, compiles changed C++ files into
`native/build-fast/`, and writes `mod/PacificTogetherNative/dlls/main.dll` (or `-Out`). Stop games using that DLL first.
It builds every `.cpp` in the native mod folder; header changes rebuild all of them. Use the full build after UE4SS,
compiler, library or CMake configuration changes, or if the fast script refuses the cached build.

## Test copies and tests

1. Get the pinned UE4SS dev build into `local/cache/ue4ss/` (hash in `tools/setup-test.ps1`):
   `gh release download experimental-latest -R UE4SS-RE/RE-UE4SS -p "zDEV-UE4SS_v3.0.1-1181-g83330635.zip" -D local/cache/ue4ss`
   (the `experimental-latest` assets get replaced upstream; if the hash no longer matches, ask for the cached copy).
2. `powershell -File tools/setup-test.ps1` makes `C:\PacificTogetherTest\client1` (full copy) and `client2` (hardlinks).
3. `powershell -File tools/run-test.ps1 -Scenario boot`, see [TESTING.md](TESTING.md).

Game class dumps for reading: run `tools/run-test.ps1 -Scenario dump`, output in `local/dumps/`
(open `UHTHeaderDump` in CLion).

## Game MCP and Blueprint atlas

`tools/gamemcp` (`.mcp.json`, `docs/GAME-MCP.md`) needs only Python and a test pair; its `watch` tool needs the native DLL built
with `trace.cpp` (the build above). Its `xref` tool reads `local/atlas`, which is git-ignored game data: copy the folder from
the owner or rebuild it as described in `docs/research/game-atlas.md`.
