#!/usr/bin/env -S nu --no-config-file
# Failure causes: a failing external and a missing binary through apply-module's exec and step and a caught error, the
# hint table per class, FAILURES grouping and order, and the two failures of a reinstall before and after.
use cause.nu [cause-from-error cause-from-output cause-text cause-hint failure-line failure-parse failures-group failure-is-system PACKAGES_FIX ONLINE_ESCAPE]
use converge.nu [apply-module]
use pipeline.nu [module-failure]
use system-apply.nu [pacman-failure]
use doctor.nu [failures-reports]

const ABSENT = "dot-cause-test-absent"

def fail [msg: string] { error make {msg: $"cause.test: ($msg)"} }

def wants [what: string, got: string, parts: list<string>]: nothing -> nothing {
    for p in $parts { if not ($got | str contains $p) { fail $"($what): ($got | to nuon) lacks ($p | to nuon)" } }
}

def action [kind: string, target: string, argv: list<string>]: nothing -> record {
    {module: test/cause, kind: $kind, target: $target, reason: "", before: null, after: null, decl: {kind: $kind, target: $target, argv: $argv, then: [], creates: null}}
}

def exec-cases [dir: path]: nothing -> nothing {
    let failing = apply-module [(action exec "fails" [sh -c "echo first >&2; echo the real reason >&2; exit 3"])] $dir user | first
    if $failing.ok { fail "a command exiting 3 counted as ok" }
    wants "failing exec" $failing.error ["`sh -c 'echo first >&2; echo the real reason >&2; exit 3'`" "exited 3" "the real reason"]
    let absent = apply-module [(action exec "absent" [$ABSENT --flag])] $dir user | first
    wants "absent exec" $absent.error [$"($ABSENT) not installed" "no package known"]
    let known = cause-text (cause-from-output "lsusb -d 1050:" 127 "setsid: failed to execute lsusb: No such file or directory")
    wants "absent, package known" $known ["lsusb not installed (usbutils)"]
}

def step-cases [dir: path]: nothing -> nothing {
    [
        "export def probe-exit [] { ^sh -c 'echo again >&2; exit 5'; print unreachable }"
        $"export def probe-absent [] { ^($ABSENT) -d 1050: | complete }"
        "export def probe-made [] { error make {msg: 'the module says why'} }"
        "export def probe-tail [] { ^sh -c 'echo last words >&2; exit 6' }"
    ] | str join "\n" | save --force ($dir | path join mod.nu)
    let exited = apply-module [(action step probe-exit [])] $dir user | first
    wants "step exiting" $exited.error ["`sh -c 'echo again >&2; exit 5'`" "exited 5" "again" "mod.nu:1"]
    let tail = apply-module [(action step probe-tail [])] $dir user | first
    wants "step ending on a failing command" $tail.error ["`step probe-tail` exited 6" "last words"]
    let absent = apply-module [(action step probe-absent [])] $dir user | first
    wants "step absent" $absent.error [$"($ABSENT) not installed" "mod.nu:2"]
    let made = apply-module [(action step probe-made [])] $dir user | first
    if $made.error != "the module says why" { fail $"step error make: ($made.error | to nuon)" }
}

# the nvim prefetch of a VM run: its last progress line had no newline, so the error block began mid-line, and the
# message wrapped at 80 columns
def wrapped-cases []: nothing -> nothing {
    let output = [
        "Downloading websocat 99.1%"
        "All binaries downloaded to /home/u/typst-preview/Error: nu::shell::error"
        ""
        "  x 1 tools are not installed after the restore (:MasonLog, :checkhealth nvim-"
        "  | treesitter): mason/gopls"
        "     ,-[/repo/configs/programming/nvim/mod.nu:121:20]"
        " 120 |     if ($missing | is-not-empty) {"
        " 121 |         error make {msg: $\"($missing | length) tools\"}"
        "     :                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
        " 122 |     }"
        "     `----"
    ] | str join "\n"
    let text = cause-text (cause-from-output "step prefetch" 1 $output)
    wants "error mid-line" $text ["1 tools are not installed after the restore (:MasonLog, :checkhealth nvim- treesitter): mason/gopls" "All binaries downloaded to /home/u/typst-preview/"]
    for junk in ["^^^" "122 |" "`----"] { if ($text | str contains $junk) { fail $"error mid-line: ($text | to nuon) carries the snippet's ($junk | to nuon)" } }
}

