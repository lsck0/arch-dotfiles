# The health checks of `dot status`.

use state.nu [SYSTEM_REPO SYSTEM_STATE]
use ledger.nu [ledger-get]
use platform.nu [platform-load]
use profile.nu [profile-has]
use secrets.nu [secret-is-plaintext]
use system.nu [system-files]
use preserve.nu [preserve-report]
use pipeline.nu [pipeline-load]
use modules.nu [modules-packages]
use ../../configs/base/yubikey/audit.nu [audit-findings]

const REPO = path self ../..
const INVARIANTS = path self invariants.txt
const PROFILES_CONF = path self ../../configs/base/apparmor/profiles.conf
const LUKS_TOKENS = [TPM2 FIDO2]
const LUKS_TOKEN_MISSING = 'No valid (?<token>TPM2|FIDO2) token data found'
const WITNESS = path self ../../configs/secrets/keys/pgp_privatekey.asc
const APPARMOR_MANUAL = "/etc/apparmor/flags.d/manual.conf"
const SNAPSHOT_MAX_DAYS = 30
const SHOWN_MAX = 8

def report [level: string, check: string, text: string]: nothing -> record {
    {level: $level, check: $check, text: $text}
}

def shown [names: list<string>]: nothing -> string {
    let more = if ($names | length) > $SHOWN_MAX { $" \(+(($names | length) - $SHOWN_MAX) more\)" } else { "" }
    $"($names | first $SHOWN_MAX | str join ' ')($more)"
}

def days-since [time: datetime]: nothing -> int { (date now) - $time | $in / 1day | math floor }

def mtime [file: path]: nothing -> datetime { ls $file | get 0.modified }

def failures []: nothing -> list<record> {
    let files = glob ($REPO | path join "FAILURES.*") | where { (ls $in | get 0.size) > 0B }
    if ($files | is-empty) { return [(report ok failures "no FAILURES.* left by dot apply")] }
    $files | each {|f|
        let entries = open --raw $f | lines | where ($it | str trim) != ""
            | each { str replace --regex '.*/configs/' '' }
        let from = $"($f | path basename) from (mtime $f | format date '%F %H:%M')"
        report FAIL failures $"($from), ($entries | length): (shown $entries)"
    }
}

def hashes [dir: path, files: list<string>]: nothing -> list<string> {
    if ($files | is-empty) { return [] }
    cd $dir
    $files | str join "\u{0}" | ^xargs -0 sha256sum | complete | get stdout | lines
}

def config-pending []: nothing -> list<record> {
    if not ($SYSTEM_REPO | path exists) { return [] }
    let head = ^git -C $REPO rev-parse HEAD | str trim
    let source = try { open --raw ($SYSTEM_REPO | path join .source) | str trim } catch { "" }
    let ours = system-files $REPO "--cached" | append (system-files $REPO "--others") | uniq
    let theirs = cd $SYSTEM_REPO | ^find . -type f ! -name .source -printf '%P\n' | lines
    let a = hashes $REPO $ours
    let b = hashes $SYSTEM_REPO $theirs
    let changed = ($a | where $it not-in $b) ++ ($b | where $it not-in $a) | each { str substring 66.. } | uniq | length
    if $changed > 0 {
        let at = $"the root copy is at ($source | str substring 0..6), the checkout at ($head | str substring 0..6)"
        [(report FAIL config $"dot apply pending: ($at) with ($changed) files differing")]
    } else {
        [(report ok config "the root copy matches the checkout")]
    }
}

def reboot []: nothing -> list<record> {
    let stamp = $SYSTEM_STATE | path join boot-inputs
    if not ($stamp | path exists) { return [] }
    let boot = open /proc/stat | lines | parse "btime {s}" | get 0.s | into int | $in * 1_000_000_000 | into datetime
    if (mtime $stamp) > $boot {
        let built = mtime $stamp | format date '%F %H:%M'
        [(report FAIL reboot $"reboot pending: the boot chain was rebuilt ($built), after this boot")]
    } else {
        [(report ok reboot "the running boot chain is the latest built")]
    }
}

