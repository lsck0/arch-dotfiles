#!/usr/bin/env -S nu --no-config-file
# Schema.js under qmltestrunner, and each `dot set` argument it builds read back through nu's argument coercion and
# READER's copy of the value parse in scripts/lib/dot-cli.nu's `main set`; a change to that parse is mirrored here by hand

const SCHEMA = path self Schema.js
const RUNNER = "/usr/lib/qt6/bin/qmltestrunner"
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
    [list "list<int>" [9003 9004] "[9003, 9004]"]
    [json record {"1": "DP-2"} '{"1": "DP-2"}']
    [filesize filesize 2147483648 "2147483648b"]
    [filesize "filesize?" null "null"]
    [multi "list<string>" ["base" "programming/docker"] '["base", "programming/docker"]']
]
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

  // an entry typed into a list<int> lands as a number, so dot set reads the list back as list<int>
  function test_list_entry\() {
    var ints = { type: \"list\", nuType: \"list<int>\" }
    compare\(Schema.listEntry\(ints, \" 9004 \"\), 9004\)
    compare\(Schema.listEntry\(ints, \"9.5\"\), undefined\)
    compare\(Schema.listEntry\(ints, \"x\"\), undefined\)
    compare\(Schema.listEntry\({ type: \"list\", nuType: \"list<float>?\" }, \"0.5\"\), 0.5\)
    compare\(Schema.listEntry\({ type: \"list\", nuType: \"list<string>\" }, \" a b \"\), \"a b\"\)
    compare\(Schema.listEntry\({ type: \"list\", nuType: \"list<path>\" }, \" \"\), undefined\)
  }

  function test_system\() {
    var status = { generation: \"Generation: 7\", checks: [{ level: \"FAIL\", check: \"failures\", text: \"x\" }],
      migrations_pending: [\"0001-a\"], system_pending: [], pending_apply: [],
      drift: [{ module: \"core/btop\", target: \"/h/.config/btop/btop.conf\", drift: \"changed\" }] }
    var rows = Schema.systemEntries\(status, \"\"\)
    var kinds = rows.map\(function \(r\) { return r.kind }\).join\(\",\"\)
    compare\(kinds, \"header,action,action,action,action,header,drift,header,check,check,check\"\)
    compare\(rows[10].level, \"FAIL\"\)
    var drift = rows[6]
    var adopt = Schema.systemCommand\(\"dot\", drift, \"adopt\"\)
    compare\(adopt.slice\(0, 2\).join\(\" \"\), \"sh -c\"\)
    compare\(adopt.slice\(3\).join\(\" \"\), \"dot /h/.config/btop/btop.conf core/btop\"\)
    compare\(Schema.systemCommand\(\"dot\", drift, \"reset\"\).join\(\" \"\), \"dot module reset /h/.config/btop/btop.conf\"\)
    compare\(Schema.systemCommand\(\"dot\", rows[1], \"\"\).join\(\" \"\), \"dot sync\"\)
    compare\(Schema.systemEntries\(status, \"btop\"\).filter\(function \(r\) { return r.kind === \"drift\" }\).length, 1\)
    compare\(Schema.systemEntries\(null, \"\"\)[0].kind, \"header\"\)
    var term = Schema.terminalCommand\([\"dot\", \"it's\"], \"dot sync\"\)
    compare\(term.slice\(0, 5\).join\(\" \"\), \"app2unit -T -- bash -c\"\)
    console.log\(\"TERM \" + term[5]\)
  }

  function test_sections\() {
    var modules = [{ name: \"base/a\", options: [{ key: \"x\" }] }, { name: \"core/b\", options: [] }]
    var ids = function \(list\) { return list.map\(function \(s\) { return s.id }\).join\(\",\"\) }
    compare\(ids\(Schema.sections\(modules, [], \"\", null\)\), \":toggles,#base,base/a\"\)
    compare\(ids\(Schema.sections\(modules, [], \"zzz\", { checks: [] }\)\), \":toggles,:system,#base,base/a\"\)
    compare\(ids\(Schema.sections\(modules, [], \"\", null, machine\(\)\)\), \"platform,:toggles,#base,base/a\"\)
    compare\(Schema.sections\(modules, [], \"homelab\", null, machine\(\)\)[0].count, 1\)
    var loose = modules.concat\([{ name: \"scripts\", options: [{ key: \"y\" }] }]\)
    compare\(ids\(Schema.sections\(loose, [], \"\", null\)\), \":toggles,scripts,#base,base/a\"\)
  }

  // dot set --json's platform section: the top keys without a header, then the facts under theirs
  function machine\() {
    return Schema.moduleNormalize\({ name: \"platform\", label: \"luca-pc\", options: [
      { key: \"hostname\", type: \"string\", fixed: true, source: \"platform\", scope: \"machine\", group: \"\", value: \"pc\" },
      { key: \"groups\", type: \"list<string>\", nonempty: true, choices: [\"base\", \"core\"], source: \"platform\", scope: \"machine\", group: \"\" },
      { key: \"facts.homelab\", type: \"bool\", source: \"default\", scope: \"machine\", group: \"facts\", apply: \"apply\" }
    ] }\)
  }

  function test_machine\() {
    var m = machine\(\)
    var rows = Schema.rows\([], [], \"platform\", \"\", null, m\)
    compare\(rows.map\(function \(r\) { return r.id }\).join\(\",\"\), \"platform.hostname,platform.groups,#platform/facts,platform.facts.homelab\"\)
    compare\(rows[0].option.type, \"fixed\"\)
    verify\(!Schema.resettable\(rows[0].option\)\)
    compare\(rows[1].option.type, \"multi\"\)
    verify\(Schema.resettable\(rows[1].option\)\)
    compare\(Schema.choicePicked\(rows[1].option, [\"core\"], \"base\"\).join\(\",\"\), \"base,core\"\)
    var opt = Object.assign\({}, rows[1].option, { value: [\"core\", \"base\"] }\)
    var off = Schema.choicePicked\(opt, opt.value, \"core\"\)
    compare\(Schema.choicePicked\(opt, off, \"core\"\).join\(\",\"\), \"core,base\"\)
    compare\(Schema.choicePicked\(rows[1].option, [\"core\", \"base\"], \"core\"\).join\(\",\"\), \"base\"\)
    compare\(Schema.choicePicked\(rows[1].option, [\"base\"], \"base\"\).join\(\",\"\), \"base\"\)
    compare\(Schema.choicePicked\({ type: \"multi\" }, [\"a\"], \"a\"\).length, 0\)
    compare\(Schema.choicePicked\({ type: \"enum\" }, \"a\", \"b\"\), \"b\"\)
    compare\(Schema.adjusted\(rows[1].option, [\"core\"], 1\), undefined\)
    var hits = Schema.rows\([], [], \"\", \"homelab\", null, m\)
    compare\(hits[0].text, \"MACHINE\"\)
    compare\(hits[1].id, \"platform.facts.homelab\"\)
    compare\(Schema.strongestApply\([{ apply: \"packages\" }, { apply: \"apply\" }]\), \"apply\"\)
  }

  // status.nu's records as rows: an unavailable one hidden, a broken one kept, showing [error]; a switch only an
  // off/on record, rows by label, an options toggle under its own header
  function test_toggles\() {
    var t = function \(name, label, state, states, available\) {
      return { name: name, label: label, state: state, text: state, states: states, on: false, available: available }
    }
    var toggles = [
      t\(\"wifi\", \"Wi-Fi\", \"on\", [\"off\", \"on\"], true\), t\(\"mobile\", \"Mobile\", \"off\", [\"off\", \"on\"], false\),
      t\(\"route\", \"route\", \"error\", [], true\), t\(\"powermode\", \"Power mode\", \"auto\", [\"auto\", \"balanced\"], true\),
      Object.assign\(t\(\"font\", \"Font\", \"x\", [], true\), { options: [{ key: \"family\", type: \"string\" }] }\)
    ]
    var rows = Schema.toggleEntries\(toggles, \"\"\)
    compare\(rows.map\(function \(r\) { return r.id }\).join\(\",\"\), \":toggles.powermode,:toggles.route,:toggles.wifi,#:toggles/font,:toggles.font.family\"\)
    verify\(Schema.toggleIsSwitch\(toggles[0]\)\)
    verify\(!Schema.toggleIsSwitch\(toggles[2]\)\)
    verify\(!Schema.toggleIsSwitch\(toggles[3]\)\)
    compare\(rows[4].option.toggle, \"font\"\)
    compare\(Schema.toggleEntries\(toggles, \"wi-fi\"\).length, 1\)
    compare\(Schema.toggleEntries\(toggles, \"mobile\"\).length, 0\)
    compare\(Schema.toggleEntries\([], \"\"\).length, 0\)
    // a radio whose probe failed \(NetworkManager down\): shown as [error], never as a switch that is off
    var broken = Schema.toggleEntries\([t\(\"wifi\", \"Wi-Fi\", \"error\", [], true\)], \"\"\)
    compare\(broken.length, 1\)
    verify\(!Schema.toggleIsSwitch\(broken[0].toggle\)\)
  }

  function test_type\() {
    compare\(Schema.typeOf\({ type: \"filesize?\" }\), \"filesize\"\)
    compare\(Schema.typeOf\({ type: \"list<record>?\" }\), \"json\"\)
    compare\(Schema.typeOf\({ type: \"string?\", choices: [\"a\"] }\), \"enum\"\)
    compare\(Schema.typeOf\({ type: \"list<string>\", choices: [\"a\"] }\), \"multi\"\)
    compare\(Schema.typeOf\({ type: \"list<string>\", choices: [\"a\"], ordered: true }\), \"sequence\"\)
    var named = { type: \"multi\", choices: [\"x@y\", \"z\"], choice_labels: { \"x@y\": \"Named\" } }
    compare\(Schema.choiceLabel\(named, \"x@y\"\), \"Named\"\)
    compare\(Schema.choiceLabel\(named, \"z\"\), \"z\"\)
    compare\(Schema.choiceLabel\({}, \"\"\), \"\(none\)\"\)
    compare\(Schema.choicesMatching\(named, \"name\"\).join\(\",\"\), \"x@y\"\)
    compare\(Schema.choicesMatching\(named, \"@y\"\).join\(\",\"\), \"x@y\"\)
    // fuzzy: letters in order across a name, the tighter and the substring first; prose only as a substring
    var bar = { choices: [\"Workspaces\", \"Separator\", \"KeyboardLayout\", \"Network\"] }
    compare\(Schema.choicesMatching\(bar, \"kbl\"\).join\(\",\"\), \"KeyboardLayout\"\)
    compare\(Schema.choicesMatching\(bar, \"work\"\).join\(\",\"\), \"Workspaces,Network\"\)
    compare\(Schema.choicesMatching\(bar, \"zz\"\).length, 0\)
    verify\(Schema.optionMatches\(\"brrgt\", { name: \"m\" }, { key: \"bar_right\", doc: \"x\" }\)\)
    verify\(!Schema.optionMatches\(\"wdgt\", { name: \"m\" }, { key: \"k\", doc: \"Widgets\" }\)\)
    verify\(Schema.optionMatches\(\"widg left\", { name: \"m\" }, { key: \"left\", doc: \"Widgets\" }\)\)
    // scattered letters stay inside one word from its start: \"light\" is no hit in playwright, \"effort\" none across words
    verify\(!Schema.optionMatches\(\"light\", { name: \"programming/playwright\" }, { key: \"headless\", label: \"Headless browsers\" }\)\)
    verify\(!Schema.optionMatches\(\"effort\", { name: \"m\" }, { key: \"k\", label: \"Screens off in power saver after\" }\)\)
    // the module with the best hit leads: an exact label before a prefix in a module listed earlier
    var ranked = Schema.rows\([Schema.moduleNormalize\({ name: \"a/x\", options: [{ key: \"k\", type: \"bool\", label: \"Effortless\" }] }\),
      Schema.moduleNormalize\({ name: \"b/y\", options: [{ key: \"effort\", type: \"string\", label: \"Effort\" }] }\)], [], \"\", \"effort\", null\)
    compare\(ranked.map\(function \(r\) { return r.id }\).join\(\",\"\), \"#b/y,b/y.effort,#a/x,a/x.k\"\)
    compare\(Schema.choicePicked\({ type: \"sequence\" }, [\"a\", \"b\"], \"a\"\).join\(\",\"\), \"a,b,a\"\)
    compare\(Schema.typeOf\({ type: \"string\", fixed: true }\), \"fixed\"\)
  }

  function ids\(list\) { return list.map\(function \(r\) { return r.id }\).join\(\",\"\) }

  function mod\(name, options\) {
    return Schema.moduleNormalize\({ name: name, options: options.map\(function \(o\) { return Object.assign\({ type: \"bool\" }, o\) }\) }\)
  }

  // scattered letters: too wide a spread is no hit, and any word or substring hit anywhere drops them all
  function test_fuzzy\() {
    verify\(!Schema.optionMatches\(\"dpi\", { name: \"m\" }, { key: \"desktop_quotes_file\" }\)\)
    var modules = [mod\(\"a/q\", [{ key: \"quotes_file\", label: \"Quotes file\" }, { key: \"bar_right\", label: \"Right\" }]\),
      mod\(\"b/w\", [{ key: \"dpi\", label: \"Wine dpi\" }]\)]
    compare\(ids\(Schema.rows\(modules, [], \"\", \"dpi\", null\)\), \"#b/w,b/w.dpi\"\)
    compare\(ids\(Schema.rows\(modules, [], \"\", \"brrgt\", null\)\), \"#a/q,a/q.bar_right\"\)
    var counts = Schema.sections\(modules.concat\([mod\(\"c/d\", [{ key: \"dp_ix\" }]\)]\), [], \"dpi\", null\)
      .filter\(function \(s\) { return s.kind === \"section\" && s.count > 0 }\)
    compare\(ids\(counts\), \"b/w\"\)
  }

  // labels lead docs and module names; enum values and a multi-state toggle's states match, a switch's off/on do not
  function test_search_fields\() {
    var modules = [mod\(\"a/x\", [{ key: \"k\", label: \"Gateways\", doc: \"routers and printers\" }]\),
      mod\(\"b/y\", [{ key: \"p\", label: \"Printers\" }]\),
      mod\(\"c/printing\", [{ key: \"page_size\", label: \"Paper size\", type: \"string\" }]\),
      mod\(\"d/z\", [{ key: \"look\", label: \"Look\", type: \"string\", choices: [\"dark\", \"light\"] }]\)]
    compare\(ids\(Schema.rows\(modules, [], \"\", \"printers\", null\)\), \"#b/y,b/y.p,#a/x,a/x.k\"\)
    compare\(ids\(Schema.rows\(modules, [], \"\", \"printing\", null\)\), \"#c/printing,c/printing.page_size\"\)
    compare\(ids\(Schema.rows\(modules, [], \"\", \"light\", null\)\), \"#d/z,d/z.look\"\)
    var theme = { name: \"theme-mode\", label: \"Theme\", state: \"dark\", text: \"dark\", states: [\"dark\", \"light\"], available: true }
    var wifi = { name: \"wifi\", label: \"Wi-Fi\", state: \"on\", text: \"on\", states: [\"off\", \"on\"], available: true }
    compare\(ids\(Schema.toggleEntries\([theme, wifi], \"dark mode\"\)\), \":toggles.theme-mode\"\)
    compare\(ids\(Schema.toggleEntries\([theme, wifi], \"light\"\)\), \":toggles.theme-mode\"\)
    compare\(Schema.toggleEntries\([theme, wifi], \"off\"\).length, 0\)
  }

  // a newcomer's word for what the options name otherwise
  function test_synonyms\() {
    var modules = [mod\(\"desktop/hyprland\", [{ key: \"idle_dpms_s\", label: \"Screens off after\", group: \"idle\", type: \"int\" },
      { key: \"autostart\", label: \"Autostart\", type: \"list<string>\" }]\),
      mod\(\"core/locale\", [{ key: \"keyboard_options\", label: \"Keyboard options\", doc: \"xkb options, e.g. ctrl:nocaps\", type: \"string\" }]\),
      mod\(\"desktop/printing\", [{ key: \"page_size\", label: \"Paper size\", type: \"string\" }]\)]
    compare\(ids\(Schema.rows\(modules, [], \"\", \"screen timeout\", null\)\), \"#desktop/hyprland,desktop/hyprland.idle_dpms_s\"\)
    compare\(ids\(Schema.rows\(modules, [], \"\", \"startup\", null\)\), \"#desktop/hyprland,desktop/hyprland.autostart\"\)
    compare\(ids\(Schema.rows\(modules, [], \"\", \"caps lock\", null\)\), \"#core/locale,core/locale.keyboard_options\"\)
    compare\(ids\(Schema.rows\(modules, [], \"\", \"printer\", null\)\), \"#desktop/printing,desktop/printing.page_size\"\)
  }

  // the keybind list, wallpaper and theme pickers sit under quick toggles, found by the words a newcomer tries
  function test_launchers\() {
    compare\(ids\(Schema.rows\([], [], \":toggles\", \"\", null\)\), \"#:toggles/open,:toggles.open.keybinds,:toggles.open.wallpaper,:toggles.open.theme\"\)
    compare\(Schema.sections\([], [], \"\", null\)[0].count, 3\)
    var first = function \(q\) { return Schema.rows\([], [], \"\", q, null\).filter\(function \(r\) { return r.kind === \"launch\" }\).map\(function \(r\) { return r.name }\).join\(\",\"\) }
    compare\(first\(\"keybinds\"\), \"keybinds\"\)
    compare\(first\(\"shortcut\"\), \"keybinds\"\)
    compare\(first\(\"hotkeys\"\), \"keybinds\"\)
    compare\(first\(\"keybindings\"\), \"keybinds\"\)
    compare\(first\(\"help\"\), \"keybinds\"\)
    compare\(first\(\"wallpapers\"\), \"wallpaper\"\)
    compare\(first\(\"themes\"\), \"theme\"\)
    compare\(first\(\"background\"\), \"wallpaper\"\)
    compare\(first\(\"colors\"\), \"theme\"\)
    compare\(first\(\"palette\"\), \"theme\"\)
    var keys = Schema.rows\([], [], \":toggles\", \"\", null\)[1]
    compare\(keys.ipc.join\(\"|\"\), \"appsearch|openWith|? \"\)
    compare\(Schema.rows\([], [], \":toggles\", \"\", null\)[3].bin.join\(\" \"\), \"wallpaper-picker --themes\"\)
  }

  // a label several hits share shows its module's name; a label of its own stays as it is
  function test_titles\() {
    var modules = [mod\(\"pentesting/proxychains\", [{ key: \"enable\", label: \"Enabled\" }]\),
      mod\(\"pentesting/zaproxy\", [{ key: \"enable\", label: \"Enabled\" }, { key: \"port\", label: \"Proxy port\", type: \"int\" }]\)]
    var hits = Schema.rows\(modules, [], \"\", \"proxy\", null\).filter\(function \(r\) { return r.kind === \"option\" }\)
    compare\(hits.map\(function \(r\) { return r.title || \"-\" }\).join\(\",\"\), \"-,zaproxy Enabled,proxychains Enabled\"\)
    compare\(Schema.rows\(modules, [], \"pentesting/zaproxy\", \"\", null\)[0].title, undefined\)
  }
}
" | save ($dir | path join tst_schema.qml)
    let run = with-env {QT_QPA_PLATFORM: offscreen} { ^$RUNNER -input ($dir | path join tst_schema.qml) } | complete
    if $run.exit_code != 0 { error make {msg: $"qmltestrunner failed\n($run.stdout)($run.stderr)"} }
    $run.stdout + $run.stderr
}

def main [] {
    let dir = mktemp --directory
    let err = try {
        let output = qml-test $dir
        let term = $output | lines | parse --regex 'qml: TERM (?<script>.*)$' | get 0.script
        let echoed = ^bash -c ($term | str replace "; echo; read" "; exit 0; read" | str replace "'dot'" "'echo'") | str trim
        if $echoed != "it's" { error make {msg: $"terminal command quotes wrong: ($term) ran as ($echoed)"} }
        let args = $output | lines | parse --regex 'qml: ARG (?<arg>.*)$' | get arg | each { from json }
        $READER | save ($dir | path join reader.nu)
        let failed = $CASES | zip $args | each {|pair|
            let got = ^nu --no-config-file ($dir | path join reader.nu) set -- x.y $pair.1 | str trim
            let want = $pair.0.want | from nuon | to nuon
            if $got != $want { $"($pair.0.type) ($pair.0.value | to nuon): argument ($pair.1) stored as ($got), want ($want)" }
        } | compact
        if ($args | length) != ($CASES | length) { error make {msg: $"($args | length) arguments for ($CASES | length) cases"} }
        if ($failed | is-not-empty) { error make {msg: ($failed | str join "\n")} }
        null
    } catch {|e| $e.msg }
    rm --recursive --force $dir
    if $err != null { error make {msg: $err} }
}
