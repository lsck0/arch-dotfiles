#!/usr/bin/env -S nu --no-config-file

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join scripts lib proc.nu) [notify]

# Files, links and text to the paired phone over KDE Connect. What the phone sends lands on its own: files in
# the download dir, links in the browser, text on the clipboard.

const APP = "phone"
const URI_LIST = "text/uri-list"
const TEXT_TYPES = ["text/plain;charset=utf-8" text/plain UTF8_STRING STRING TEXT]
const URL_PATTERN = '^[a-zA-Z][a-zA-Z0-9+.-]*://\S+$'

# One share target: an existing path is a file, a single scheme:// word a link (file:// included), the rest text.
export def share-target [target: string, exists: bool]: nothing -> record<kind: string, value: string> {
    if $exists { return {kind: file, value: ($target | path expand)} }
    let trimmed = $target | str trim
    if $trimmed =~ $URL_PATTERN { return {kind: url, value: $trimmed} }
    {kind: text, value: $target}
}

# The entries of a text/uri-list, comments and blank lines dropped.
export def uri-list-parse [text: string]: nothing -> list<string> {
    $text | lines | each { str trim } | where { $in != "" and not ($in | str starts-with "#") }
}

# What the clipboard offers to share: uri-list (copied files), text, or none (an image alone, empty).
export def clipboard-source [types: list<string>]: nothing -> string {
    if $URI_LIST in $types { return uri-list }
    if ($types | any { $in in $TEXT_TYPES }) { return text }
    "none"
}

# The one paired, reachable device in `kdeconnect-cli --list-available --id-name-only`'s output.
export def device-pick [listing: string]: nothing -> record<id: string, name: string> {
    let devices = $listing | lines | parse --regex '^(?<id>\S+) (?<name>.*)$'
    match ($devices | length) {
        0 => { error make --unspanned {msg: "phone not reachable"} }
        1 => { $devices | first }
        _ => { error make --unspanned {msg: $"($devices | length) devices reachable: ($devices.name | str join ', ')"} }
    }
}

def device-reachable []: nothing -> record<id: string, name: string> {
    device-pick (^kdeconnect-cli --list-available --id-name-only | complete | get stdout)
}

def clipboard-targets []: nothing -> list<string> {
    let types = ^wl-paste --list-types | complete
    let source = if $types.exit_code == 0 { clipboard-source ($types.stdout | lines) } else { "none" }
    match $source {
        "uri-list" => { uri-list-parse (^wl-paste --no-newline --type $URI_LIST) }
        "text" => { [(^wl-paste --no-newline)] }
        _ => { error make --unspanned {msg: "clipboard holds no text or files"} }
    }
}

def --wrapped kdeconnect [device: record, ...args: string] {
    let out = ^kdeconnect-cli --device $device.id ...$args | complete
    if $out.exit_code != 0 { error make --unspanned {msg: ($out.stderr | str trim)} }
}

def report [notify: bool, title: string, body: string = "", --error] {
    print --stderr=$error ([$title $body] | where $it != "" | str join ": ")
    if $notify { notify $APP $title $body | ignore }
}

def attempt [notify: bool, action: closure] {
    try { do $action } catch {|e| report $notify "Not sent" $e.msg --error; exit 1 }
}

def main [] { help main }

# Shares files, links and text with the phone; without a target, what the clipboard holds.
def "main share" [...targets: string, --notify]: nothing -> nothing {
    attempt $notify {
        let device = device-reachable
        let clipboard = $targets | is-empty
        let raw = if $clipboard { clipboard-targets } else { $targets }
        # copied text is a file only as an absolute path: a copied word would resolve against wherever phone runs
        let items = $raw | each {|t| share-target $t ((not $clipboard or ($t | str starts-with "/")) and ($t | path exists)) }
        let urls = $items | where kind != text | get value
        if ($urls | is-not-empty) { kdeconnect $device --share ($urls | first) ...($urls | skip 1) }
        for text in ($items | where kind == text | get value) { kdeconnect $device --share-text $text }
        report $notify $"Sent to ($device.name)" ($items | length | $"($in) item(if $in != 1 { 's' })")
    }
}

# The desktop clipboard onto the phone's clipboard.
def "main clipboard" [--notify]: nothing -> nothing {
    attempt $notify {
        let device = device-reachable
        kdeconnect $device --send-clipboard
        report $notify $"Clipboard sent to ($device.name)"
    }
}
