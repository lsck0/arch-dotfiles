# JSON edits as data, for json-merge: json-set and json-delete records applied in order by json-edits-apply.

export def json-set [path: list<string>, value: any]: nothing -> record {
    {path: $path, value: $value}
}

export def json-delete [path: list<string>]: nothing -> record {
    {path: $path, delete: true}
}

export def json-edits-apply [edits: list<record>]: any -> any {
    let start = $in
    $edits | reduce --fold $start {|edit, doc|
        if ($edit.path | is-empty) { error make {msg: "json edit with an empty path"} }
        let cell = $edit.path | into cell-path
        if ($edit.delete? | default false) { $doc | reject --optional $cell } else { $doc | upsert $cell $edit.value }
    }
}

# What a path holds: {value: v}, or {absent: true} when the document has no such key.
def json-slot [doc: any, path: list<string>]: nothing -> record {
    let parent = if ($path | length) == 1 { $doc } else { $doc | get --optional ($path | drop | into cell-path) }
    if ($parent | describe) !~ '^record' or ($path | last) not-in ($parent | columns) { return {absent: true} }
    {value: ($parent | get ($path | last))}
}

# Each path the edits touch, with what it held before dot first set it and what dot sets. known: the record's keys,
# whose before-values stand; null for a record from before keys were tracked, whose before-values are unknown.
export def json-keys [current: any, edits: list<record>, known: any]: nothing -> list<record> {
    $edits | each {|e|
        let kept = if $known == null { null } else { $known | where path == $e.path | get --optional 0 }
        let before = if $kept != null { $kept.before } else if $known == null { {unknown: true} } else { json-slot $current $e.path }
        {path: $e.path, before: $before, set: (if ($e.delete? | default false) { {absent: true} } else { {value: $e.value} })}
    }
}

# Puts back what each key held before dot set it, only where it still holds dot's value: a hand edit since stays.
export def json-keys-restore [keys: list<record>]: any -> any {
    let start = $in
    $keys | reduce --fold $start {|k, doc|
        if ($k.before.unknown? | default false) or (json-slot $doc $k.path) != $k.set { return $doc }
        let cell = $k.path | into cell-path
        if ($k.before.absent? | default false) { $doc | reject --optional $cell } else { $doc | upsert $cell $k.before.value }
    }
}
