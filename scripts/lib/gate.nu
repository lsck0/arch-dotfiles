# The static gates: gate-lint behind dot test lint (repo rules and every *.test.nu/sh), gate-tools behind
# dot test check and fmt (formatters and linters), gate-palette (palette.nu against Palette.js).

use ../../configs/core/wallust/palette.nu
use platform.nu [PLATFORM_FACTS]

const REPO = path self ../..
const SUDO = '\bsudo\b'
const NU_VERB = '(?ms)^export def (?<verb>link|unlink|system|theme|apply|backup|restore|check) \[.*?^\}'
const NU_USER_FACT = '(profile-has|profile-load|\$nu\.home-dir|\$env\.HOME\b|\$env\.USER\b|~/)'
const QUOTED = r#''[^']*'|"(?:[^"\\]|\\.)*"'#
const ROOT_MODULES = [scripts skills]
const SECRETS_DATA = ["secrets/keys/**" "secrets/state/**"]
# the folder root itself (syncthing needs it) and .stignore (per device) are not writes into it
const SYNC_PATH = '(?:\$\{?HOME\}?|~|%h)/sync(?<tail>[^\w].*|$)'
const SYNC_WRITE = '(^|[^\w-])(mkdir|touch|cp|mv|install|tee|rm|ln|unzip|tar|curl|wget)([^\w-]|$)|--mkdir|>'
const DOCS_DIFF_LINES = 40
const FMT_DIR = path self ../../configs/programming/formatting
const FMT_EXCLUDE = "configs/core/wallust/templates/"
# empty on purpose: shfmt reads .editorconfig only when no formatting flag is given
const SHFMT_FLAGS = []
const QMLLINT = "/usr/lib/qt6/bin/qmllint"
const PALETTE_NU = "configs/core/wallust/palette.nu"
const PALETTE_JS = "configs/desktop/quickshell/Commons/Palette.js"
const PALETTE_THEMES = [ayu-dark gruvbox-light]
const PALETTE_TIMEOUT_S = 20

def rel [path: path]: nothing -> string { $path | path relative-to $REPO }

def code-lines [file: path]: nothing -> table<n: int, line: string> {
    open --raw $file | lines | enumerate | where not ($it.item | str trim --left | str starts-with "#") | each {|l| {n: ($l.index + 1), line: $l.item} }
}

def names-read [file: path]: nothing -> list<string> {
    open --raw $file | lines | each { split row "#" | first | str trim } | where $it != "" | each { split row " " | first }
}

def unquote [line: string, keep: closure]: nothing -> string {
    $line | parse --regex $"\(?<q>($QUOTED)\)" | get q | reduce --fold $line {|q, acc| if (do $keep $q) { $acc } else { $acc | str replace $q "''" } }
}

def walk []: nothing -> list<path> {
    ^git -C $REPO ls-files -z --cached --others --exclude-standard | split row (char nul) | where $it != "" and not ($it | str starts-with $FMT_EXCLUDE)
    | each {|f| $REPO | path join $f } | where {|p| ($p | path type) == "file" }
}

def lint-modules []: nothing -> list<string> {
    let configs = $REPO | path join configs
    let groups = ls $configs | where type == dir | get name | path basename
    let deps = $groups | where {|g| $configs | path join $g dependencies.txt | path exists } | reduce --fold {} {|g, acc| $acc | insert $g (names-read ($configs | path join $g dependencies.txt)) }
    let bad_deps = $deps | items {|g, ds| $ds | where $it not-in $groups | each { $"configs/($g)/dependencies.txt: '($in)' is not a module" } } | flatten
    let platforms = glob ($REPO | path join platforms '*.nuon') | where not ($it | str ends-with ".options.nuon") | each {|f|
        open $f | get --optional groups | default [] | where {|g| $g not-in $groups and not ($configs | path join $g mod.nu | path exists) }
        | each { $"(rel $f): groups has '($in)', not a group or module" }
    } | flatten
    let siblings = glob $"($configs)/*/*/**/dependencies.txt" | each {|df|
        let grp = $df | path relative-to $configs | path split | first
        names-read $df | where {|d| not ($configs | path join $grp $d mod.nu | path exists) } | each { $"(rel $df): '($in)' is no module of configs/($grp)" }
    } | flatten
    let order = [[] [--system]] | each {|flags|
        let run = ^nu --no-config-file ($REPO | path join scripts dot.nu) plan --order ...$flags | complete
        if $run.exit_code != 0 { $"run order (dot plan --order ($flags | str join ' ')): ($run.stderr | str trim)" }
    } | compact
    $bad_deps ++ $platforms ++ $siblings ++ $order
}

