#!/usr/bin/env -S nu --no-config-file
# phone.nu's pure parts (what a target is, the clipboard's offer, the device pick), then the kdeconnect-cli calls a
# share and a clipboard send make against stubbed kdeconnect-cli and wl-paste.

const PHONE = path self phone.nu
use $PHONE [share-target uri-list-parse clipboard-source device-pick]

const SHEBANG = "#!/usr/bin/env -S nu --no-config-file"
const DEVICE_ID = "_0a1b2c3d_4e5f_6a7b_8c9d_0e1f2a3b4c5d_"
const STUBS = {
    kdeconnect-cli: '
def --wrapped main [...args] {
    if "--list-available" in $args { print --raw (open --raw ($env.STUB_STATE | path join devices)); return }
    $"($args | str join " ")\n" | save --append ($env.STUB_STATE | path join calls)
}'
    wl-paste: '
def --wrapped main [...args] {
    let types = open --raw ($env.STUB_STATE | path join types)
    if "--list-types" in $args { print --raw $types; return }
    let type = if "--type" in $args { $args | get (($args | enumerate | where item == "--type" | first | get index) + 1) } else { "text" }
    print --raw --no-newline (open --raw ($env.STUB_STATE | path join ($type | str replace --all "/" "_")))
}'
    notify-send: 'def --wrapped main [...args] {}'
}

use std/assert

const TARGET_CASES = [
    [name target exists kind value];
    ["existing file" "/etc/hostname" true file "/etc/hostname"]
    ["https link" "https://example.org/a?b=c" false url "https://example.org/a?b=c"]
    ["link with surrounding newline" "\nhttps://example.org\n" false url "https://example.org"]
    ["file uri from a uri-list" "file:///home/u/a%20b.pdf" false url "file:///home/u/a%20b.pdf"]
    ["bare domain stays text" "example.org" false text "example.org"]
    ["sentence with a link is text" "see https://example.org" false text "see https://example.org"]
    ["two links are text" "https://a.org https://b.org" false text "https://a.org https://b.org"]
    ["missing path is text" "/no/such/file" false text "/no/such/file"]
    ["multi-line text kept verbatim" "line one\nline two\n" false text "line one\nline two\n"]
]

for c in $TARGET_CASES {
    let got = share-target $c.target $c.exists
    assert equal $got {kind: $c.kind, value: $c.value} $"share-target ($c.name)"
}

const URI_LIST_CASES = [
    [name text want];
    ["two files, CRLF" "file:///a/b.png\r\nfile:///a/c.pdf\r\n" ["file:///a/b.png" "file:///a/c.pdf"]]
    ["comment and blank line" "# copied\n\nfile:///x\n" ["file:///x"]]
    ["empty" "" []]
]

for c in $URI_LIST_CASES {
    let got = uri-list-parse $c.text
    assert equal $got $c.want $"uri-list-parse ($c.name)"
}

const SOURCE_CASES = [
    [name types want];
    ["dolphin copy" [text/uri-list x-special/gnome-copied-files "text/plain;charset=utf-8"] uri-list]
    ["browser text" ["text/plain;charset=utf-8" UTF8_STRING text/html] text]
    ["xwayland text" [UTF8_STRING STRING TEXT] text]
    ["screenshot" [image/png] none]
    ["empty" [] none]
]

for c in $SOURCE_CASES {
    let got = clipboard-source $c.types
    assert equal $got $c.want $"clipboard-source ($c.name)"
}

const PICK_CASES = [
    [name listing want];
    ["one phone" $"($DEVICE_ID) Galaxy S22\n" {id: $DEVICE_ID, name: "Galaxy S22"}]
    ["none reachable" "" "phone not reachable"]
    ["two reachable" $"($DEVICE_ID) Galaxy S22\nabc Tablet\n" "2 devices reachable: Galaxy S22, Tablet"]
]

for c in $PICK_CASES {
    let got = try { device-pick $c.listing } catch {|e| $e.msg }
    assert equal $got $c.want $"device-pick ($c.name)"
}

# end to end: the argv kdeconnect-cli gets, and that a failure exits non-zero without calling it
const RUN_CASES = [
    [name args types clipboard devices calls exit_code];
    ["file, link and text in one share" [share /etc/hostname "https://example.org" "hi there"] "" {} "D Phone\n"
        ["--device D --share /etc/hostname https://example.org" "--device D --share-text hi there"] 0]
    ["clipboard files" [share] "text/uri-list\n" {text_uri-list: "file:///a/b.png\r\nfile:///a/c.pdf\r\n"} "D Phone\n"
        ["--device D --share file:///a/b.png file:///a/c.pdf"] 0]
    ["clipboard link" [share --notify] "text/plain\n" {text: "https://example.org"} "D Phone\n"
        ["--device D --share https://example.org"] 0]
    ["clipboard word naming a dir" [share] "text/plain\n" {text: "bin"} "D Phone\n" ["--device D --share-text bin"] 0]
    ["clipboard absolute path" [share] "text/plain\n" {text: "/etc/hostname"} "D Phone\n"
        ["--device D --share /etc/hostname"] 0]
    ["clipboard image" [share] "image/png\n" {} "D Phone\n" [] 1]
    ["phone away" [share "hi"] "" {} "" [] 1]
    ["clipboard send" [clipboard] "" {} "D Phone\n" ["--device D --send-clipboard"] 0]
]

let work = mktemp --directory
try {
    mkdir ($work | path join bin)
    $STUBS | items {|name, body|
        let file = $work | path join bin $name
        $"($SHEBANG)\n($body)\n" | save $file
        ^chmod +x $file
    } | ignore
    for c in $RUN_CASES {
        let state = $work | path join state
        rm --recursive --force $state
        mkdir $state
        $c.types | save ($state | path join types)
        $c.devices | save ($state | path join devices)
        $c.clipboard | items {|type, body| $body | save ($state | path join $type) } | ignore
        let out = with-env {PATH: ([($work | path join bin)] ++ $env.PATH), STUB_STATE: $state} {
            cd $work
            ^nu --no-config-file $PHONE ...$c.args | complete
        }
        let calls_file = $state | path join calls
        let calls = if ($calls_file | path exists) { open --raw $calls_file | lines } else { [] }
        assert equal $out.exit_code $c.exit_code $"($c.name): exit, stderr ($out.stderr | str trim)"
        assert equal $calls $c.calls $"($c.name): calls"
    }
} catch {|e|
    rm --recursive --force $work
    error make {msg: $e.msg}
}
rm --recursive --force $work
