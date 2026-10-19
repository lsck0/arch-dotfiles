use log.nu *
use state.nu [state-dir state-locked path-kind]
use sandbox.nu [plan-note]

const STAMP = '\.(\d{14})(\.\d+)?$'
const STAMP_FORMAT = "%Y%m%d%H%M%S"

export def written-file []: nothing -> path {
    state-dir | path join written
}

def seen-file []: nothing -> path {
    $"(written-file).seen"
}

export def preserve-dir []: nothing -> path {
    state-dir | path join preserved
}

# a file made here before syncthing delivers the real one collides with it
export def sync-guard [path: path]: nothing -> nothing {
    if (^realpath -m $path) =~ '^/home/[^/]+/sync(/|$)' {
        error make {msg: $"refusing to write ($path), ~/sync belongs to syncthing"}
    }
}

# by its full path under preserved/, never beside the original, where a scanning dir would load it as a second config
export def preserve-aside [path: path]: nothing -> path {
    let base = $"(preserve-dir)(^realpath -ms $path).(date now | format date $STAMP_FORMAT)"
    mut dest = $base
    mut n = 0
    while (path-kind $dest) != "" {
        $n += 1
        $dest = $"($base).($n)"
    }
    mkdir ($dest | path dirname)
    ^mv -n $path $dest
    plan-note preserve $path $"aside to ($dest)"
    log-info $"($path): the earlier copy kept as ($dest)"
    $dest
}

export def written-record [path: path]: nothing -> nothing {
    if (seen-file | path exists) { $"($path)\n" | save --append (seen-file) }
    state-locked $"(written-file).lock" written-record {file: (written-file), path: $path, sum: (open --raw $path | hash sha256)}
}

export def written-forget [...paths: path]: nothing -> nothing {
    state-locked $"(written-file).lock" written-forget {file: (written-file), paths: $paths}
}

export def written-begin []: nothing -> nothing {
    mkdir (state-dir)
    "" | save --force (seen-file)
}

# only after every module finished: otherwise what a failed module did not reach would be forgotten
export def written-prune [keep: list<string>]: nothing -> nothing {
    if not ((seen-file | path exists) and (written-file | path exists)) { return }
    let seen = open --raw (seen-file) | lines | append $keep
    let gone = open --raw (written-file) | lines | where $it != "" | split column "\t" path sum
        | where {|row| (path-kind $row.path) == "" or $row.path not-in $seen }
    for row in $gone {
        plan-note forget $row.path "no module manages it any more"
        log-info $"no longer managed, forgotten: ($row.path)"
    }
    if ($gone | is-not-empty) { written-forget ...$gone.path }
    written-end
}

export def written-end []: nothing -> nothing {
    rm --force (seen-file)
}

# by the stamp in the name: mv keeps the original mtime
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

# yes only from a person at the terminal: nu's input reads stdin, which may carry the secrets tar
export def tty-confirm [question: string]: nothing -> bool {
    if ($env.DOTFILES_UNATTENDED? | is-not-empty) {
        log-warn "unattended, nothing done"
        return false
    }
    (try { ^bash -c 'read -rp "$1 [y/N] " a < /dev/tty && printf %s "$a"' confirm $question } catch { "" }) == "y"
}
