#!/usr/bin/env -S nu --no-config-file

const SCRIPTS = path self | path expand | path dirname
use ($SCRIPTS | path join lib usage.nu) [die]
use ($SCRIPTS | path join lib repository.nu) [repository-find-under]

const JOBS_DEFAULT = 8
const SEARCH_DEPTH = 3
const CONFLICT = '^(U.|.U|AA|DD)'

def --wrapped git-out [dir: path, ...args: string]: nothing -> string {
    do { ^git -C $dir ...$args } | complete | get stdout | str trim
}

def refs-of [dir: path, ...patterns: string]: nothing -> list<string> {
    git-out $dir for-each-ref --exclude=refs/remotes/*/HEAD "--format=%(refname) %(objectname)" ...$patterns | lines
}

# a worktree shares its checkout's refs; an ignored nested repo belongs to the outer one
def repos-under [base: path]: nothing -> table<dir: path, kind: string> {
    repository-find-under $base $SEARCH_DEPTH | where kind != worktree | where {|repo|
        let top = git-out ($repo.dir | path dirname) rev-parse --show-toplevel
        $top == "" or $top == $repo.dir or (do { ^git -C $top check-ignore -q $repo.dir } | complete).exit_code != 0
    }
}

# through direnv where the repo has its own identity, so its credentials push and pull; no prompts, as parallel ones
# would fight over the terminal: a repo that needs input fails and is fixed alone
def --wrapped remote-git [dir: path, ...args: string]: nothing -> record {
    let prefix = if ($dir | path join .identity envrc | path exists) { [direnv exec $dir] } else { [] }
    with-env {GIT_TERMINAL_PROMPT: "0"} { do { run-external ...($prefix ++ [git -C $dir ...$args]) } | complete }
}

def sync-one [dir: path, bare: bool]: nothing -> list<string> {
    let no_remote = (git-out $dir remote) == ""
    if $bare {
        let before = refs-of $dir
        let fetch_failed = (remote-git $dir fetch --all --prune --quiet).exit_code != 0
        return ([
            (if $fetch_failed { "FETCH FAILED" })
            (if $before != (refs-of $dir) { "FETCHED" })
            (if $no_remote { "NO REMOTE" })
        ] | compact)
    }
    # untrimmed: the first entry's leading space is what tells unstaged from staged
    let porcelain = do { ^git -C $dir status --porcelain } | complete | get stdout | lines
    let conflicted = $porcelain | any { $in =~ $CONFLICT }
    let resolved = $porcelain | where $it !~ $CONFLICT
    let staged = $resolved | any { $in =~ '^[MADRCT]' }
    let unstaged = $resolved | any { $in =~ '^.[MADRCT]' }
    let local = [
        (if $conflicted { "CONFLICTS" })
        (if $staged { "STAGED CHANGES" })
        (if $unstaged { "UNSTAGED CHANGES" })
        (if ($porcelain | any { str starts-with "??" }) { "UNTRACKED FILES" })
    ] | compact
    if $no_remote { return ($local | append "NO REMOTE") }
    let upstream = git-out $dir rev-parse --symbolic-full-name "@{u}"
    let ahead = {|| $upstream != "" and (git-out $dir log "@{u}..HEAD" --oneline) != "" }
    let unpushed = do $ahead
    let before = refs-of $dir refs/remotes
    let fetch_failed = (remote-git $dir fetch --all --quiet).exit_code != 0
    let after = refs-of $dir refs/remotes
    let others = {|refs| $refs | where { not ($in | str starts-with $"($upstream) ") } }
    let pull_skipped = $conflicted or $staged or $unstaged or $unpushed
    # a pull reports upstream movement as PULLED; without one, it is only FETCHED
    let fetched = $before != $after and ($upstream == "" or $pull_skipped or (do $others $before) != (do $others $after))
    let pulled = if $upstream != "" and not $pull_skipped {
        let head_before = git-out $dir rev-parse HEAD
        let pull = remote-git $dir pull
        if $pull.exit_code != 0 {
            "PULL FAILED"
        } else if (git-out $dir rev-parse HEAD) != $head_before {
            "PULLED"
        }
    }
    let pushed = if (do $ahead) { if (remote-git $dir push --quiet).exit_code == 0 { "PUSHED" } else { "PUSH FAILED" } }
    $local
    | append (if $unpushed { if $pushed == "PUSHED" { "PUSHED" } else { "UNPUSHED COMMITS" } })
    | append (if $fetch_failed { "FETCH FAILED" })
    | append (if $fetched { "FETCHED" })
    | append $pulled
    | append (if $pushed == "PUSH FAILED" { $pushed })
    | compact
}

# Fetch, pull and push every git repo under a dir (default: here) in parallel, GIT_SYNC_JOBS at a time.
def main [dir?: path]: nothing -> nothing {
    let base = $dir | default "." | path expand
    if ($base | path type) != dir { die --misuse $"not a directory: ($base)" }
    let repos = repos-under $base
        | insert name {|r| if $r.dir == $base { $r.dir } else { $r.dir | path relative-to $base } }
    let pad = $repos.name | each { str length } | append 0 | math max
    $repos | par-each --threads ($env.GIT_SYNC_JOBS? | default $JOBS_DEFAULT | into int) {|repo|
        let bare = $repo.kind == bare
        let statuses = sync-one $repo.dir $bare | if ($in | is-empty) { ["UP TO DATE"] } else { $in }
        print $"($repo.name | fill -w $pad)  ($statuses | str join ', ')(if $bare { '  (bare)' } else { '' })"
    } | ignore
}
