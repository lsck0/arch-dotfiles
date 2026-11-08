# Parallel implementation: one worktree per workstream

Part of `l-spec-driven-development`.

Two workers in one working tree stomp each other's uncommitted changes,
so every concurrent branch gets its own worktree. A project already laid
out as a bare repo with one worktree per branch keeps that layout; any
other repo works too. Under Claude Code the Agent call's
`isolation: "worktree"` creates it (`l-multi-agent-mode`,
`references/harness.md`). Under Herdr use its worktree support, not raw
`git worktree`, so checkout, branch and pane are created together:

```bash
herdr worktree list                                  # reuse before creating
herdr worktree create --cwd "$REPO_DIR" --branch <workstream-branch> --base <base-branch> \
  --label <workstream-name> --no-focus --trust-repository
# -> .result.worktree.path            the worker's checkout
#    .result.root_pane.pane_id        start the worker here, no split
#    .result.workspace.workspace_id   needed for remove
herdr worktree open --path <existing-worktree>       # reopen after a restart
```

- `--trust-repository` grants Git trust for this one request: pass it only
  for Luca's own repos or one he verified, never as a retry for a failed
  command.
- The branch is the workstream's phase branch, cut from the updated base;
  land it from inside the worktree (rebase, push, PR).
- Specs, research and other shared docs stay in the main checkout's
  notes directory (`$SPEC_DIR`) or `tasks/`; pass the worker that absolute
  path.
- After the PR is open: `herdr worktree remove --workspace <id>`. It
  deletes the checkout and its workspace and keeps the branch for the PR;
  the branch goes after the merge (`trace-and-github.md`, Branches).
  Feedback on that PR gets a checkout back with `herdr worktree create
  --branch <existing branch>` (no `--base`), or `open --path` while the
  checkout still exists.
  `create` also opens a workspace for the main checkout if none exists;
  close that with `herdr workspace close <id>` when you opened it.
- Only one implementer at a time needs no worktree: it works in the main
  checkout.