def invariants []: nothing -> list<record> {
    open --raw $INVARIANTS | lines | where $it != "" and not ($it | str starts-with "#")
    | parse --regex '^(?<key>\S+)\s+(?<want>\S+)\s+(?<where>\S+)\s+(?<probe>.*)$' | where where == live
    | each {|i|
        let value = do { ^bash -c $i.probe } | complete | get stdout | str trim
        if $value == "n/a" { return null }
        if $value == $i.want {
            report ok invariant $"($i.key)=($value)"
        } else {
            report FAIL invariant $"($i.key)=($value), expected ($i.want)"
        }
    } | compact
}

def apparmor []: nothing -> list<record> {
    if (try { open --raw /sys/module/apparmor/parameters/enabled | str trim } catch { "" }) != "Y" {
        return [(report FAIL apparmor "apparmor is not enabled in the kernel")]
    }
    let rows = {|file|
        open --raw $file | lines | where not ($it | str starts-with "#") | parse --regex '^(?<name>\S+)\s+(?<mode>\S+)'
    }
    let enforced = do $rows $PROFILES_CONF | where ($it.mode | str starts-with enforce) | get name | uniq
    let backed = if ($APPARMOR_MANUAL | path exists) { do $rows $APPARMOR_MANUAL } else { [] }
        | where {|r| not ($r.mode | str starts-with enforce) and $r.name in $enforced }
        | each { $"($in.name):($in.mode)" }
    let live = glob /proc/[0-9]*/attr/apparmor/current | each {|f| try { open --raw $f | str trim } catch { "" } }
        | where ($it | str ends-with " (complain)") | each { str replace " (complain)" "" } | uniq | sort
        | where $it in $enforced | each { $"($in):complain \(running\)" }
    let disabled = if ("/etc/apparmor.d/disable" | path exists) {
        # a link aa-install made to disable the stock stub of a profile apparmor.d or this repo replaces is no back-off
        ls /etc/apparmor.d/disable | get name | path basename | where $it in $enforced
            | where {|n| [$"($n).apparmor.d" $"($n).dotfiles"] | all {|f| not ("/etc/apparmor.d" | path join $f | path exists) } }
            | each { $"($in):disabled" }
    } else { [] }
    if ($backed ++ $live ++ $disabled | is-not-empty) {
        [(report FAIL apparmor $"backed off from enforce: (shown ($backed ++ $live ++ $disabled)); aa enforce <profile>")]
    } else {
        [(report ok apparmor "every profiles.conf profile is in its baseline mode")]
    }
}

def snapshot []: nothing -> list<record> {
    let entry = with-env {DOT_LAYER: system} { ledger-get snapshot } | get --optional 0 | default "" | split row " "
    if ($entry | length) < 2 {
        return [(report note snapshot "no lsck0 snapshot in the machine ledger yet (dot apply --packages)")]
    }
    let pin = $entry.0
    let day = $entry.1 | split row T | first
    let age = days-since ($entry.1 | into datetime)
    if $age > $SNAPSHOT_MAX_DAYS {
        [(report FAIL snapshot $"lsck0 snapshot ($pin) from ($day), ($age) days old: dot sync")]
    } else {
        [(report ok snapshot $"lsck0 snapshot ($pin) from ($day), ($age) days old")]
    }
}

# A package group counts as installed.
def packages []: nothing -> list<record> {
    if (which pacman | is-empty) { return [] }
    let ctx = pipeline-load $REPO system
    let declared = modules-packages $REPO $ctx.modules $ctx.platform | get pacman
    let missing = with-env {LC_ALL: C} { do { ^pacman -Qq ...$declared } | complete }
        | get stderr | lines | parse "error: package '{name}' was not found" | get name
        | where {|n| (do { ^pacman -Qqg $n } | complete).exit_code != 0 }
    if ($missing | is-empty) { return [(report ok packages "every declared package installed")] }
    [(report FAIL packages $"dot apply --packages pending, declared but not installed: (shown $missing)")]
}

