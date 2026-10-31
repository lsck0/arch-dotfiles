#!/usr/bin/env -S nu --no-config-file
# Table cases for the commands lint: what counts as a call, and which calls a module's packages, its deps' or the
# pacstrap set cover.
use commands.nu [commands-from-nu commands-from-sh commands-from-py commands-from-unit wrapper-chain command-db-path command-owners-parse command-row pactree-names commands-undeclared commands-fail-closed commands-allow-check module-packages-every packages-every-context FAIL_CLOSED]

const REPO = path self ../..

def fail [msg: string] { error make {msg: $"commands.test: ($msg)"} }

# The calls in nushell code, read from a file of it, as the scan reads a module's files; head prepends the module API.
def nu-calls [code: string, --api]: nothing -> table {
    let dir = mktemp --directory --tmpdir dot-commands-test-XXXXXX
    let file = $dir | path join case.nu
    (if $api { $"use module.nu *\n($code)" } else { $code }) | save $file
    let calls = commands-from-nu $file
    rm --recursive --force $dir
    $calls
}

def module-fake [id: string, code: string, --deps: list<string> = [], --packages: list<string> = []]: nothing -> record {
    {id: $id, deps: $deps, packages: $packages, files: [{file: $"configs/($id)/mod.nu", text: $code, calls: (nu-calls $code)}]}
}