def lint-layers []: nothing -> list<string> {
    let configs = $REPO | path join configs
    let mods = glob $"($configs)/**/mod.nu" --exclude $SECRETS_DATA
        | append ($ROOT_MODULES | each {|r| $REPO | path join $r mod.nu } | where ($it | path exists))
    let verbs = $mods | each {|f|
        let text = open --raw $f
        $text | parse --regex $"\(?<body>($NU_VERB)\)" | each {|m|
            let line = ($text | split row $m.body | first | lines | length) + 1
            let body = $m.body | lines | where not ($it | str trim --left | str starts-with "#") | str join "\n"
            let fact = $body | parse --regex $NU_USER_FACT | get --optional 0.capture0
            [
                (if $m.verb == "system" and $fact != null { $"(rel $f):($line): '($fact)' in the system verb, a user fact belongs in link" })
                (if $m.verb != "system" and (unquote $body {|q| false }) =~ $SUDO { $"(rel $f):($line): sudo in the ($m.verb) verb, move it to system" })
            ] | compact
        } | flatten
    } | flatten
    let marker = ["is_" "personal"] | str join
    let personal = walk | where {|p| (open --raw $p | into binary | bytes index-of ($marker | into binary)) >= 0 } | each { $"(rel $in): ($marker), use profile-has or a machine fact" }
    $verbs ++ $personal
}

def lint-sync []: nothing -> list<string> {
    let files = glob $"($REPO)/configs/**/*.{sh,nu,py}" --exclude $SECRETS_DATA | append (glob $"($REPO)/scripts/**/*.{sh,nu}")
        | append [($REPO | path join bootstrap.sh)]
    $files | where ($it | path exists) | each {|f|
        code-lines $f | each {|l|
            let code = unquote ($l.line | split row " #" | first) {|q| $q =~ $SYNC_PATH }
            let writes = $code | parse --regex $SYNC_PATH | any {|m| not ($m.tail =~ `^["']?(\s|$)` or ($m.tail | str starts-with "/.stignore")) }
            if $writes and $code =~ $SYNC_WRITE { $"(rel $f):($l.n): writes into ~/sync, which only syncthing may fill" }
        } | compact
    } | flatten
}

const ROOT_FILES = [
    .editorconfig .gitattributes .gitignore .gitleaks.toml .gitmodules .ruff.toml .shellcheckrc AGENTS.md FEATURES.md
    LICENSE.md README.md bootstrap.sh
]
const ROOT_DIRS = [configs migrations mirror platforms profiles scripts showcase skills themes wallpapers]
const GROUP_FILES = [AGENTS.md dependencies.txt]
const SUBMODULE = "configs/secrets"

# dot sync commits with `git add .`: a file some tool dropped in the checkout must stop it, not ride along.
def lint-stray []: nothing -> list<string> {
    let files = ^git -C $REPO ls-files --cached --others --exclude-standard -z | split row (char nul)
        | where {|f| $f != "" and ($REPO | path join $f | path exists) }
    $files | each {|f|
        let parts = $f | split row "/"
        let stray = match ($parts | length) {
            1 => ($f not-in $ROOT_FILES and $f not-in $ROOT_DIRS)
            _ => (($parts.0 not-in $ROOT_DIRS) or ($parts.0 == configs and $f != $SUBMODULE and (($parts | length) == 2 or (($parts | length) == 3 and $parts.2 not-in $GROUP_FILES))))
        }
        if $stray { $"($f): not a file of the repo's layout, a tool's leftover? remove it or add it where it belongs" }
    } | compact
}

