# The writes that must not interleave, each run under flock by state-locked (state.nu) with its
# arguments as json on stdin.

use json.nu [json-edits-apply]
use ini.nu [ini-apply]

def main [] {
    error make {msg: "locked.nu <written-record|written-forget|json-update|ini-update|units-set>"}
}

def records-read [file: path]: nothing -> table<path: string, sum: string> {
    if not ($file | path exists) {
        return []
    }
    open --raw $file | lines | where $it != "" | split column "\t" path sum
}

def records-write [file: path, rows: table]: nothing -> nothing {
    mkdir ($file | path dirname)
    $rows | each {|row| $"($row.path)\t($row.sum)\n" } | str join | save --force $"($file).new"
    mv --force $"($file).new" $file
}

def "main written-record" []: string -> nothing {
    let args = $in | from json
    let rows = records-read $args.file | where path != $args.path
    records-write $args.file ($rows | append {path: $args.path, sum: $args.sum})
}

def "main written-forget" []: string -> nothing {
    let args = $in | from json
    records-write $args.file (records-read $args.file | where path not-in $args.paths)
}

# Prints "changed" when rewritten, plus "owned" when the new content is to be recorded.
def "main json-update" []: string -> nothing {
    let args = $in | from json
    let raw = if ($args.file | path exists) { open --raw $args.file } else { "" }
    let current = if ($raw | str trim | is-empty) { {} } else { $raw | from json }
    let merged = $current | json-edits-apply $args.edits
    if $merged == $current and ($raw | str trim | is-not-empty) {
        return
    }
    let owned = ($raw | is-not-empty) and ($raw | hash sha256) == $args.recorded_sum
    $merged | to json --indent 2 | $"($in)\n" | save --force $args.file
    print (if $owned { "changed owned" } else { "changed" })
}

# Follows a link (save writes through it), so the file it points to keeps every key the module does not set.
def "main ini-update" []: string -> nothing {
    let args = $in | from json
    let raw = if ($args.file | path exists) { open --raw $args.file } else { "" }
    let merged = $args.edits | reduce --fold $raw {|e, text| $text | ini-apply $e.values $e.missing_only }
    if $merged == $raw { return }
    $merged | save --force --raw $args.file
    print changed
}

# Replaces these units' state in the plan sandbox's unit snapshot of <unit> <state> lines.
def "main units-set" []: string -> nothing {
    let args = $in | from json
    let kept = if ($args.file | path exists) {
        open --raw $args.file | lines | where {|line| ($line | split row " " | first) not-in $args.units }
    } else {
        []
    }
    $kept | append ($args.units | each {|unit| $"($unit) ($args.state)" }) | str join "\n" | $"($in)\n"
    | save --force $args.file
}
