#!/usr/bin/env -S nu --no-config-file
# Schema.js under qmltestrunner, and each `dot set` argument it builds read back the way dot.nu reads it

const SCHEMA = path self | path dirname | path join Schema.js
const RUNNER = "/usr/lib/qt6/bin/qmltestrunner"
# a typed option value and the nuon `dot set` must end up storing
const CASES = [
    [type nu value want];
    [string string "de" '"de"']
    [string string "ctrl:nocaps,terminate:ctrl_alt_bksp" '"ctrl:nocaps,terminate:ctrl_alt_bksp"']
    [path string "/dev/dri/by-path/pci-0000:03:00.0-render" '"/dev/dri/by-path/pci-0000:03:00.0-render"']
    [string string "" '""']
    [string string "true" '"true"']
    [string string "1.0" '"1.0"']
    [string string "null" '"null"']
    [string string null "null"]
    [float float -0.5 "-0.5"]
    [int int -5 "-5"]
    [int int 95 "95"]
    [bool bool false "false"]
    [list "list<string>" ["10.100.0.*" "a b"] '["10.100.0.*", "a b"]']
    [json record {"1": "DP-2"} '{"1": "DP-2"}']
    [filesize filesize 2147483648 "2147483648b"]
]
# dot.nu's `main set` signature and parse, so the arguments meet the same reader
const READER = '
def main [] {}
def "main set" [target?: string, ...value: any, --default, --machine, --json, --no-system] {
    let value = $value | get --optional 0
    let parsed = if ($value | describe) != "string" { $value } else { try { $value | from nuon } catch { try { $value | from json } catch { $value } } }
    print ($parsed | to nuon)
}'

def qml-test [dir: path]: nothing -> string {
    let cases = $CASES | select type value | to json --raw
    $"import QtQuick
import QtTest
import \"file://($SCHEMA)\" as Schema

TestCase {
  name: \"schema\"
  readonly property var cases: ($cases)

  function test_encode\() {
    for \(let i = 0; i < cases.length; i++\) console.log\(\"ARG \" + JSON.stringify\(Schema.encode\({ type: cases[i].type }, cases[i].value\)\)\)
  }

  function test_filesize\() {
    var o = { type: \"filesize\" }
    compare\(Schema.toText\(o, 2147483648\), \"2GiB\"\)
    compare\(Schema.toText\(o, 1000\), \"1000B\"\)
    compare\(Schema.fromText\(o, \"2GiB\"\), 2147483648\)
    compare\(Schema.fromText\(o, \"1.5 gb\"\), 1500000000\)
    compare\(Schema.fromText\(o, \"512\"\), 512\)
    compare\(Schema.fromText\(o, \"lots\"\), undefined\)
  }

  function test_sliderable\() {
    verify\(Schema.sliderable\({ type: \"int\", min: 0, max: 100 }\)\)
    verify\(Schema.sliderable\({ type: \"float\", min: -1, max: 1 }\)\)
    verify\(!Schema.sliderable\({ type: \"int\", min: 60 }\)\)
    verify\(!Schema.sliderable\({ type: \"string\", min: 0, max: 1 }\)\)
  }

  function test_nullable\() {
    compare\(Schema.fromText\({ type: \"string\", nuType: \"string?\" }, \"\"\), null\)
    compare\(Schema.fromText\({ type: \"string\", nuType: \"string\" }, \"\"\), \"\"\)
    compare\(Schema.fromText\({ type: \"int\", nuType: \"int?\" }, \" \"\), null\)
    compare\(Schema.fromText\({ type: \"string\", nuType: \"string?\" }, \"de\"\), \"de\"\)
  }

  function test_type\() {
    compare\(Schema.typeOf\({ type: \"filesize?\" }\), \"filesize\"\)
    compare\(Schema.typeOf\({ type: \"list<record>?\" }\), \"json\"\)
    compare\(Schema.typeOf\({ type: \"string?\", choices: [\"a\"] }\), \"enum\"\)
  }
}
" | save ($dir | path join tst_schema.qml)
    let run = with-env {QT_QPA_PLATFORM: offscreen} { ^$RUNNER -input ($dir | path join tst_schema.qml) } | complete
    if $run.exit_code != 0 { error make {msg: $"qmltestrunner failed\n($run.stdout)($run.stderr)"} }
    $run.stdout + $run.stderr
}

def main [] {
    let dir = mktemp --directory
    let output = qml-test $dir
    let args = $output | lines | parse --regex 'qml: ARG (?<arg>.*)$' | get arg | each { from json }
    $READER | save ($dir | path join reader.nu)
    let failed = $CASES | zip $args | each {|pair|
        let got = ^nu --no-config-file ($dir | path join reader.nu) set -- x.y $pair.1 | str trim
        let want = $pair.0.want | from nuon | to nuon
        if $got != $want { $"($pair.0.type) ($pair.0.value | to nuon): argument ($pair.1) stored as ($got), want ($want)" }
    } | compact
    rm --recursive --force $dir
    if ($args | length) != ($CASES | length) { error make {msg: $"($args | length) arguments for ($CASES | length) cases"} }
    if ($failed | is-not-empty) { error make {msg: ($failed | str join "\n")} }
}