def lint-platform-facts []: nothing -> list<string> {
    glob ($REPO | path join platforms '*.nuon') | where not ($it | str ends-with ".options.nuon") | sort | each {|f|
        open $f | get --optional facts | default {} | columns | where $it not-in $PLATFORM_FACTS
        | each { $"(rel $f): fact '($in)' is not in PLATFORM_FACTS; add it there so modules see it, or it is set for nothing" }
    } | flatten
}

def lint-palette []: nothing -> list<string> {
    let band = {|text, pattern| $text | parse --regex $pattern | reduce --fold {} {|m, acc| $acc | insert ($m.k | str uppercase) ($m.v | into float) } }
    let py = do $band (open --raw ($REPO | path join $PALETTE_NU)) 'BG_VALUE_(?<k>MIN|MAX)\s*=\s*(?<v>[0-9.]+)'
    let qml = do $band (open --raw ($REPO | path join configs desktop quickshell Commons Theme.qml)) 'backgroundValue(?<k>Min|Max)\s*:\s*(?<v>[0-9.]+)'
    let json = open ($REPO | path join configs desktop quickshell theme.json) | get --optional palette | default {}
    [MIN MAX] | each {|k|
        let vals = {"palette.nu": ($py | get --optional $k), "Theme.qml": ($qml | get --optional $k), "theme.json": ($json | get --optional $"backgroundValue($k | str capitalize | str replace 'Min' 'Min')")}
        let vals = $vals | update "theme.json" ($json | get --optional (if $k == "MIN" { "backgroundValueMin" } else { "backgroundValueMax" }))
        if ($vals | values | uniq | length) != 1 { $"palette clamp BG_VALUE_($k) drifted: ($vals | items {|n, v| $'($n)=($v)' } | str join ', ')" }
    } | compact
}

const SYSTEM_APPLY = "scripts/lib/system-apply.nu"

# root re-execs each command under flock with the flags it spells out; a flag it leaves out is dropped silently.
def lint-locked-flags []: nothing -> list<string> {
    open --raw ($REPO | path join $SYSTEM_APPLY)
    | parse --regex '(?ms)^def "main (?<cmd>[a-z-]+)" \[(?<sig>[^\]]*)\][^\n]*\n(?<body>.*?)^\}'
    | each {|d|
        let call = $d.body | lines | str trim | where ($it | str starts-with $"locked ($d.cmd)") | get --optional 0
        if $call == null { return [] }
        $d.sig | parse --regex '--(?<flag>[a-z][a-z-]*)' | get flag | where {|f| not ($call =~ $"--($f)\\b") }
        | each {|f| $"($SYSTEM_APPLY): main ($d.cmd) takes --($f), its locked re-exec drops it" }
    } | flatten
}

const NU_PITFALLS = [
    [pattern why];
    ['\bexec \^' "exec takes the bare name, the caret becomes part of it"]
    ["\\$'[^']*\\\\\\(" "\\( is no escape inside $'...'"]
    ['\bnot \((\^|do )[^()]*\)\.[a-z_]+ *(==|!=|<|>)' "not binds before the comparison, compare with != instead"]
    ['^\s*else\b' "else must follow the closing brace on the same line"]
    ['\$"\((into|encode|decode) ' "an interpolation does not pipe $in into its command, pass it explicitly"]
    ["\\$'[^']*\\(\\\\" "a ( inside $'...' starts a subexpression, build the regex with + instead"]
]

def lint-nu-pitfalls []: nothing -> list<string> {
    walk | where ($it | str ends-with ".nu") | each {|f|
        code-lines $f | each {|l| $NU_PITFALLS | where {|p| $l.line =~ $p.pattern } | each {|p| $"(rel $f):($l.n): ($p.why)" } } | flatten
    } | flatten
}

