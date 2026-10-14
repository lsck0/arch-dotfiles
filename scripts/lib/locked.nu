# every read-modify-write of a file modules share, run under flock by state-locked with its arguments on stdin

use json.nu [json-edits-apply]

def main [] {
    error make {msg: "locked.nu <written-record|written-forget|json-update|units-set>"}
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

# prints "changed" when the file was rewritten, and "owned" too when its new content is to be recorded
def "main json-update" []: string -> nothing {
    let args = $in | from json
    let raw = if ($args.file | path exists) { open --raw $args.file } else { "" }
    let current = if ($raw | str trim | is-empty) { {} } else { $raw | from json }
    let merged = $current | json-edits-apply $args.edits
    if $merged == $current and ($raw | str trim | is-not-empty) {
        return
    }
    let owned = ($raw | is-not-empty) and ($raw | hash sha256) == $args.recorded_sum
    # the same inode, so an app holding the file open or a link to it keeps working
    $merged | to json --indent 2 | $"($in)\n" | save --force $args.file
    print (if $owned { "changed owned" } else { "changed" })
}

# the plan sandbox's unit snapshot: <unit> <state> lines, one unit's state replaced
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
