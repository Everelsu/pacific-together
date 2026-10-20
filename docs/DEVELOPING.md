# Developer setup

## Prerequisites

- Pacific Drive on Steam, build 21896301 (see `CLAUDE.md`), Steam running.
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

## Clone and build

```
git clone https://github.com/ikeepcalm/pacific-together.git
cd pacific-together
git -c url."https://github.com/".insteadOf="git@github.com:" submodule update --init --recursive
tools\build-native.cmd
```

`native/RE-UE4SS` is pinned to the commit of the UE4SS build we run (8333063, release
`UE4SS_v3.0.1-1181-g83330635`). Our DLL links against it and loads in that official release (spike X9).
The build copies the DLL to `mod/PacificTogether/dlls/main.dll`.

CLion: open `native/` as a CMake project, toolchain Visual Studio (amd64), generator Ninja,
build type `Game__Shipping__Win64`, target `PacificTogetherNative`.

## Fast mod build in worktrees

A git worktree normally needs the submodules and a full UE4SS build (10-15 min). Instead, with the main
checkout's `native/build` already built, run from the worktree:

```
powershell -File tools/build-mod-fast.ps1 [-Out <path/main.dll>] [-MainBuild <dir>]
```

It takes the compile and link commands for `PacificTogetherNative` from the main build (via `ninja -t commands`),
compiles this checkout's `native/PacificTogetherNative/*.cpp` into `native/build-fast/` (only changed files),
links against the main build's UE4SS libraries and copies the result to `mod/PacificTogether/dlls/main.dll`
(or `-Out`). About 5 s when nothing changed, 15-25 s after a source change.

Use it for edits to our own C++ files, including new .cpp files. It refuses (use `tools/build-native.cmd`)
when the main build is missing, the `RE-UE4SS` pin differs from main's, or our `CMakeLists.txt` adds libraries,
compile settings or include directories. It does not read the CMake source list: every `.cpp` in the folder is built,
and a changed header rebuilds all of them. Rebuild the main build after UE4SS or compiler flag changes.

## Test copies and tests

1. Get the pinned UE4SS dev build into `local/cache/ue4ss/` (hash in `tools/setup-test.ps1`):
   `gh release download experimental-latest -R UE4SS-RE/RE-UE4SS -p "zDEV-UE4SS_v3.0.1-1181-g83330635.zip" -D local/cache/ue4ss`
   (the `experimental-latest` assets get replaced upstream; if the hash no longer matches, ask for the cached copy).
2. `powershell -File tools/setup-test.ps1` makes `C:\PacificTogetherTest\client1` (full copy) and `client2` (hardlinks).
3. `powershell -File tools/run-test.ps1 -Scenario boot`, see `docs/TESTING.md`.

Game class dumps for reading: run `tools/run-test.ps1 -Scenario dump`, output in `local/dumps/`
(open `UHTHeaderDump` in CLion).

## Game MCP and Blueprint atlas

`tools/gamemcp` (`.mcp.json`, `docs/GAME-MCP.md`) needs only Python and a test pair; its `watch` tool needs the native DLL built
with `trace.cpp` (the build above). Its `xref` tool reads `local/atlas`, which is git-ignored game data: copy the folder from
the owner or rebuild it as described in `docs/research/game-atlas.md`.