def caught-cases [dir: path]: nothing -> nothing {
    let file = $dir | path join caught.nu
    $"export def unlock [] {\n    if true { ^($ABSENT) -d 1050: | complete }\n}\nexport def code [] {\n    ^sh -c 'exit 7'\n    print unreachable\n}\n" | save --force $file
    let src = $"use ($file | to nuon) [unlock code]; use cause.nu [cause-from-error cause-text]\n"
    let run = {|call| ^$nu.current-exe --no-config-file -I ($env.FILE_PWD) -c $"($src)try { ($call) } catch {|e| print $\"cause: \(cause-text \(cause-from-error $e\)\)\" }" | str trim }
    wants "caught absent" (do $run unlock) [$"($ABSENT) not installed" "caught.nu:2"]
    wants "caught exit" (do $run code) ["`sh -c 'exit 7'`" "exited 7" "caught.nu:5"]
}

# dot apply at a terminal re-execs under script (pty-log): its errors render for a tty, in colour and box drawing, and
# still name their cause.
def tty-cases [dir: path]: nothing -> nothing {
    let file = $dir | path join tty.nu
    $"export def code [] {\n    ^sh -c 'exit 7'\n    print unreachable\n}\nexport def absent [] {\n    ^($ABSENT) -d 1050:\n}\n" | save --force $file
    let probe = $dir | path join tty-probe.nu
    [
        $"use ($file | to nuon) [code absent]"
        "use cause.nu [cause-from-error cause-text]"
        "def shown [e: record] { print $\"fancy=($e.rendered | str contains \(ansi reset\)) and ($e.rendered | str contains \(char --unicode '2502'\))\"; print $\"cause: \(cause-text \(cause-from-error $e\)\)\" }"
        "try { code } catch {|e| shown $e }"
        "try { absent } catch {|e| shown $e }"
    ] | str join "\n" | save --force $probe
    let run = ^script -qe -c $"($nu.current-exe) --no-config-file -I ($env.FILE_PWD) ($probe)" /dev/null | complete
    # a terminal title nushell sets can lead a line: the probe's lines are found by their markers
    let out = $run.stdout | ansi strip | lines
    if ($out | where $it =~ 'fancy=true and true$' | length) != 2 { fail $"the probe did not render for a tty, exit ($run.exit_code): ($out | to nuon)" }
    let causes = $out | parse --regex 'cause: (?<text>.*?)\s*$' | get text
    wants "tty exit" ($causes | get --optional 0 | default "") ["`sh -c 'exit 7'`" "exited 7" "tty.nu:2"]
    wants "tty absent" ($causes | get --optional 1 | default "") [$"($ABSENT) not installed" "tty.nu:6"]
}

def hint-cases []: nothing -> nothing {
    let cases = [
        [text class fix];
        ["lsusb not installed (usbutils) (at configs/base/yubikey/yubikey.nu:242)" missing $PACKAGES_FIX]
        ["error: failed retrieving file 'core.db' from mirror.lsck0.dev : Could not resolve host: mirror.lsck0.dev" dns $ONLINE_ESCAPE]
        ["error: failed retrieving file 'x' : The requested URL returned error: 429" refused "429, a rate ban"]
        ["`pacman -S foo` exited 1: error: target not found: foo" not-found "no repo has foo"]
        ["warning: cannot resolve \"libbar\", a dependency of \"foo\" / error: unable to satisfy dependency 'libbar>=2' required by foo" unsatisfied "no repo has libbar>=2"]
        ["configs/secrets/keys/x.age starts with \\0GITCRYPT" locked "dot secrets unlock"]
        ["secrets are locked" locked "dot secrets unlock"]
        ["audit: apparmor=\"DENIED\" operation=\"open\" profile=\"foo\"" apparmor "l-dotfiles-apparmor-profile"]
        ["`systemctl --user restart a.service` exited 1: Job for a.service failed because the control process exited with error code. / See \"systemctl --user status a.service\" for details." unit "journalctl --user -u a.service -b"]
        ["`systemctl restart b.service` exited 1: Job for b.service failed because a timeout was exceeded." unit "journalctl -u b.service -b"]
        ["`sudo true` exited 1: sudo: a terminal is required to read the password" root "dot apply --system"]
        ["`sudo true` exited 1: sudo: 3 incorrect password attempts" root "dot apply --system"]
        ["`install -m 600 x /etc/y` exited 1: install: cannot create regular file '/etc/y': Permission denied" root "dot apply --system"]
        ["plain failure nobody classified" null null]
        ["`aa-status` exited 4 (at configs/base/apparmor/mod.nu:12)" null null]
    ]
    for c in $cases {
        let h = cause-hint $c.text
        if ($h.class? | default null) != $c.class { fail $"hint of ($c.text | to nuon): class ($h.class? | to nuon), wants ($c.class | to nuon)" }
        if $c.fix != null { wants $"fix of ($c.class)" $h.fix [$c.fix] }
    }
}

