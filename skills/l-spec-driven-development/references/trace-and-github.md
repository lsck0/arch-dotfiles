# Trace, GitHub and branches

Part of `l-spec-driven-development`: naming every artifact back to its spec, the GitHub rules for PRs, reviewers,
issues and waiting, and branch handling.

## Trace

Every artifact names where it came from, so a bare PR link is enough to
find the spec, the phase and the requirements.

- **Code**: `INDEX.md` maps every file to its spec, so a diff alone
  names the specs it must update.
- **Branches**: `spec/spec-<nnn>-<slug>`, `<type>/spec-<nnn>-p<k>-<slug>`.
- **PR title**: `spec(spec-<nnn>): <title>`,
  `<type>(spec-<nnn>): p<k> <what is now true>`.
- **PR body** opens with the trace block:
  ```
  Spec: specs/spec-<nnn>-<slug>/SPEC.md (plus any other spec it touches)
  Phase: p<k> of <n> (SPEC.md Roadmap)
  Requirements: spec-<nnn>/R-004, spec-<nnn>/R-005
  Issue: #<n>
  Run: <preview URL | build-and-start command>
  Revert: <git revert <sha> | down migration + revert>
  ```
- **Commits** carry trailers `Spec: spec-<nnn>` and
  `Refs: spec-<nnn>/R-004, #<n>`.
- **Tests** carry the requirement in their name (`spec003_r004_...`), so
  a grep finds the proof after any refactor.
- **Issues**: PRs and commits reference the issue (`Issue:`, `Refs
  #<n>`). Only the last phase PR of the change says `Closes #<n>`: its
  merge comes after the last review and tests, so the issue closes when
  the change is verified.
- **Roadmap** rows link back: each phase lists its PRs and state.
- Resolving a PR: trace block first, branch name second. Neither present
  -> ask; don't guess the spec.

## GitHub: PRs, reviewers, issues, waiting

- **Questions** are documents: `QUESTIONS.md` in the spec PR (Spec
  gate), or under `l-agent-task-db` a question file in
  `tasks/context/questions/`. Never a chat prompt the human has to be
  present for.
- **Reviewer and assignee.** Every PR requests the human as reviewer and
  is assigned to them: `gh pr create --reviewer <login> --assignee
  <login>`, plus `--draft` for a phase PR (step 3 of the Phase loop); a
  spec PR opens ready for review. `<login>` is the `Reviewer:` line in `AGENTS.md`, else the
  repo owner (`gh repo view --json owner -q .owner.login`). GitHub
  refuses a review request to the PR's own author; when the agent pushes
  as the human, the assignee carries it.
- **Issues.** A project that tracks work in issues gets one per change:
  the issue the human filed, or one the agent opens from the prompt
  before the spec PR (`gh issue create --assignee <login>`). It
  stays assigned to the human (`gh issue edit <n> --add-assignee
  <login>`) for its whole life. Every PR of the change links it (Trace,
  above), and the issue gets a comment linking each new PR, so either
  side reaches the other.
- **Waiting on a PR.** The human never reports back by hand. Watch the
  PR itself until it merges, closes, or gets a new review or comment
  (any of them changes `updatedAt`):
  ```bash
  t0=$(gh pr view <n> --json updatedAt -q .updatedAt)
  while [ "$(gh pr view <n> --json state,updatedAt -q '.state+" "+.updatedAt')" = "OPEN $t0" ]; do
    sleep 120
  done
  ```
  Under Claude Code run it as a background command, so its exit wakes the
  orchestrator; a task-mode poll pass checks the same state instead.
  Merged -> continue. Closed unmerged -> stop and report. New activity ->
  read every review and comment, inline ones included, and run Feedback;
  if the activity was the agent's own push or comment, watch again.

## Branches

- Know the branch before every commit: `git branch --show-current`. A
  commit on the wrong branch is moved before anything else happens.
- One branch per PR. The spec PR lives on `spec/spec-<nnn>-<slug>`; every
  phase gets a new branch off the updated base after the previous PR
  merged. Never stack a phase on the spec branch or on an unmerged phase.
- Follow the project's branching convention: feature branches where it
  uses them, trunk commits where it lands on trunk.
- Clean up after every merge: delete the remote branch (`--delete-branch`
  on merge, or `git push origin --delete <branch>`), delete the local one
  (`git branch -d <branch>`), remove its worktree, and `git fetch
  --prune`. A bare-repo layout (`<repo>.git` with one worktree per
  branch) removes the worktree with `git worktree remove <path>` before
  deleting the branch.