def succeeds [argv: list<string>]: nothing -> bool { (do { ^$argv.0 ...($argv | skip 1) } | complete).exit_code == 0 }

def firewall []: nothing -> list<record> {
    if (which nft | is-empty) or (platform-load $REPO).form_factor == "wsl" { return [] }
    let egress_enabled = succeeds [systemctl -q is-enabled fw-egress.service]
    let egress_down = $egress_enabled and not (succeeds [systemctl -q is-active fw-egress.service])
    if not (succeeds [systemctl -q is-active fw-lockdown.service fw-inbound.service]) {
        [(report FAIL firewall "no inbound table loaded, fw-lockdown and fw-inbound are both inactive")]
    } else if $egress_down {
        [(report FAIL firewall "fw-egress is enabled but not active")]
    } else {
        [(report ok firewall "inbound and egress tables loaded")]
    }
}

def units []: nothing -> list<record> {
    [system user] | each {|scope|
        let failed = ^systemctl $"--($scope)" list-units --failed --plain --no-legend | lines
            | each { split row " " | first }
        let journal = if $scope == "user" { "journalctl --user -xeu <unit>" } else { "journalctl -xeu <unit>" }
        if ($failed | is-not-empty) {
            report FAIL units $"failed ($scope) units: (shown $failed); ($journal)"
        } else {
            report ok units $"no failed ($scope) unit"
        }
    }
}

def luks []: nothing -> list<record> {
    let options = open --raw /proc/cmdline | parse --regex 'rd\.luks\.options=(?<o>\S+)' | get --optional 0.o | default ""
    let asked = $LUKS_TOKENS | where {|t| $"($t | str lowercase)-device=auto" in ($options | split row ",") }
    if ($asked | is-empty) { return [] }
    let unlock = ^journalctl --boot --quiet --identifier systemd-cryptsetup --output cat --grep $LUKS_TOKEN_MISSING
        | complete | get stdout | parse --regex $LUKS_TOKEN_MISSING | get token | uniq
    $unlock | where $it in $asked | each {|t|
        report note luks ($"the LUKS root has no ($t) token, rd.luks.options asks for one: "
            + "the system apply of base/boot/luks notes the systemd-cryptenroll command")
    }
}

def secrets []: nothing -> list<record> {
    if not (profile-has secrets) { return [] }
    if not (secret-is-plaintext $WITNESS) {
        return [(report note secrets "locked, so not audited: dot secrets unlock")]
    }
    let found = audit-findings | where level != ok
    if ($found | is-empty) { return [(report ok secrets "unlocked, every credential within its rotation limit")] }
    $found | each { report (if $in.level == fail { "FAIL" } else { "note" }) secrets $in.text }
}

def preserved []: nothing -> list<record> {
    [user system] | each {|layer|
        let line = with-env {DOT_LAYER: $layer} { preserve-report } | str replace "preserved: " ""
        report (if ($line | str starts-with none) { "ok" } else { "note" }) preserved $line
    }
}

const CHECKS = [
    failures config-pending reboot invariants apparmor snapshot packages firewall luks units secrets
    preserved
]

def check-run [check: string]: nothing -> list<record> {
    match $check {
        failures => (failures), config-pending => (config-pending), reboot => (reboot), invariants => (invariants)
        apparmor => (apparmor), snapshot => (snapshot), packages => (packages), firewall => (firewall), luks => (luks)
        units => (units)
        secrets => (secrets), preserved => (preserved)
    }
}

# Every check's records, unprinted.
export def doctor-checks []: nothing -> list<record> {
    $CHECKS | each { check-run $in } | flatten
}

# Prints every check (--brief: only FAIL lines as "<check>: <text>"); true when one failed.
export def doctor-run [--brief]: nothing -> bool {
    mut failed = false
    for check in $CHECKS {
        for r in (check-run $check) {
            if $r.level == "FAIL" { $failed = true }
            if not $brief {
                print $"($r.level | fill --width 4)  ($r.check | fill --width 10) ($r.text)"
            } else if $r.level == "FAIL" {
                print $"($r.check): ($r.text)"
            }
        }
    }
    $failed
}
