#!/usr/bin/env -S nu --no-config-file
# reverts spicetify class renames the spotify js no longer emits (spotify >= 1.2.96)

const CSS_MAP = "/opt/spicetify-cli/css-map.json"
const SKIP = [user.css colors.css]
const PRELUDE = '(?s)(?<gap>.*?)(?<sep>^|[};])(?<sel>[^{};]+)\{'

def preludes [text: string]: nothing -> record {
    let rows = $text | parse --regex $PRELUDE
    let used = $rows | each { $"($in.gap)($in.sep)($in.sel){" } | str join | str length --utf-8-bytes
    {rows: $rows, tail: ($text | str substring $used..)}
}

def rename [sel: string, map: record, names: record]: nothing -> string {
    $sel | parse --regex '(?<word>[-\w]+)|(?<other>[^-\w]+)' | each {|t|
        if $t.word == null { $t.other } else if ($map | get --optional $t.word) == null { $t.word } else {
            $names | get --optional $t.word | default $t.word
        }
    } | str join
}

def main [xpui?: path]: nothing -> nothing {
    let data = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share)
    let xpui = $xpui | default ($data | path join spotify-patched Apps xpui)
    let state = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state)
    let backup = $state | path join spicetify Backup xpui.spa
    let missing = [$xpui $CSS_MAP $backup] | where not ($it | path exists)
    if ($missing | is-not-empty) {
        print -e $"spicetify-unmap-classes: ($missing.0) missing, nothing to do"
        return
    }
    let map = open --raw $CSS_MAP | from json
    let members = ^unzip -Z1 $backup | lines
    let pristine = $members | where { str ends-with .css }
        | each {|n| {name: ($n | path basename), text: (^unzip -p $backup $n)} }
    let scripts = ^unzip -p $backup ...($members | where { str ends-with .js }) | decode utf-8
    let live = glob ($xpui | path join *.js) | each { open --raw $in | decode utf-8 } | str join "\n"
    let keep = $map | transpose hashed friendly
        | where {|r| ($scripts | str contains $r.hashed) or ($live | str contains $r.friendly) }
        | reduce --fold {} {|r, acc| $acc | insert $r.hashed $r.friendly }
    mut restored = 0
    mut files = 0
    for css in (glob ($xpui | path join *.css) | sort) {
        let name = $css | path basename
        let source = $pristine | where name == $name | get --optional 0.text
        if $name in $SKIP or $source == null { continue }
        let original = (preludes $source).rows | where not ($it.sel | str trim --left | str starts-with "@")
            | each {|p| {patched: (rename $p.sel $map $map), wanted: (rename $p.sel $map $keep)} }
            | uniq-by patched | reduce --fold {} {|r, acc| $acc | upsert $r.patched $r.wanted }
        let text = preludes (open --raw $css | decode utf-8)
        let fixed = $text.rows | each {|p| $p | insert fixed ($original | get --optional $p.sel | default $p.sel) }
        let count = $fixed | where {|p| $p.fixed != $p.sel } | length
        if $count == 0 { continue }
        $fixed | each { $"($in.gap)($in.sep)($in.fixed){" } | append $text.tail | str join | save --force $css
        $restored += $count
        $files += 1
    }
    print $"spicetify-unmap-classes: restored ($restored) selectors in ($files) files"
}
