# edits as data, so a merge can cross into the locked process; a set replaces the whole value, like jq's `=`

export def json-set [path: list<string>, value: any]: nothing -> record {
    {path: $path, value: $value}
}

export def json-delete [path: list<string>]: nothing -> record {
    {path: $path, delete: true}
}

export def json-edits-apply [edits: list<record>]: any -> any {
    let start = $in
    $edits | reduce --fold $start {|edit, doc|
        if ($edit.path | is-empty) {
            error make {msg: "json edit with an empty path"}
        }
        let cell = $edit.path | into cell-path
        if ($edit.delete? | default false) {
            $doc | reject --optional $cell
        } else {
            $doc | upsert $cell $edit.value
        }
    }
}
