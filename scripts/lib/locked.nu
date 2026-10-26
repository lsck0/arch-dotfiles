# The writes that must not interleave, each run under flock by state-locked (state.nu) with its
# arguments as json on stdin.

use json.nu [json-edits-apply]
use ini.nu [ini-apply]
use state.nu [save-atomic]

def main [] {
    error make {msg: "locked.nu <json-update|ini-update>"}
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
    $merged | to json --indent 2 | $"($in)\n" | save-atomic $args.file
    print (if $owned { "changed owned" } else { "changed" })
}

# Follows a link (save writes through it), so the file it points to keeps every key the module does not set.
def "main ini-update" []: string -> nothing {
    let args = $in | from json
    let raw = if ($args.file | path exists) { open --raw $args.file } else { "" }
    let merged = $args.edits | reduce --fold $raw {|e, text| $text | ini-apply $e.values $e.missing_only }
    if $merged == $raw { return }
    $merged | save-atomic $args.file
    print changed
}

