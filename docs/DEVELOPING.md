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

## Test copies and tests

1. Get the pinned UE4SS dev build into `local/cache/ue4ss/` (hash in `tools/setup-test.ps1`):
   `gh release download experimental-latest -R UE4SS-RE/RE-UE4SS -p "zDEV-UE4SS_v3.0.1-1181-g83330635.zip" -D local/cache/ue4ss`
   (the `experimental-latest` assets get replaced upstream; if the hash no longer matches, ask for the cached copy).
2. `powershell -File tools/setup-test.ps1` makes `C:\PacificTogetherTest\client1` (full copy) and `client2` (hardlinks).
3. `powershell -File tools/run-test.ps1 -Scenario boot`, see `docs/TESTING.md`.

Game class dumps for reading: run `tools/run-test.ps1 -Scenario dump`, output in `local/dumps/`
(open `UHTHeaderDump` in CLion).
