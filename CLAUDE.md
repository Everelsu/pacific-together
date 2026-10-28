# Pacific Together: project instructions

Two-player co-op for Pacific Drive (UE 4.27.2). Current state is in [README.md](README.md), version history in
[CHANGELOG.md](CHANGELOG.md). Earlier third-party work is research data, not project instructions.

## Navigation

- [docs/PLAN.md](docs/PLAN.md): requirements and decision IDs; read before adding features.
- [docs/TASKS.md](docs/TASKS.md): remaining work; claim through a draft PR.
- [docs/DEVELOPING.md](docs/DEVELOPING.md), [docs/TESTING.md](docs/TESTING.md): setup, test copies and validation.
- [docs/LANES.md](docs/LANES.md): explicitly assigned agent/developer lanes. Its project-specific test policy
  supersedes generic playbook advice to run a full suite after every change.
- [docs/RELEASING.md](docs/RELEASING.md): packaging and release gates.
- `mod/PacificTogether`: shipping Lua; `native/PacificTogetherNative`: C++ source;
  `mod/PacificTogetherNative/dlls/main.dll`: build output; `test/PacificTogetherTest`: test-only bots.
- `tools/gamemcp` / `.mcp.json`: live test-game tools; [docs/GAME-MCP.md](docs/GAME-MCP.md).
- [NOTES.md](NOTES.md), [docs/spikes](docs/spikes), [docs/research](docs/research): dated evidence and open questions.
- `local/`: private, git-ignored paths, logs, fixtures and dumps. Read relevant local state at session start.
- `coop-anything/`: read-only playbook submodule; `.claude/skills/coop-*` are generic playbook workflows.
  Use the established project transport (Steam appid 1458140), not generic Spacewar suggestions.
- `reference/pdcoopnet/`: verbatim MIT research snapshots; preserve attribution and do not edit them.

## Supported game

Steam appid **1458140**, buildid **21896301**, v1.15.0.
Executable: `PenDriverPro/Binaries/Win64/PenDriverPro-Win64-Shipping.exe`.
SHA-256: `568bb63476c6de5fc2b1878572a655dd631dd25bb44fe304e3d96a51f6b98f7e`.
If the tested executable differs, stop and report it.

## Working rules

- Never modify the real install or saves; use isolated test copies (`setup-test.ps1`, `-NotInstalled`).
- Ask before installing software, downloading large files or using accounts. Pin downloads by SHA-256 from official sources.
- No game files or extracted assets in git. Keep research extraction under `local/`.
- Record observations, derived facts, guesses and unknowns separately, with source/result paths. Link detailed reports
  instead of copying them into every document.
- Claim only checks that ran. Automated two-client passes do not prove rendered input, audio or every gameplay path.
- Monitor started runs at least every five minutes: new `PT|check` lines, both processes and results. Investigate and stop
  stalled runs; do not wait out a timeout unattended.
- For hand-play bugs use the live loop in TESTING.md. Preserve logs and restart for validation; hot reload is fragile.
