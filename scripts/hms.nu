#!/usr/bin/env -S nu --no-config-file

const SCRIPTS = path self | path expand | path dirname
use ($SCRIPTS | path join lib usage.nu) [die]
use ($SCRIPTS | path join lib state.nu) [xdg]

const TMS_CONFIG = [tms config.toml]
const SEARCH_DIR_DEFAULT = "projects"
const SEARCH_DEPTH_DEFAULT = 10
const FD_EXCLUDES = [elpa node_modules .cargo vendor target]
const SERVER_POLLS = 100
const SERVER_POLL_INTERVAL = 100ms
const FZF_ARGS = [
    --prompt "> " --delimiter "\t" --with-nth 1 --border none --no-scrollbar --pointer " " --marker " " --gutter " "
    --color "fg:-1,bg:-1,fg+:0,bg+:12,hl:12,hl+:0,info:11,prompt:10,gutter:-1"
]

def server-running []: nothing -> bool {
    (do { ^herdr status server } | complete | get stdout) =~ "status: running"
}

def repos-in [root: string, depth: int]: nothing -> list<record> {
    let excludes = $FD_EXCLUDES | each { [--exclude $in] } | flatten
    do { ^fd --type d --type f --hidden --no-ignore --max-depth ($depth + 1) ...$excludes '^(\.git|HEAD)$' $root }
    | complete | get stdout | lines
    | where {|entry|
        if ($entry | path basename) == HEAD {
            let dir = $entry | path dirname
            (($entry | path type) == file and ($dir | path join objects | path type) == dir
                and ($dir | path join refs | path type) == dir and $entry !~ '/\.(git|bare)/')
        } else {
            ($entry | path type) == dir or (open --raw $entry | lines | first) =~ '^gitdir: .*/worktrees/[^/]+/?$'
        }
    }
    | each {|git| $git | path dirname | {display: ($in | path relative-to $root), full: $in} }
}

# Pick a project from tms's search dirs and bookmarks and open it as a herdr session.
def main []: nothing -> nothing {
    let config_file = xdg config ...$TMS_CONFIG
    # without one, the same default as the editors' project pickers
    let config = if ($config_file | path exists) { open $config_file } else {
        {search_dirs: [{path: ($nu.home-dir | path join $SEARCH_DIR_DEFAULT), depth: $SEARCH_DEPTH_DEFAULT}]}
    }
    let projects = $config.search_dirs? | default [] | where { $in.path | path exists }
        | each { repos-in $in.path ($in.depth? | default $SEARCH_DEPTH_DEFAULT) } | flatten
    let bookmarks = $config.bookmarks? | default [] | where { ($in | path type) == dir }
        | each { {display: ($in | path basename), full: $in} }
    let unique = $projects ++ $bookmarks | uniq-by full
    let clashing = $unique.display | uniq --repeated
    let entries = $unique
        | each {|e| if $e.display in $clashing { $e | update display $e.full } else { $e } }
        | sort-by display
    if ($entries | is-empty) { die "no git repos or bookmarks found in tms's config" }
    let rows = $entries | each { $"($in.display)\t($in.full)" } | str join "\n"
    let picked = try { $rows | ^fzf ...$FZF_ARGS } catch { "" }
    if $picked == "" { return }
    let selected = $picked | str trim --right | split row "\t" | get 1
    if not (server-running) {
        ^setsid -f herdr server out+err> /dev/null
        if not (seq 1 $SERVER_POLLS | any {|_| sleep $SERVER_POLL_INTERVAL; server-running }) {
            die $"herdr server failed to start within ($SERVER_POLLS * $SERVER_POLL_INTERVAL)"
        }
    }
    ^herdr-open $selected ($selected | path basename)
    if ($env.HERDR_ENV? | is-empty) { exec herdr }
}
