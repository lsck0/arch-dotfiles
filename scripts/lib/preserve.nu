# preserved/, the ~/sync write guard and the one tty question.

use log.nu *
use state.nu [state-dir path-kind]

const STAMP = '\.(\d{14})(\.\d+)?$'
const STAMP_FORMAT = "%Y%m%d%H%M%S"

export def preserve-dir []: nothing -> path {
    state-dir | path join preserved
}

# Refuses a write under ~/sync: a file made there before syncthing delivers the real one collides with it.
export def sync-guard [path: path]: nothing -> nothing {
    if (^realpath -m $path) =~ '^/home/[^/]+/sync(/|$)' {
        error make {msg: $"refusing to write ($path), ~/sync belongs to syncthing"}
    }
}

# Kept under preserved/, never beside the original where a scanning dir would load it.
export def preserve-aside [path: path]: nothing -> any {
    if (path-kind $path) == "" { return null }
    let base = $"(preserve-dir)(^realpath -ms $path).(date now | format date $STAMP_FORMAT)"
    mut dest = $base
    mut n = 0
    while (path-kind $dest) != "" {
        $n += 1
        $dest = $"($base).($n)"
    }
    mkdir ($dest | path dirname)
    ^mv -n $path $dest
    log-info $"($path): the earlier copy kept as ($dest)"
    $dest
}

# Every preserved copy with its stamp, read from the name since mv keeps the original mtime.
export def preserve-entries []: nothing -> table<stamp: string, path: string> {
    if not (preserve-dir | path exists) { return [] }
    ^find (preserve-dir) -mindepth 1 -regextype posix-extended -regex '.*\.[0-9]{14}(\.[0-9]+)?' -prune -print
    | lines | each {|path| {stamp: ($path | parse --regex $STAMP | get 0.capture0), path: $path} } | sort-by stamp path
}

export def preserve-report []: nothing -> string {
    let entries = preserve-entries
    if ($entries | is-empty) { return $"preserved: none in (preserve-dir)" }
    let oldest = $entries | first
    let day = $oldest.stamp | str substring 0..7 | into datetime --format "%Y%m%d" | format date "%Y-%m-%d"
    let original = $oldest.path | str replace (preserve-dir) "" | str replace --regex $STAMP ""
    $"preserved: ($entries | length) in (preserve-dir), (du (preserve-dir) | get 0.physical), oldest ($day) ($original)"
}

export def preserve-prune [days: int]: nothing -> nothing {
    let cutoff = (date now) - ($days * 1day) | format date $STAMP_FORMAT
    let old = preserve-entries | where stamp < $cutoff
    if ($old | is-empty) {
        log-info $"nothing in (preserve-dir) is older than ($days) days"
        return
    }
    log-warn $"preserved more than ($days) days ago, to delete:\n  ($old.path | str join "\n  ")"
    if not (tty-confirm $"preserve: delete these ($old | length)?") { return }
    $old.path | each { rm --recursive --force $in } | ignore
    ^find (preserve-dir) -mindepth 1 -type d -empty -delete
}

# Asks via /dev/tty: stdin may carry the secrets tar and stderr is captured under sync.
export def tty-confirm [question: string]: nothing -> bool {
    if ($env.DOTFILES_UNATTENDED? | is-not-empty) {
        log-warn "unattended, nothing done"
        return false
    }
    let asked = ^bash -c 'exec 3<>/dev/tty 2>/dev/null || exit 1; printf "%s [y/N] " "$1" >&3; read -r a <&3 && printf %s "$a"' confirm $question | complete
    if $asked.exit_code != 0 { log-warn $"($question) no terminal to ask on, nothing done" }
    ($asked.stdout | str trim) == "y"
}