# A script with a shebang is run directly (link-commands, unit Exec=), so it needs its executable bit in git.
def lint-exec-bits []: nothing -> list<string> {
    ^git -C $REPO ls-files -s | lines | parse "{mode} {hash} {stage}\t{path}" | where mode == "100644"
    | where {|f| ($REPO | path join $f.path | path exists) and (open --raw ($REPO | path join $f.path) | into binary | bytes at 0..1) == 0x[2321] }
    | each { $"($in.path): has a shebang but is not executable, chmod +x it" }
}

# A renamed or dropped option breaks only the machines whose options file still sets it, at their next install.
def lint-platform-options []: nothing -> list<string> {
    let script = "use pipeline.nu *; pipeline-load $env.DOT_REPO user | get modules | each {|m| {id: $m.id, keys: ($m.options | columns | append enable)} } | to nuon"
    let known = with-env {DOT_REPO: $REPO} { ^nu --no-config-file -I ($REPO | path join scripts lib) -c $script | from nuon }
    glob ($REPO | path join platforms '*.options.nuon') | sort | each {|f|
        open $f | items {|id, values|
            let module = $known | where id == $id | get --optional 0
            if $module == null { [$"(rel $f): ($id) is no module"] } else {
                $values | columns | where $it not-in $module.keys | each { $"(rel $f): ($id).($in) is no option of it" }
            }
        } | flatten
    } | flatten
}

def lint-generated []: nothing -> list<string> {
    let run = ^nu --no-config-file ($REPO | path join scripts lib internal.nu) gen --check | complete
    if $run.exit_code == 0 { [] } else { [$"dot internal gen --check: ($run.stdout + $run.stderr | str trim)"] }
}

def unit-tests []: nothing -> list<string> {
    glob $"($REPO)/{configs,themes,scripts}/**/*.test.{sh,nu}" --exclude ($SECRETS_DATA | each { $"configs/($in)" }) | sort | each {|t|
        let run = if ($t | str ends-with ".nu") { ^nu --no-config-file -I ($REPO | path join scripts lib) $t | complete } else { ^bash $t | complete }
        if $run.exit_code != 0 { $"(rel $t): failed\n($run.stdout + $run.stderr | str trim --right)" }
    } | compact
}

# Every lint finding, one line each; empty when the repo passes.
export def gate-lint []: nothing -> list<string> {
    [(lint-modules) (lint-layers) (lint-sync) (lint-stray) (lint-platform-facts) (lint-nu-pitfalls) (lint-exec-bits) (lint-platform-options) (lint-palette) (lint-generated) (lint-locked-flags) (unit-tests)] | flatten
}

def pkgbuild [path: path]: nothing -> bool {
    ($path | path basename) == "PKGBUILD" or (($path | str starts-with ($REPO | path join mirror pkgbuilds)) and ($path | str ends-with ".install"))
}

# A PKGBUILD and its .install script are bash too, with neither extension nor shebang.
def shell-script [path: path]: nothing -> bool {
    let ext = $path | path parse | get extension
    $ext == "sh" or (pkgbuild $path) or ($ext == "" and (try { open --raw $path | into binary | first 128 | decode utf-8 } catch { "" }) =~ '^#!.*\b(ba)?sh\b')
}

def nonzero [label: string, run: record, --stdout]: nothing -> list<string> {
    if $run.exit_code == 0 { return [] }
    let out = (if $stdout { $run.stdout } else { $run.stderr }) | str trim | if ($in | is-empty) { $run.stderr | str trim } else { $in }
    [(if ($out | is-empty) { $label } else { $"($label):\n($out)" })]
}

def nu-check [files: list<string>]: nothing -> list<string> {
    $files | par-each {|f|
        let run = do { cd $REPO; ^nu --no-config-file -I ($REPO | path join scripts lib) --ide-check 50 $f } | complete
        let bytes = open --raw ($REPO | path join $f) | into binary
        $run.stdout + $run.stderr | lines | each {|l| try { $l | from json } catch { null } } | compact
        | where {|d| $d.severity? == "Error" }
        | each {|d| $"($f):(($bytes | first $d.span.start | decode utf-8 | lines | length) + (if ($bytes | first $d.span.start | decode utf-8 | str ends-with "\n") { 1 } else { 0 })): ($d.message | lines | first)" }
    } | flatten | sort
}

