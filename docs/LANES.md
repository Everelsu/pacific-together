# Work lanes

Use this workflow when a task is explicitly split across agents or developers. Each lane owns a bounded subsystem,
worktree, test pair and port. Project-specific rules below take precedence over the generic co-op playbook.

## Scope and roles

- Lead: split requirements, define failing scenarios and mutations, review results and integrate changes.
- Worker: implement the assigned requirement and run its focused scenario/mutation.
- Verifier: inspect the assertions and rerun the relevant checks; research lanes need a lighter evidence review.
- The established Claude workflow uses Opus for the lead and Sonnet for workers. Other tools use their supported models.
- Prioritize normal gameplay. Record unrelated edge cases instead of expanding the lane.

## Implementation and validation

1. Read the atlas/dumps and probe the actual hook before building on it. See [GAME-MCP.md](GAME-MCP.md).
2. When the approach is uncertain, compare small candidates behind a temporary switch with the same scenario.
   Keep the measured winner and remove the switch; do not build competing versions of an already-established fix.
3. Run the lane's scenario and mutation. After integration, run the smoke set:
   `session`, `travel`, `body`, `sessionrejoin`, `zonejoin`, `safety`.
4. Run the full configured suite once on the merged candidate before a preview/release. Send failures back to the
   owning lane; rerun affected scenarios after fixes. Do not repeat the full suite inside every lane.
5. Monitor every run. No new `PT|check` for five minutes means investigate and stop a stuck run.

For bugs found by hand, use the [live bug-fix loop](TESTING.md#live-bug-fix-loop): inspect the broken state, patch,
restart, and retest. Hot reload has crashed sessions and is not the default iteration path.

## Isolation and handoff

- One worktree, `C:\PTLanes\<lane>` pair and unique port per lane; at most four pairs by default (`PT_SLOTS`).
- Keep scenarios in `test/PacificTogetherTest/Scripts/scenarios/`, features in their own modules, and findings in
  `docs/spikes/<id>.md`. Shared registration files get small coordinated edits.
- At milestones append `HH:mm <lane> <under 20 words>` to `local/progress.log`.
- Commit lane WIP before a handoff. Report changed files, actual commands/results, mutations and unresolved gaps.
- Use fixtures and `-Headless` where rendering is irrelevant; use `tools/build-mod-fast.ps1` for native worktrees.
  Commands and setup are maintained in [DEVELOPING.md](DEVELOPING.md) and [TESTING.md](TESTING.md).