def group-cases []: nothing -> nothing {
    let lines = [
        "dot secrets unlock: secrets are locked; fix: dot secrets unlock (YubiKey)"
        "system layer config: sudo exited 1, root recorded no failure; fix: dot apply --system at a terminal"
        "base/a link/exec x: a not installed (pkg-a); fix: dot apply --packages"
        "base/b link/step y: `systemctl restart b.service` exited 1: Job for b.service failed; fix: journalctl -u b.service -b"
        "base/c system/exec z: c not installed (pkg-c); fix: dot apply --packages"
        "base/d link/eval: Cannot find column 'q'"
        "base/e link/eval: Cannot find column 'q'"
        "base/a link/exec x: a not installed (pkg-a); fix: dot apply --packages"
        "base/f"
    ]
    let got = failures-group $lines
    let expected = [
        "dot secrets unlock: secrets are locked; fix: dot secrets unlock (YubiKey)"
        "2 modules (base/a base/c): not installed: a (pkg-a), c (pkg-c); fix: dot apply --packages"
        "base/b link/step y: `systemctl restart b.service` exited 1: Job for b.service failed; fix: journalctl -u b.service -b"
        "2 modules (base/d base/e): Cannot find column 'q'"
        "base/f"
        "system layer config: sudo exited 1, root recorded no failure; fix: dot apply --system at a terminal"
    ]
    if $got != $expected { fail $"grouping:\n($got | str join "\n")\nwants\n($expected | str join "\n")" }
    let units = failures-group [
        "base/b link/step y: Job for b.service failed; fix: journalctl -u b.service -b"
        "base/g link/step y: Job for g.service failed; fix: journalctl -u g.service -b"
    ]
    if $units != ["2 modules (base/b base/g): units failing to start: b.service, g.service; fix: journalctl -u <unit> -b"] { fail $"unit group: ($units | to nuon)" }
    let p = failure-parse "base/a link/update ~/.config/a: `x` exited 1: a: b; fix: do this"
    if $p != {subject: base/a, where: "link/update ~/.config/a", text: "`x` exited 1: a: b", fix: "do this"} { fail $"parse: ($p | to nuon)" }
    let systems = [
        ["base/boot system/step commit: x" true] ["system layer pacman the install pass: y" true] ["base/x link/eval: z" false] ["dot secrets unlock: w" false]
    ]
    for s in $systems { if (failure-is-system $s.0) != $s.1 { fail $"failure-is-system ($s.0)" } }
}

# A crash in a guarded run: crash.json, the run's PANIC record and dot log --trace name the same cause.
def crash-cases [dir: path]: nothing -> nothing {
    let state = $dir | path join state
    let file = $dir | path join crashing.nu
    "export def crash [] {\n    ^sh -c 'echo the crash reason >&2; exit 4'\n    print unreachable\n}\n" | save --force $file
    let call = $"use ($file | to nuon) [crash]; use cli.nu [guarded]; guarded probe --read-only { crash }"
    with-env {XDG_STATE_HOME: $state} { ^$nu.current-exe --no-config-file -I ($env.FILE_PWD) -c $call | complete } | ignore
    let crash = open ($state | path join dotfiles crash.json)
    if $crash.cause.exit_code != 4 or $crash.cause.command != "sh -c 'echo the crash reason >&2; exit 4'" { fail $"crash cause: ($crash.cause | to nuon)" }
    let panic = open --raw (glob ($state | path join dotfiles runs *.jsonl) | first) | lines | each { from json } | where level == PANIC | first
    if $panic.cause != $crash.cause { fail $"the PANIC record's cause differs from crash.json's: ($panic.cause | to nuon)" }
    wants "panic line" $panic.msg ["`sh -c 'echo the crash reason >&2; exit 4'` exited 4" "crashing.nu:2"]
    let trace = with-env {XDG_STATE_HOME: $state} { ^$nu.current-exe --no-config-file ($env.FILE_PWD | path join .. dot.nu) log $crash.run --trace }
    wants "trace" $trace ["probe" "! `sh -c 'echo the crash reason >&2; exit 4'` exited 4"]
}

