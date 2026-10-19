use state.nu [SYSTEM_REPO SYSTEM_STATE]
use ledger.nu [ledger-get]
use platform.nu [platform-load]
use profile.nu [profile-has]
use secrets.nu [secret-is-plaintext]
use written.nu [preserve-report]
use drift.nu [drift-report]
use audit.nu [audit-findings]

const REPO = path self ../..
const INVARIANTS = path self invariants.txt
const PROFILES_CONF = path self ../../configs/base/apparmor/profiles.conf
const BORG_SCRIPT = path self ../../configs/core/borg/borg-backup.nu
const SYNCTHING_CONFIG = ".local/state/syncthing/config.xml"
const WITNESS = path self ../../secrets/pgp_privatekey.asc
const APPARMOR_MANUAL = "/etc/apparmor/flags.d/manual.conf"
const TIMESHIFT_LOGS = "/var/log/timeshift"
const SYSTEM_PATHS = [configs platforms profiles scripts]
const SNAPSHOT_MAX_DAYS = 30
const TIMESHIFT_MAX_DAYS = 14
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
    $files | str join "\u{0}" | ^xargs -0 sha256sum | lines
}

def config-pending []: nothing -> list<record> {
    if not ($SYSTEM_REPO | path exists) { return [] }
    let head = ^git -C $REPO rev-parse HEAD | str trim
    let source = try { open --raw ($SYSTEM_REPO | path join .source) | str trim } catch { "" }
    let ours = ^git -C $REPO ls-files -z --cached --others --exclude-standard --deduplicate -- ...$SYSTEM_PATHS
        | split row "\u{0}" | where {|f| $f != "" and (($REPO | path join $f | path type) == file) }
    let theirs = cd $SYSTEM_REPO | ^find . -type f ! -name .source -printf '%P\n' | lines
    let a = hashes $REPO $ours
    let b = hashes $SYSTEM_REPO $theirs
    let changed = ($a | where $it not-in $b) ++ ($b | where $it not-in $a) | each { str substring 66.. } | uniq | length
    if $source != $head or $changed > 0 {
        let at = $"the root copy is at ($source | str substring 0..6), the checkout at ($head | str substring 0..6)"
        [(report FAIL config $"dot apply pending: ($at) with ($changed) files differing")]
    } else {
        [(report ok config "the root copy matches the checkout")]
    }
}

# ukis rebuilt after this boot started: the running initramfs and cmdline are old
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

# backed off from the enforce baseline: a manual `aa complain|off`, or a running process of ours in complain
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
    if ($backed ++ $live | is-not-empty) {
        [(report FAIL apparmor $"backed off from enforce: (shown ($backed ++ $live)); aa enforce <profile>")]
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
        [(report FAIL snapshot $"lsck0 snapshot ($pin) from ($day), ($age) days old: scripts/system-update.nu")]
    } else {
        [(report ok snapshot $"lsck0 snapshot ($pin) from ($day), ($age) days old")]
    }
}