def qml-lint [files: list<string>]: nothing -> list<string> {
    let root = mktemp --directory
    ^ln -s ($REPO | path join configs desktop quickshell) ($root | path join qs)
    let run = ^$QMLLINT -I $root --json - ...($files | each {|f| $REPO | path join $f }) | complete
    rm --recursive --force $root
    let report = try { $run.stdout | from json } catch { return [$"qmllint: ($run.stderr | str trim | default 'no json report')"] }
    $report.files | each {|f| $f.warnings | where type != info | each {|w| $"(rel $f.filename):($w.line? | default 0):($w.column? | default 0): ($w.message | lines | first) [($w.id? | default $w.type)]" } } | flatten
}

def --wrapped tool [...cmd: string]: nothing -> record {
    do { cd $REPO; ^($cmd | first) ...($cmd | skip 1) } | complete
}

# Runs every installed formatter and linter, applying fixes first when apply; findings fail check, notes
# (a missing optional tool) only warn.
export def gate-tools [apply: bool]: nothing -> record {
    let paths = walk
    let pick = {|exts| $paths | where { ($in | path parse | get extension) in $exts } | each { rel $in } | sort }
    let sh = $paths | where { shell-script $in } | each { rel $in } | sort
    let recipes = $paths | where { pkgbuild $in } | each { rel $in } | sort
    let sets = {shfmt: $sh, shellcheck: ($sh | where $it not-in $recipes), ruff: (do $pick [py]), stylua: (do $pick [lua]), prettier: (do $pick [css scss yaml yml]), taplo: (do $pick [toml]), $QMLLINT: (do $pick [qml]), nu: (do $pick [nu])}
    let present = $sets | items {|t, files| {tool: $t, files: $files, have: (($files | is-not-empty) and (which $t | is-not-empty))} }
    let notes = $present | where {|t| ($t.files | is-not-empty) and not $t.have } | each { $"($in.tool): not installed, ($in.files | length) file\(s\) left untouched" }
    let on = {|t| $present | where tool == $t | get 0 | if $in.have { $in.files } else { [] } }
    let shfmt = do $on shfmt
    if $apply and ($shfmt | is-not-empty) { tool shfmt -w ...$SHFMT_FLAGS ...$shfmt | ignore }
    let shfmt_run = if ($shfmt | is-empty) { null } else { tool shfmt -l ...$SHFMT_FLAGS ...$shfmt }
    let shellcheck = do $on shellcheck
    let ruff = do $on ruff
    let ruff_cfg = [--config ($REPO | path join .ruff.toml)]
    if $apply and ($ruff | is-not-empty) { tool ruff format ...$ruff_cfg ...$ruff | ignore; tool ruff check ...$ruff_cfg --fix ...$ruff | ignore }
    let ruff_checked = if ($ruff | is-empty) { null } else { tool ruff check ...$ruff_cfg --output-format=concise ...$ruff }
    let stylua = do $on stylua
    let stylua_cfg = [--config-path ($FMT_DIR | path join stylua.toml)]
    if $apply and ($stylua | is-not-empty) { tool stylua ...$stylua_cfg ...$stylua | ignore }
    let prettier = do $on prettier
    let prettier_cfg = [--config ($FMT_DIR | path join prettierrc.json)]
    if $apply and ($prettier | is-not-empty) { tool prettier --write ...$prettier_cfg ...$prettier | ignore }
    let taplo = do $on taplo
    if $apply and ($taplo | is-not-empty) { tool taplo fmt ...$taplo | ignore }
    let findings = [
        (if $shfmt_run == null { [] } else {
            ($shfmt_run.stdout | lines | where $it != "" | each { $"shfmt would reformat ($in)" }) ++ (if $shfmt_run.exit_code != 0 and ($shfmt_run.stderr | str trim | is-not-empty) { [$"shfmt: ($shfmt_run.stderr | str trim)"] } else { [] })
        })
        (if ($shellcheck | is-empty) { [] } else { tool shellcheck -f gcc ...$shellcheck | get stdout | lines | where ($it | str trim | is-not-empty) })
        (if ($recipes | is-empty) or (which shellcheck | is-empty) { [] } else {
            tool shellcheck -f gcc -s bash -e SC2034,SC2154,SC2164 ...$recipes | get stdout | lines | where ($it | str trim | is-not-empty)
        })
        ($sh | where {|f| ($f | str starts-with "scripts/") and (^test -x ($REPO | path join $f) | complete).exit_code == 0 }
            | where {|f| let t = open --raw ($REPO | path join $f); not ($t =~ '(?m)^set -euo pipefail\b' or $t =~ '(?m)^# no-errexit: \S') }
            | each { $"($in): executable without 'set -euo pipefail' \(or a '# no-errexit: <reason>' line\)" })
        (if $ruff_checked == null { [] } else {
            let format = nonzero "ruff format --check" (tool ruff format ...$ruff_cfg --check -q ...$ruff) --stdout
            $format ++ (if $ruff_checked.exit_code != 0 { $ruff_checked.stdout | lines | where {|l| ($l | str trim | is-not-empty) and not ($l | str starts-with "Found") } } else { [] })
        })
        (if ($stylua | is-empty) { [] } else { nonzero "stylua --check" (tool stylua ...$stylua_cfg --check ...$stylua) --stdout })
        (if ($prettier | is-empty) { [] } else {
            let r = tool prettier --check ...$prettier_cfg ...$prettier
            $r.stdout + "\n" + $r.stderr | lines | where ($it | str starts-with "[warn]") | each { $"prettier would reformat ($in | split row ' ' | skip 1 | str join ' ')" }
        })
        (if ($taplo | is-empty) { [] } else { nonzero "taplo fmt --check" (tool taplo fmt --check ...$taplo) --stdout })
        (do $on $QMLLINT | if ($in | is-empty) { [] } else { qml-lint $in })
        (do $on nu | if ($in | is-empty) { [] } else { nu-check $in })
    ] | flatten
    {findings: $findings, notes: $notes}
}

