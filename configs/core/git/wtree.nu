#!/usr/bin/env -S nu --no-config-file
# branch/worktree picker; a new worktree goes where nvim's lua/lib/worktree.lua puts it

const WORKTREES_DIR = ".worktrees"
const BARE_DIR = ".bare"

def hold []: nothing -> nothing {
    input "enter to close..." | ignore
}

def --wrapped git-ok [...args: string]: nothing -> bool {
    (do { ^git ...$args } | complete).exit_code == 0
}

def worktrees-parse []: string -> table {
    $in | split row "\n\n" | where ($it | str trim) != "" | each {|block|
        let lines = $block | lines
        let field = {|key|
            $lines | where $it starts-with $"($key) " | each { str substring (($key | str length) + 1).. }
        }
        {path: (do $field worktree | first), branch: (do $field branch | get --optional 0), bare: ("bare" in $lines)}
    }
}

# ties go to the shallower dir, so one stray nested worktree never becomes the convention
def parent-shared [linked: table]: nothing -> any {
    if ($linked | is-empty) { return null }
    let counts = $linked.path | path dirname | uniq --count
    let max = $counts.count | math max
    $counts | where count == $max | sort-by { $in.value | str length } | first | get value
}

def main []: nothing -> nothing {
    # plain git from cwd, not --show-toplevel: that fails at a bare root and names branches/main "main"
    let listed = do { ^git worktree list --porcelain } | complete
    if $listed.exit_code != 0 {
        print --stderr "not a git repo"
        hold
        exit 1
    }
    let trees = $listed.stdout | worktrees-parse
    # the first entry is the main checkout or the bare repo itself
    let main = $trees.0
    let root = if ($main.path | path basename) == $BARE_DIR { $main.path | path dirname } else { $main.path }
    let repo = $root | path basename

    # local and origin branches; typing a new name in fzf creates that branch (fzf exits 1 then)
    let branches = ^git for-each-ref '--format=%(refname)' refs/heads refs/remotes/origin | lines
        | each { str replace --regex '^refs/(heads|remotes/origin)/' "" } | where $it != HEAD | uniq
    let picked = $branches | str join "\n" | ^fzf "--prompt=worktree branch> " --print-query --height=100% | complete
        | get stdout | lines
    if ($picked | is-empty) or ($picked | last) == "" { return }
    let branch = $picked | last

    let existing = $trees | where branch == $"refs/heads/($branch)" | get --optional 0.path
    let wt = if $existing != null { $existing } else {
        # feat/x is one dir, like clones-sdd-repos.sh's slug_of
        let slug = $branch | str replace --all "/" "-"
        let parent = parent-shared ($trees | skip 1)
        let wt = if $parent != null {
            $parent | path join $slug
        } else if not $main.bare {
            $nu.home-dir | path join $WORKTREES_DIR $repo $slug
        } else if ($main.path | path basename) == $BARE_DIR {
            $main.path | path dirname | path join branches $slug
        } else {
            $main.path | path join $slug
        }
        let added = try {
            if (git-ok show-ref --verify --quiet $"refs/heads/($branch)") {
                ^git worktree add $wt $branch
            } else if (git-ok show-ref --verify --quiet $"refs/remotes/origin/($branch)") {
                ^git worktree add --track -b $branch $wt $"origin/($branch)"
            } else {
                ^git worktree add -b $branch $wt
            }
            true
        } catch { false }
        if not $added {
            print --stderr "worktree add failed"
            hold
            exit 1
        }
        $wt
    }

    # no slashes in a session/workspace label
    let label = $"($repo)-($branch | str replace --all '/' '-')"
    if ($env.HERDR_SESSION? | default "") + ($env.HERDR_ENV? | default "") != "" {
        ^herdr-open $wt $label
    } else if ($env.TMUX? | default "") != "" {
        if not ((do { ^tmux has-session -t $"=($label)" } | complete).exit_code == 0) {
            ^tmux new-session -d -s $label -c $wt
        }
        # the session-created hook lays out the windows
        ^tmux switch-client -t $"=($label)"
    } else {
        cd $wt
        exec $env.SHELL
    }
}
