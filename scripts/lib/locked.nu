# Writes that must not interleave, run under flock by state-locked with json args on stdin.

use json.nu [json-edits-apply json-keys json-keys-restore]
use ini.nu [ini-apply]
use state.nu [save-atomic]

def main [] {
    error make {msg: "locked.nu <json-update|ini-update>"}
}

# Restores the keys dot no longer sets (drop), applies the edits, and prints {changed, owned, keys} as json: owned
# when the new content is to be recorded, keys what each edited path held before dot set it (known: the record's).
def "main json-update" []: string -> nothing {
    let args = $in | from json
    let raw = if ($args.file | path exists) { open --raw $args.file } else { "" }
    let current = if ($raw | str trim | is-empty) { {} } else { $raw | from json }
    # a caller that tracks no keys (an older engine mid-sync) passes neither: its before-values are unknown
    let keys = json-keys $current $args.edits $args.known?
    let merged = $current | json-keys-restore ($args.drop? | default []) | json-edits-apply $args.edits
    if $merged == $current and ($raw | str trim | is-not-empty) {
        print ({changed: false, owned: false, keys: $keys} | to json --raw)
        return
    }
    let owned = ($raw | is-not-empty) and ($raw | hash sha256) == $args.recorded_sum
    $merged | to json --indent 2 | $"($in)\n" | save-atomic $args.file
    print ({changed: true, owned: $owned, keys: $keys} | to json --raw)
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

