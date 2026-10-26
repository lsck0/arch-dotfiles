# Parallel implementation: one worktree per workstream

Part of `l-spec-driven-development`.

Two workers in one working tree stomp each other's uncommitted changes,
so every concurrent branch gets its own worktree. A project already laid
out as a bare repo with one worktree per branch keeps that layout; any
other repo works too. Use Herdr's worktree support, not raw
`git worktree`, so checkout, branch and pane are created together:

```bash
herdr worktree list                                  # reuse before creating
herdr worktree create --cwd "$REPO_DIR" --branch <workstream-branch> \
  --label <workstream-name> --no-focus --trust-repository
# -> .result.worktree.path            the worker's checkout
#    .result.root_pane.pane_id        start the worker here, no split
#    .result.workspace.workspace_id   needed for remove
herdr worktree open --path <existing-worktree>       # reopen after a restart
```

- The branch is the workstream's phase branch; land it from inside the
  worktree (rebase, push, PR).
- Specs, research and other shared docs stay in the main checkout's
  `$SPEC_DIR`; pass the worker that absolute path.
- After the PR is open: `herdr worktree remove --workspace <id>`. It
  deletes the checkout and its workspace and keeps the branch for the PR;
  the branch goes after the merge (`trace-and-github.md`, Branches).
  Feedback on that PR reopens it with `herdr worktree create --branch
  <existing branch>` or `open`.
  `create` also opens a workspace for the main checkout if none exists;
  close that with `herdr workspace close <id>` when you opened it.
- Only one implementer at a time needs no worktree: it works in the main
  checkout.