def extraction-check [] {
    let cases = [
        [name text wants];
        ["caret" "    ^ethtool -s eth0" [ethtool]]
        ["caret in a pipeline" "let x = (^lsusb -d 1050: | complete)" [lsusb]]
        ["caret inside a string" "let re = '^export def'" []]
        ["comment" "# ^ethtool is not run here" []]
        ["run-external" "run-external \"wg\" show" [wg]]
        ["nu's exec" "exec hyprland --config $cfg" [hyprland]]
        ["const path" "const WGQ = \"/usr/bin/wg-quick\"\n^$WGQ up wg0" ["/usr/bin/wg-quick"]]
        ["repo command" "^/usr/local/bin/tor-router start" []]
        ["dynamic" "^$cmd --flag" []]
        ["bare external" "let v = (pactl get-sink-volume @DEFAULT_SINK@)" [pactl]]
        ["builtin and own def" "def probe [] { ls | length }
probe
str join" []]
        ["record key and closure param" "let r = {pactl: 1}
[1] | each {|brightnessctl| $brightnessctl }" []]
        ["local wrapper" "def --wrapped out [...argv: string] { do { run-external ...$argv } | complete }
out ip -j route" [ip]]
        ["wrapper with args first" "def --wrapped quiet [...args: string] { ^sbctl ...$args }
quiet sign x" [sbctl]]
        ["timeout" "^timeout 2 quickshell ipc call" [timeout quickshell]]
        ["sudo" "^sudo -n -u luca systemctl restart x" [sudo systemctl]]
        ["systemd-run" "^systemd-run --user --unit x -p CPUWeight=20 --quiet nice -n 19 make" [systemd-run nice]]
        ["env" "^env -u DO_NOT_TRACK FOO=1 claude" [env claude]]
        ["flock" "^flock -n -E 0 /run/lock brightnessctl set 1%" [flock brightnessctl]]
        ["flock -c" "^flock /run/lock -c 'ddcutil setvcp 10 5'" [flock]]
        ["setsid and pkexec" "^setsid -f pkexec --user root dmesg" [setsid pkexec dmesg]]
        ["computed target" "^sudo -n $cmd" [sudo]]
        ["after --" "^systemd-run --user -- lsblk" [systemd-run lsblk]]
    ]
    let api = [
        [name text wants];
        ["then list" "(file-copy a /etc/a --then [systemctl try-restart a.service])" [systemctl]]
        ["exec declaration" "(exec probe [lsusb -d 1050:] --creates /tmp/x)" [lsusb]]
        ["quoted exec name" "exec \"desktop database\" [update-desktop-database $dir]" [update-desktop-database]]
        ["interpolated exec name" "exec $\"install \\($id\\)\" [kpackagetool6 -t Plasma/Applet]" [kpackagetool6]]
        ["exec argv in parens" "exec keymap ([localectl set-x11-keymap $layout] ++ $rest)" [localectl]]
        ["exec argv over lines" "exec reload [\n    ghostty +reload\n]" [ghostty]]
        ["exec argv const" "const ELAN = \"/usr/bin/elan\"\nexec elan-default [$ELAN default nightly]" ["/usr/bin/elan"]]
        ["exec argv env" "exec prefix [env WINEPREFIX=/p ($wine | path join wineboot) --init]" [env]]
        ["exec argv computed" "exec prefix [...$vars wineboot]" []]
    ]
    let all = ($cases | insert api false) ++ ($api | insert api true)
    let failed = $all | par-each {|c|
        let got = (if $c.api { nu-calls $c.text --api } else { nu-calls $c.text }) | get --optional cmd | default []
        if $got != $c.wants { $"($c.name): got ($got | to nuon), wants ($c.wants | to nuon)" }
    } | compact
    if ($failed | is-not-empty) { fail ($failed | str join "; ") }
    let sh = "#!/bin/bash\nf() { :; }\ncd /x || exit 1\nrefresh=$(command -v hyprctl > /dev/null && hyprctl -j monitors | jq -r .)\nf\nexec gamescope -w 1 -- sh -c 'wine x'\n\"$var\" arg\n"
    let got = commands-from-sh $sh | get cmd
    if $got != [bash hyprctl jq gamescope] { fail $"sh: got ($got | to nuon)" }
    let zsh = "(( $+commands[z] )) && alias cd=\"z\"\nalias ldocker='sudo lazydocker' ls=eza\nalias t=\"$DOTFILES/t.nu\"\nf() { env -u X kubecolor \"$@\" }\n"
    let got = commands-from-sh $zsh --zsh | get cmd
    if $got != [z sudo lazydocker eza env kubecolor] { fail $"zsh: got ($got | to nuon)" }
    let py = "#!/usr/bin/env python3\nimport subprocess\nsubprocess.run([\"ddcutil\", \"detect\"])\nsubprocess.run(cmd)\n"
    let got = commands-from-py $py | get cmd
    if $got != [python3 ddcutil] { fail $"py: got ($got | to nuon)" }
    let unit = "[Service]\nExecStart=-/usr/bin/wg-quick up wg0\nExecStartPost=%h/.local/bin/notify\nExecStop=@DIR@/stop.nu\n"
    let got = commands-from-unit $unit | get cmd
    if $got != ["/usr/bin/wg-quick"] { fail $"unit: got ($got | to nuon)" }
}

def undeclared-check [] {
    let map = {
        ethtool: {owner: ethtool, providers: [ethtool]}
        lsusb: {owner: usbutils, providers: [usbutils fwupd]}
        ls: {owner: base, providers: []}
        herdr: {owner: "-", providers: []}
    }
    let cases = [
        [name modules wants];
        ["undeclared" [(module-fake base/nic "^ethtool -K eth0 tso off")] ["base/nic ethtool"]]
        ["declared" [(module-fake base/nic "^ethtool -K eth0 tso off" --packages [ethtool])] []]
        ["declared by a package that pulls it in" [(module-fake base/usb "^lsusb" --packages [fwupd])] []]
        ["base set" [(module-fake core/files "^ls -la")] []]
        ["the repo's own" [(module-fake core/herdr "^herdr open")] []]
        ["unknown to the map" [(module-fake core/x "^not-mapped")] []]
        ["from a transitive dep" [(module-fake a/top "^ethtool" --deps [a/mid]) (module-fake a/mid "" --deps [a/low]) (module-fake a/low "" --packages [ethtool])] []]
        ["from a module that is no dep" [(module-fake a/one "^ethtool") (module-fake a/two "" --packages [ethtool])] ["a/one ethtool"]]
        ["guarded" [(module-fake base/nic "if (which ethtool | is-not-empty) { ^ethtool -K eth0 tso off }")] []]
    ]
    for c in $cases {
        let got = commands-undeclared $c.modules $map | get --optional key | default []
        if $got != $c.wants { fail $"($c.name): got ($got | to nuon), wants ($c.wants | to nuon)" }
    }
}

def fail-closed-check [] {
    let old = "let tor = $TOR | path exists\n(if $policy == lockdown-tor and $tor {\n    unit-enable fw-egress.service\n} else {\n    unit-disable fw-egress.service --now\n})"
    let cases = [
        [name code wants];
        ["policy only" "if $policy != lockdown-tor {\n    ok systemctl stop fw-egress.service | ignore\n}" 0]
        ["enabled, never off" "(unit-enable fw-egress.service)" 0]
        ["off on the path" "const TOR = \"/usr/bin/tor\"\nif not ($TOR | path exists) {\n    ok systemctl stop fw-egress.service\n}" 1]
        ["off through a let and an else" $"const TOR = \"/usr/bin/tor\"\n($old)" 1]
        ["const list on one line" "const UNITS = [fw-lockdown.service fw-egress.service]\nif (which tor | is-empty) { $UNITS | each {|u| unit-disable $u } }" 1]
        ["const list over lines" "const UNITS = [fw-egress.service]\nif (which tor | is-empty) {\n    $UNITS | each {|u|\n        unit-mask $u\n    }\n}" 1]
        ["gate only in comments" "# fw-egress stays on without /usr/bin/tor\nif $policy != lockdown-tor { unit-disable fw-egress.service } # not on which tor" 0]
        ["gate elsewhere in the file" "const TOR = \"/usr/bin/tor\"\nif ($TOR | path exists) { start-tor }\nif $policy == off { unit-disable fw-egress.service }" 0]
        ["another unit off" "if (which tor | is-empty) { unit-disable fw-inbound.service }\n(unit-enable fw-egress.service)" 0]
    ]
    for c in $cases {
        let got = commands-fail-closed $REPO [(module-fake base/nftables $c.code)] | length
        if $got != $c.wants { fail $"fail closed, ($c.name): ($got) findings, wants ($c.wants)" }
    }
    let empty = mktemp --directory --tmpdir dot-fail-closed-test-XXXXXX
    let lost = commands-fail-closed $empty [] | length
    rm --recursive --force $empty
    if $lost != ($FAIL_CLOSED | length) { fail $"fail closed, no escape files: ($lost) findings, wants ($FAIL_CLOSED | length)" }
}

def allow-check [] {
    let lines = ["# head" "" "base/nic ethtool  # pending" "base/usb lsusb" "core/x gone  # pending"]
    let got = commands-allow-check $lines ["base/nic ethtool" "base/usb lsusb"]
    if $got.allowed != ["base/nic ethtool" "base/usb lsusb" "core/x gone"] { fail $"allow: keys ($got.allowed | to nuon)" }
    if ($got.findings | length) != 2 or not ($got.findings.0 =~ ':4: .* no reason') or not ($got.findings.1 =~ ':5: .* drop the line') {
        fail $"allow: findings ($got.findings | to nuon)"
    }
}

const HOOK_MODULE = "use profile.nu [profile-has]
export def packages [cfg: record]: nothing -> record {
    let owner = if (profile-has secrets) { [owner-tool] } else { [plain-tool] }
    {pacman: ($owner ++ [$\"driver-($cfg.driver)\" $\"port-($cfg.port)\"])}
}
"

# The packages every profile and option can want, the same whichever profile the caller runs under.
def packages-every-check [] {
    let repo = mktemp --directory --tmpdir dot-commands-test-XXXXXX
    mkdir ($repo | path join profiles) ($repo | path join platforms) ($repo | path join mod)
    {capabilities: [secrets]} | save ($repo | path join profiles owner.nuon)
    {"x/mod": {port: 2}} | save ($repo | path join platforms box.options.nuon)
    $HOOK_MODULE | save ($repo | path join mod mod.nu)
    let m = {
        id: x/mod, dir: ($repo | path join mod), native: [packages]
        meta: {packages: {pacman: [base-tool], native: [], flatpak: {}, nix: []}}
        options: {driver: {type: "string?", default: null, choices: [open legacy]}, port: {type: int, default: 1}}
        cfg: {enable: false, driver: legacy, port: 9}
    }
    let every = packages-every-context $repo
    let as_owner = with-env {PROFILE_FILE: ($repo | path join profiles owner.nuon)} { module-packages-every $m $every }
    let as_nobody = with-env {PROFILE_FILE: "", XDG_CONFIG_HOME: ($repo | path join none)} { module-packages-every $m $every }
    rm --recursive --force $repo
    let wants = [base-tool driver- driver-legacy driver-open owner-tool plain-tool port-1 port-2]
    if ($as_owner | sort) != $wants { fail $"packages every: got ($as_owner | sort | to nuon), wants ($wants | to nuon)" }
    if $as_owner != $as_nobody { fail $"packages every: ($as_owner | to nuon) as the owner, ($as_nobody | to nuon) as nobody" }
}

def wrapper-chain-check [] {
    let cases = [
        [name words wants];
        ["no wrapper" [ls -la] [ls]]
        ["nested" [sudo -n systemd-run --user flock /l make] [sudo systemd-run flock make]]
        ["timeout without a command" [timeout "5"] [timeout]]
        ["path basename" [/usr/bin/env -i ls] [/usr/bin/env ls]]
    ]
    for c in $cases {
        let got = wrapper-chain $c.words
        if $got != $c.wants { fail $"wrapper chain, ($c.name): got ($got | to nuon), wants ($c.wants | to nuon)" }
    }
}

# Resolving against the sync databases: the files database's paths, its owners in repo order, a row's providers.
def resolve-check [] {
    let paths = [[cmd want]; [ethtool usr/bin/ethtool] [/usr/sbin/nft usr/bin/nft] [/bin/sh usr/bin/sh] [/usr/lib/qt6/bin/qml usr/lib/qt6/bin/qml]]
    for p in $paths { if (command-db-path $p.cmd) != $p.want { fail $"db path ($p.cmd): got (command-db-path $p.cmd)" } }
    let nul = char nul
    let owners = command-owners-parse ([lsck0 ethtool 1 usr/bin/ethtool extra ethtool 1 usr/bin/ethtool lsck0 fprintd-clients-git 1 usr/bin/fprintd-list extra fprintd 1 usr/bin/fprintd-list]
        | chunks 4 | each { str join $nul } | str join "\n")
    let want = {usr/bin/ethtool: [ethtool], usr/bin/fprintd-list: [fprintd-clients-git fprintd]}
    if $owners != $want { fail $"owners: got ($owners | to nuon)" }
    let by = {fprintd: [base-fp], ethtool: [nic-tools]}
    let rows = [
        [name owners wants];
        ["no package" [] {owner: "-", providers: []}]
        ["base" [coreutils] {owner: base, providers: []}]
        ["first owner, every owner's bringers" [fprintd-clients-git fprintd] {owner: fprintd-clients-git, providers: [base-fp fprintd fprintd-clients-git]}]
    ]
    for r in $rows {
        let got = command-row $r.owners [coreutils glibc] $by
        if $got != $r.wants { fail $"row, ($r.name): got ($got | to nuon), wants ($r.wants | to nuon)" }
    }
    let tree = "bemenu-wayland\n|-glibc\n| `-linux-api-headers>=4.10\n`-bemenu provides libbemenu.so=0-64\n"
    if (pactree-names $tree) != [bemenu-wayland glibc linux-api-headers bemenu] { fail $"pactree names: (pactree-names $tree | to nuon)" }
}

def main [] {
    extraction-check
    wrapper-chain-check
    resolve-check
    undeclared-check
    fail-closed-check
    allow-check
    packages-every-check
}