def drift []: nothing -> list<record> {
    let text = try { drift-report } catch {
        return [(report note drift "no drift report (no machine ledger or platform file)")]
    }
    let names = {|kind|
        $text | lines | where ($it | str starts-with $"($kind) ") | each { str substring (($kind | str length) + 1).. }
    }
    let missing = do $names missing
    let hand = do $names hand
    let units = do $names unit-hand | each { str replace " " ":" }
    [
        (if ($missing | is-not-empty) {
            report FAIL drift $"dot apply --packages pending, declared but not installed: (shown $missing)"
        })
        (if ($hand | is-not-empty) { report note drift $"($hand | length) packages installed by hand: (shown $hand)" })
        (if ($units | is-not-empty) { report note drift $"($units | length) units enabled by hand: (shown $units)" })
        (if ($missing ++ $hand ++ $units | is-empty) { report ok drift "packages and units as declared" })
    ] | compact
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

# the repo only counts once every other device of borg-<host> holds it, a day's grace for the upload
def borg-replicated [age: int]: nothing -> list<record> {
    let config = $nu.home-dir | path join $SYNCTHING_CONFIG
    if not ($config | path exists) { return [(report FAIL borg "no syncthing config, the borg repo never leaves")] }
    let text = open --raw $config
    let api = $text | parse --regex '<gui[^>]*>\s*<address>(?<address>[^<]+)</address>' | get 0.address
    let headers = [X-API-Key ($text | parse --regex '<apikey>(?<key>[^<]+)</apikey>' | get 0.key)]
    let folder = $"borg-(sys host | get hostname)"
    let self = try { http get --headers $headers $"http://($api)/rest/system/status" | get myID } catch {
        return [(report FAIL borg $"syncthing does not answer on ($api), the borg repo is not leaving")]
    }
    let names = http get --headers $headers $"http://($api)/rest/config/devices" | select deviceID name
    let devices = try {
        http get --headers $headers $"http://($api)/rest/config/folders/($folder)" | get devices.deviceID
    } catch { [] } | where $it != $self
    if ($devices | is-empty) { return [(report FAIL borg $"no device receives the syncthing folder ($folder)")] }
    $devices | each {|device|
        let name = $names | where deviceID == $device | get --optional 0.name | default ($device | str substring 0..6)
        let done = http get --headers $headers $"http://($api)/rest/db/completion?folder=($folder)&device=($device)"
        if $done.remoteState == "notSharing" {
            report FAIL borg $"($name) does not accept the syncthing folder ($folder), declare it there"
        } else if $done.completion < 100 {
            report (if $age > 0 { "FAIL" } else { "note" }) borg $"($name) holds ($done.completion | math floor)% of ($folder)"
        } else {
            report ok borg $"($name) holds all of ($folder)"
        }
    }
}

def borg []: nothing -> list<record> {
    if not (succeeds [systemctl --user -q is-enabled borg-backup.timer]) { return [] }
    let stale_days = open --raw $BORG_SCRIPT | parse --regex 'const STALE_DAYS = (?<d>\d+)' | get 0.d | into int
    let stamp = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join borg last-success
    if not ($stamp | path exists) {
        return [(report FAIL borg "no borg backup has succeeded yet: systemctl --user start borg-backup")]
    }
    let age = days-since (mtime $stamp)
    if $age > $stale_days {
        let when = $"($age) days ago, more than ($stale_days)"
        [(report FAIL borg $"last borg backup ($when): journalctl --user -u borg-backup")]
    } else {
        [(report ok borg $"last borg backup (mtime $stamp | format date '%F %H:%M')")]
    } | append (borg-replicated $age)
}

# root keeps the snapshots out of reach, its logs are readable: the newest that counted them
def timeshift []: nothing -> list<record> {
    if (which timeshift | is-empty) or not (succeeds [systemctl -q is-enabled timeshift-check.timer]) { return [] }
    let counted = glob ($TIMESHIFT_LOGS | path join "*.log") | sort --reverse | each {|log|
        let counts = try { open --raw $log | parse --regex '(?<n>\d+) snapshots, ' | get n } catch { [] }
        if ($counts | is-empty) { null } else { {log: $log, count: ($counts | last | into int)} }
    } | compact | get --optional 0
    if $counted == null {
        return [(report FAIL timeshift "no timeshift log counts any snapshot: systemctl start timeshift-check")]
    }
    let day = mtime $counted.log | format date "%F"
    let age = days-since (mtime $counted.log)
    if $counted.count == 0 {
        [(report FAIL timeshift $"no timeshift snapshot as of ($day)")]
    } else if $age > $TIMESHIFT_MAX_DAYS {
        [(report FAIL timeshift $"timeshift last ran ($age) days ago: journalctl -u timeshift-check")]
    } else {
        [(report ok timeshift $"($counted.count) snapshots as of ($day)")]
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
    failures config-pending reboot invariants apparmor snapshot drift firewall units borg timeshift secrets preserved
]

def check-run [check: string]: nothing -> list<record> {
    match $check {
        failures => (failures), config-pending => (config-pending), reboot => (reboot), invariants => (invariants)
        apparmor => (apparmor), snapshot => (snapshot), drift => (drift), firewall => (firewall), units => (units)
        borg => (borg), timeshift => (timeshift), secrets => (secrets), preserved => (preserved)
    }
}

export def doctor-checks []: nothing -> list<record> {
    $CHECKS | each { check-run $in } | flatten
}

# --brief: only FAIL lines as "<check>: <text>", doctor-check reads these; true when a check failed
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
