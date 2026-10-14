#!/usr/bin/env -S nu --no-config-file

const SCRIPTS = path self | path expand | path dirname
use ($SCRIPTS | path join lib usage.nu) [die]

const TMS_CONFIG = ".config/tms/config.toml"
const SEARCH_DEPTH_DEFAULT = 10
const FD_EXCLUDES = [elpa node_modules .cargo vendor target]
const SERVER_POLLS = 100
const SERVER_POLL_INTERVAL = 100ms
# ansi indices match tms's picker_colors; the herdr popup draws the frame, so no fzf border
const FZF_ARGS = [
    --prompt "> " --delimiter "\t" --with-nth 1 --border none --no-scrollbar --pointer " " --marker " " --gutter " "
    --color "fg:-1,bg:-1,fg+:0,bg+:12,hl:12,hl+:0,info:11,prompt:10,gutter:-1"
]

def server-running []: nothing -> bool {
    (do { ^herdr status server } | complete | get stdout) =~ "status: running"
}

def repos-in [root: string, depth: int]: nothing -> list<record> {
    let excludes = $FD_EXCLUDES | each { [--exclude $in] } | flatten
    do { ^fd --type d --type f --hidden --no-ignore --max-depth $depth ...$excludes '^\.git$' $root } | complete
    | get stdout | lines
    # a .git file is a project only as a linked worktree, so submodules and the `gitdir: ./.bare` root stay out
    | where {|git| ($git | path type) == dir or (open --raw $git | lines | first) =~ '^gitdir: .*/worktrees/[^/]+/?$' }
    | each {|git| $git | path dirname | {display: ($in | path relative-to $root), full: $in} }
}

# Pick a project from tms's search dirs and bookmarks and open it as a herdr session.
def main []: nothing -> nothing {
    let config = open ($nu.home-dir | path join $TMS_CONFIG)
    let projects = $config.search_dirs? | default [] | where { $in.path | path exists }
        | each { repos-in $in.path ($in.depth? | default $SEARCH_DEPTH_DEFAULT) } | flatten
    # tms bookmarks are non-git dirs, under the session name tms gives them
    let bookmarks = $config.bookmarks? | default [] | where { ($in | path type) == dir }
        | each { {display: ($in | path basename), full: $in} }
    let entries = $projects ++ $bookmarks | sort-by display | uniq-by display
    if ($entries | is-empty) { die "no git repos or bookmarks found in tms's config" }
    let rows = $entries | each { $"($in.display)\t($in.full)" } | str join "\n"
    let picked = try { $rows | ^fzf ...$FZF_ARGS } catch { "" }
    if $picked == "" { return }
    let selected = $picked | str trim --right | split row "\t" | get 1
    if not (server-running) {
        ^setsid -f herdr server out+err> /dev/null
        if not (seq 1 $SERVER_POLLS | any {|_| sleep $SERVER_POLL_INTERVAL; server-running }) {
            die "herdr server failed to start within 10s"
        }
    }
    ^herdr-open $selected ($selected | path basename)
    if ($env.HERDR_ENV? | is-empty) { exec herdr }
}