# The reinstall's two failures: what dot status --brief said, and what the same failures say now.
export def reinstall-fixture [dir: path]: nothing -> record {
    let before = [
        "failures: FAILURES.config from 2026-10-30 18:39, 32: dot secrets unlock: External command failed system layer: config base/apparmor base/boot/sbctl base/fwupd base/lact base/networkmanager base/plymouth (+24 more)"
        "install pacman: the install pass failed"
    ]
    let file = $dir | path join yubikey.nu
    "export def yubikey-unlock [] {\n    if (^lsusb -d 1050: | complete).exit_code == 0 { print plugged }\n}\n" | save --force $file
    # PATH without lsusb, as on the fresh laptop
    let unlock = ^$nu.current-exe --no-config-file -I ($env.FILE_PWD) -c $"use ($file | to nuon) [yubikey-unlock]; use cause.nu [cause-from-error cause-text failure-line]
with-env {PATH: []} { try { yubikey-unlock } catch {|e| print \(failure-line 'dot secrets unlock' null \(cause-text \(cause-from-error $e\)\)\) } }" | str trim
    let missing = [
        [base/apparmor aa-enabled apparmor] [base/boot/sbctl sbctl sbctl] [base/fwupd fwupdmgr fwupd] [base/lact lact lact]
        [base/networkmanager nmcli networkmanager] [base/plymouth plymouth-set-default-theme plymouth]
    ] ++ (1..24 | each {|i| [$"desktop/m($i)" $"tool($i)" $"pkg($i)"] })
    let modules = $missing | each {|m|
        let text = cause-text (cause-from-output $"($m.1) --version" 127 $"setsid: failed to execute ($m.1): No such file or directory") | str replace "no package known" $m.2
        module-failure {id: $m.0, outcomes: [{ok: false, kind: exec, target: $"($m.1) setup", error: $text}], error: $text} system false
    }
    let install = pacman-failure "the install pass" [-Su --needed --noconfirm --ask 4 base linux sbctl fwupd] 1 "resolving dependencies...\nwarning: cannot resolve \"libjcat\", a dependency of \"fwupd\"\nerror: failed to prepare transaction (could not satisfy dependencies)\n:: unable to satisfy dependency 'libjcat' required by fwupd\n"
    let config = [$unlock ...$modules]
    {before: $before, config: $config, after_config: (failures-group $config), after_install: (failures-group [$install])}
}

def reinstall-cases [dir: path]: nothing -> nothing {
    let f = reinstall-fixture $dir
    wants "unlock" $f.after_config.0 ["dot secrets unlock: lsusb not installed (usbutils)" "yubikey.nu:2" $"fix: ($PACKAGES_FIX)"]
    wants "modules" $f.after_config.1 ["30 modules (base/apparmor base/boot/sbctl" "+24 more" "not installed: aa-enabled (apparmor), sbctl (sbctl)" $"fix: ($PACKAGES_FIX)"]
    if ($f.after_config | length) != 2 { fail $"reinstall config groups: ($f.after_config | to nuon)" }
    let file = $dir | path join FAILURES.config
    $f.config | str join "\n" | save --force $file
    let status = failures-reports [$file] | each { $"($in.check): ($in.text)" }
    if ($status | length) != 3 { fail $"status lines: ($status | to nuon)" }
    wants "status head" $status.0 ["FAILURES.config from" "31 failed" "dot log --trace"]
    wants "status groups" ($status | skip 1 | str join "\n") ["  dot secrets unlock: lsusb" "  30 modules (base/apparmor"]
    wants "install" $f.after_install.0 ["pacman the install pass: `pacman -Su --needed" "exited 1" "unable to satisfy dependency 'libjcat' required by fwupd" "fix: no repo has libjcat"]
}

def main [--show] {
    let dir = mktemp --directory --tmpdir dot-cause-test-XXXXXX
    if $show {
        print (reinstall-fixture $dir | to yaml)
        rm --recursive --force $dir
        return
    }
    exec-cases $dir
    step-cases $dir
    caught-cases $dir
    wrapped-cases
    tty-cases $dir
    hint-cases
    group-cases
    reinstall-cases $dir
    crash-cases $dir
    rm --recursive --force $dir
}