def palette-expect [theme: path]: nothing -> list {
    let c = open $theme
    let raw = $c.special.background | palette hex-to-rgb
    let bg = $raw | palette condition-bg
    let fg = $c.special.foreground | palette hex-to-rgb
    let slots = [$c.special.foreground] ++ (0..15 | each {|i| $c.colors | get $"color($i)" })
    [($bg | palette rgb-to-hex) ($raw | palette is-light) ($bg | palette shade 0.045 | palette rgb-to-hex) (palette mix $bg $fg 0.12 | palette rgb-to-hex)] ++ ($slots | each {|s|
        let rgb = $s | palette hex-to-rgb
        let hsv = $rgb | palette rgb-to-hsv
        [
            ($rgb | palette readable-on $bg | palette rgb-to-hex) ($rgb | palette readable-on $bg --ratio 7 | palette rgb-to-hex)
            ($rgb | palette tone-map | palette rgb-to-hex) ($rgb | palette vivify 0.45 0.55 | palette rgb-to-hex)
            (palette hsv-to-rgb $hsv.0 $hsv.1 $hsv.2 | palette rgb-to-hex) (palette contrast $rgb $bg) ($rgb | palette is-light)
        ]
    })
}

const PALETTE_PROBE_QML = 'import QtQuick
import "@JS@" as P
QtObject {
    Component.onCompleted: {
        try {
            var out = @INPUTS@.map(function(c) {
                var raw = P.hexToRgb(c.special.background), bg = P.conditionBg(raw), fg = P.hexToRgb(c.special.foreground);
                var slots = [c.special.foreground];
                for (var i = 0; i < 16; i++) slots.push(c.colors["color" + i]);
                return [P.rgbToHex(bg), P.isLight(raw), P.rgbToHex(P.shade(bg, 0.045)), P.rgbToHex(P.mix(bg, fg, 0.12))]
                    .concat(slots.map(function(s) {
                        var rgb = P.hexToRgb(s), hsv = P.rgbToHsv(rgb);
                        return [P.rgbToHex(P.readableOn(bg, rgb)), P.rgbToHex(P.readableOn(bg, rgb, 7)),
                            P.rgbToHex(P.toneMap(rgb)), P.rgbToHex(P.vivify(rgb, 0.45, 0.55)),
                            P.rgbToHex(P.hsvToRgb(hsv[0], hsv[1], hsv[2])), P.contrast(rgb, bg), P.isLight(rgb)];
                    }));
            });
            console.warn("probe " + JSON.stringify(out));
        } catch (e) {
            console.warn("probe-error " + e);
        }
        Qt.quit();
    }
}
'

