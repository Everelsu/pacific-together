# Pacific Together

Two-player online co-op mod for [Pacific Drive](https://store.steampowered.com/app/1458140/Pacific_Drive/):
one drives, one rides along, both scavenge, the run is shared. Join through Steam invites.

**Status: early development.** Two players can join by IP, see each other and walk the garage and zones together;
the car, loot and the run aren't synced yet. No public release before 1.0. See [docs/PLAN.md](docs/PLAN.md) for scope
and milestones.

- Game build: Steam v1.15.0 (buildid 21896301). Other builds are not supported.
- Built on [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS). Not affiliated with Ironwood Studios.
- Research notes: [docs/research](docs/research). Release rules: [docs/RELEASING.md](docs/RELEASING.md).
- `reference/pdcoopnet` is a copy of [PDCoopNet](https://github.com/BroZYTnikkkk/pacific-drive-coop) (MIT, by
  BroZYTnikkkk), kept as research material.

## Building from source

Windows only. The C++ part builds against UE4SS's source, which includes Unreal Engine headers that only
Epic-linked GitHub accounts can download.

1. **Link GitHub to Epic Games**: epicgames.com -> Account -> Apps and Accounts -> GitHub -> Connect, then accept the
   invite at https://github.com/orgs/EpicGames/invitation (arrives by email).
2. **Install the tools**:
   ```
   winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
   winget install --id Rustlang.Rustup
   winget install --id GitHub.cli
   ```
   Then in a new terminal: `rustup default stable-msvc`, `gh auth login` (choose HTTPS), `gh auth setup-git`, and
   `git config --global core.longpaths true` (some UE4SS file paths are longer than Windows' 260-character limit).
3. **Clone and build** into a short path such as `C:\dev`. UE4SS's sub-repos point at SSH addresses; the `-c` flag
   fetches them over HTTPS so no SSH key is needed:
   ```
   git clone https://github.com/ikeepcalm/pacific-together.git
   cd pacific-together
   git -c url."https://github.com/".insteadOf="git@github.com:" submodule update --init --recursive
   tools\build-native.cmd
   ```
   Do not use `git clone --recursive`: it uses the SSH addresses and fails without an SSH key.

Test copies of the game, the test runner and CLion settings: [docs/DEVELOPING.md](docs/DEVELOPING.md). Many tasks need
none of the C++ setup above (see its "Lua-only setup").

## Contributing

[docs/TASKS.md](docs/TASKS.md) lists self-contained tasks, each on its own branch, sorted by AI-token cost and by how
many game instances they need. Some need no AI at all. To claim one, open a draft PR named after its id.

MIT license. This repository contains no game files.
