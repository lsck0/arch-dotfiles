# Section "" is the part before the first header; missing_only keeps set values.
export def ini-apply [values: record, missing_only: bool]: string -> string {
    let start = $in
    $values | items {|section, keys| {section: $section, keys: $keys} } | reduce --fold ($start | lines) {|s, lines|
        let headers = $lines | enumerate | where ($it.item | str trim) =~ '^\[.*\]$'
        let begin = if $s.section == "" { 0 } else {
            $headers | where ($it.item | str trim) == $"[($s.section)]" | get --optional 0.index | if $in == null { null } else { $in + 1 }
        }
        let lines = if $begin == null { $lines ++ (if ($lines | is-empty) { [] } else { [""] }) ++ [$"[($s.section)]"] } else { $lines }
        let begin = $begin | default ($lines | length)
        let end = $lines | enumerate | skip $begin | where ($it.item | str trim) =~ '^\[.*\]$' | get --optional 0.index | default ($lines | length)
        $s.keys | items {|key, value| {key: $key, value: ($value | into string)} } | reduce --fold {lines: $lines, end: $end} {|kv, acc|
            let at = $acc.lines | enumerate | skip $begin | first ($acc.end - $begin) | where {|l| ($l.item | split row "=" | first | str trim) == $kv.key and ($l.item | str contains "=") } | get --optional 0.index
            if $at == null {
                {lines: ($acc.lines | insert $acc.end $"($kv.key)=($kv.value)"), end: ($acc.end + 1)}
            } else if $missing_only {
                $acc
            } else {
                {lines: ($acc.lines | update $at $"($kv.key)=($kv.value)"), end: $acc.end}
            }
        } | get lines
    } | str join "\n" | $"($in)\n"
}

# One row per line: its section ("" before the first), key and value (null for a header, comment or blank).
export def ini-rows [text: string]: nothing -> table<section: string, key: any, value: any, line: string> {
    $text | lines | reduce --fold {section: "", rows: []} {|line, acc|
        let section = $line | str trim | parse --regex '^\[(?<s>.*)\]$' | get --optional 0.s | default $acc.section
        let kv = if ($line =~ '^\s*[#;\[]') { null } else { $line | parse --regex '^(?<key>[^=]+?)=(?<value>.*)$' | get --optional 0 }
        {section: $section, rows: ($acc.rows | append {section: $section, key: ($kv.key? | if $in == null { null } else { str trim }), value: ($kv.value? | if $in == null { null } else { str trim }), line: $line})}
    } | get rows
}