# Compares palette.nu with Palette.js run in qml6, the engine quickshell uses, so rounding differences show.
export def gate-palette []: nothing -> record {
    let themes = $PALETTE_THEMES | each {|t| $REPO | path join themes $"($t).json" }
    let py = {synced: (palette palette-js-sync), light: $palette.LIGHT_LUMINANCE, expected: ($themes | each { palette-expect $in })}
    let sync = if $py.synced { [] } else { [$"($PALETTE_JS): constants block is stale, run ($PALETTE_NU) js --write"] }
    let qml_light = open --raw ($REPO | path join configs desktop quickshell Commons Theme.qml) | parse --regex 'lightLuminance\s*:\s*(?<v>[0-9.]+)' | get --optional 0.v | if $in == null { null } else { into float }
    let json_light = open ($REPO | path join configs desktop quickshell theme.json) | get --optional palette.lightLuminance
    let light = [["Theme.qml" $qml_light] ["theme.json" $json_light]] | where {|w| $w.1 != $py.light } | each {|w| $"palette: ($w.0) lightLuminance=($w.1), palette.nu LIGHT_LUMINANCE=($py.light)" }
    let qml = which qml6 | get --optional 0.path | default "/usr/lib/qt6/bin/qml"
    if not ($qml | path exists) { return {findings: ($sync ++ $light), notes: ["qml6: not installed, palette.nu against Palette.js not compared"]} }
    let dir = mktemp --directory
    let probe = $dir | path join probe.qml
    $PALETTE_PROBE_QML | str replace "@JS@" $"file://($REPO | path join $PALETTE_JS)" | str replace "@INPUTS@" ($themes | each { open $in } | to json --raw) | save $probe
    let run = with-env {QT_QPA_PLATFORM: offscreen, QT_FORCE_STDERR_LOGGING: "1"} { ^timeout $PALETTE_TIMEOUT_S $qml $probe | complete }
    rm --recursive --force $dir
    let line = $run.stderr | lines | where ($it | str contains "qml: probe ") | get --optional 0
    if $line == null { return {findings: ($sync ++ $light ++ [$"palette: Palette.js probe failed:\n($run.stderr | str trim)"]), notes: []} }
    let got = $line | split row "qml: probe " | last | from json
    let diffs = $PALETTE_THEMES | enumerate | each {|t|
        let want = $py.expected | get $t.index
        let have = $got | get $t.index
        if $want == $have { return null }
        let at = $want | zip $have | enumerate | where {|p| $p.item.0 != $p.item.1 } | get --optional 0
        let detail = if $at == null { $"length: palette.nu ($want | length) != Palette.js ($have | length)" } else { $"($at.index): palette.nu ($at.item.0 | to json --raw) != Palette.js ($at.item.1 | to json --raw)" }
        $"palette: palette.nu and Palette.js differ on ($t.item), first at probe entry ($detail)"
    } | compact
    {findings: ($sync ++ $light ++ $diffs), notes: []}
}
