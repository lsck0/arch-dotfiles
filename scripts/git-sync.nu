#!/usr/bin/env -S nu --no-config-file

const SCRIPTS = path self | path expand | path dirname
use ($SCRIPTS | path join lib usage.nu) [die]

const JOBS_DEFAULT = 8
const SEARCH_DEPTH = 5
const PRUNED = [vendor node_modules .cache target .venv .direnv]

def --wrapped git-out [dir: path, ...args: string]: nothing -> string {
    do { ^git -C $dir ...$args } | complete | get stdout | str trim
}

# refs/remotes/*/HEAD is skipped: fetch creates it without anything new
def refs-of [dir: path, ...patterns: string]: nothing -> list<string> {
    git-out $dir for-each-ref --exclude=refs/remotes/*/HEAD "--format=%(refname) %(objectname)" ...$patterns | lines
}

def repos-under [base: path]: nothing -> list<path> {
    let pruned = $PRUNED | each { [-name $in -o] } | flatten | drop
    (^find $base -maxdepth $SEARCH_DEPTH -type d "(" ...$pruned -o -path "*/.git/*" ")" -prune
        -o -type f -name HEAD -printf "%h\n")
    | lines | where { ($in | path join objects | path type) == dir and ($in | path join refs | path type) == dir }
    | str replace --regex '/\.git$' '' | uniq | sort
    | where {|dir|
        let top = git-out ($dir | path dirname) rev-parse --show-toplevel
        $top == "" or $top == $dir or (do { ^git -C $top check-ignore -q $dir } | complete).exit_code != 0
    }
}

# customer repos fetch and push with their own credentials
def --wrapped remote-git [dir: path, ...args: string]: nothing -> record {
    if ($dir | path join .identity envrc | path exists) {
        do { ^direnv exec $dir git -C $dir ...$args } | complete
    } else {
        do { ^git -C $dir ...$args } | complete
    }
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
    let porcelain = git-out $dir status --porcelain | lines
    let staged = $porcelain | any { $in =~ '^[MADRC]' }
    let unstaged = $porcelain | any { $in =~ '^.[MADRC]' }
    let local = [
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
    let fetched = $before != $after and ($upstream == "" or (do $others $before) != (do $others $after))
    let pulled = if $upstream != "" and not ($staged or $unstaged or $unpushed) {
        let pull = remote-git $dir pull
        if $pull.exit_code != 0 {
            "PULL FAILED"
        } else if not ($"($pull.stdout)($pull.stderr)" =~ "Already up to date") {
            "PULLED"
        }
    }
    # non-force, so a diverged branch just reports PUSH FAILED
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
    if ($base | path type) != dir { die --misuse $"not a directory: ($dir)" }
    let repos = repos-under $base
    let names = $repos | each {|r| if $r == $base { $r } else { $r | path relative-to $base } }
    let pad = $names | each { str length } | append 0 | math max
    $repos | zip $names | par-each --threads ($env.GIT_SYNC_JOBS? | default $JOBS_DEFAULT | into int) {|pair|
        let bare = (git-out $pair.0 rev-parse --is-bare-repository) == "true"
        let statuses = sync-one $pair.0 $bare | if ($in | is-empty) { ["UP TO DATE"] } else { $in }
        print $"($pair.1 | fill -w $pad)  ($statuses | str join ', ')(if $bare { '  (bare)' } else { '' })"
    } | ignore
}
