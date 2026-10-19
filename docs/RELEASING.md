# Releasing Pacific Together

## Versions

- Semantic versions `MAJOR.MINOR.PATCH`, tag `vX.Y.Z` on `main`.
- `0.x` until the v1.0 scope in `docs/PLAN.md` is met. Each milestone M2-M6 is a minor release (0.1 ... 0.5).
- PATCH: bug fixes only, no protocol change. MINOR: features or protocol change. MAJOR: after 1.0, a protocol or
  install change that breaks old installs.
- Pre-releases for testing: `vX.Y.Z-beta.N`.
- The network protocol has its own integer `PROTOCOL_VERSION`, bumped on any wire change. The join handshake compares
  mod version, protocol version, game build id and DLC set; any mismatch refuses the join.

## Release gate

A tag is cut only when all of these are true:

1. The full automated suite passes on `main`, including lag/loss scenarios once they exist (M7). Paste the summary into the release notes.
2. Each new test has had its mutation check (the test failed when the feature was broken on purpose).
3. A human playtest of the release's headline feature (from 0.2 on: a full run) by the owner and a friend.
4. `CHANGELOG.md` updated.
5. The game build id and exe SHA-256 still match `CLAUDE.md`. If Steam patched the game, no release until re-tested.
6. Uses the two Steam accounts (ikeepcalm, Djecka) for the Steam join check from 0.5 on.

## Artifact

`PacificTogether-vX.Y.Z.zip`, unpacked into `<game dir>/PenDriverPro/Binaries/Win64/`:

```
ue4ss/Mods/PacificTogether/   Lua scripts, dlls/main.dll, enabled.txt
README.txt                    install, play, uninstall, known issues, where logs are
```

- UE4SS itself: link the exact pinned release and its SHA-256 in the README, or bundle it if its license allows (check before 0.1).
- No game files, no debug test bots, no test-only scenarios.
- `SHA256SUMS.txt` next to the zip.

## Release notes template

```
## Pacific Together vX.Y.Z

Game: Pacific Drive Steam build 21896301 (v1.15.0), exe SHA-256 568bb634...
UE4SS: <version / commit>, SHA-256 <...>
Protocol: <n>  (host and guest must run the same mod version)

### New
### Fixed
### Known issues
### Tests
<suite summary pasted from the runner>
```

## Changelog

`CHANGELOG.md` in Keep a Changelog style: an `Unreleased` section collects entries as PRs merge; the release moves
them under the version heading.

## Where releases go

GitHub Releases on https://github.com/ikeepcalm/pacific-together (public, MIT). `-beta` builds are marked
pre-release there. Nexus only after 1.0, when the owner decides.
