# The health checks of `dot status`.

use proc.nu [succeeds]
use state.nu [SYSTEM_REPO SYSTEM_STATE state-dir xdg file-trim HOOK_WATCH_PREFIX HOOK_RUN_PREFIX]
use ledger.nu [ledger-get awaited-names LEDGER_AWAITED LSCK0_DB]
use platform.nu [platform-load]
use profile.nu [profile-has]
use secrets.nu [secret-is-plaintext OWNER_WITNESS]
use system.nu [system-files root-acts-on system-recorded secrets-digest SECRETS_PREFIX SECRETS_DIGEST]
use preserve.nu [preserve-report]
use pipeline.nu [pipeline-load pending-recorded]
use online.nu [DNS_TLS_BLOCKED dns-tls-escape]
use modules.nu [modules-packages]
use cause.nu [failures-group names-shown]
use invariants.nu [invariants-load]
use cli.nu [crash-file crash-list crash-read]
use usage.nu [counted]
use ../../configs/base/yubikey/scripts/audit.nu [audit-findings]

# the boot chain barrier's record (base/boot/systemd-boot's meta.barrier): when it last went through
const BOOT_BARRIER = "modules/base/boot/systemd-boot/barrier.nuon"
const REPO = path self ../..
const PROFILES_CONF = path self ../../configs/base/apparmor/config/profiles.conf
const LUKS_TOKENS = [TPM2 FIDO2]
const LUKS_ROOT = 'rd\.luks\.(?:name|uuid)=(?<uuid>[0-9a-fA-F-]+)'
const LUKS_TOKEN_MISSING = 'No valid (?<token>TPM2|FIDO2) token data found'
# systemd's lines for a user-hook oneshot ending, as module.nu's user-hook describes it
const HOOK_OUTCOME = ['^(Failed to start|Finished) ' $HOOK_RUN_PREFIX ' .* hook\.$'] | str join
const WITNESS = $REPO | path join $OWNER_WITNESS
const APPARMOR_MANUAL = "/etc/apparmor/flags.d/manual.conf"
const SNAPSHOT_MAX_DAYS = 30
# `pacman -Sl` marks a package whose installed version differs from that repo's
const SL_DIFFERS = '^(?<repo>\S+) (?<name>\S+) (?<version>\S+) \[installed: (?<installed>[^\]]+)\]$'
# how far back `dot status` looks for programs that dumped core
const CORES_SINCE = "-24h"
const SHOWN_MAX = 8
# failure groups dot status shows per FAILURES file, one line each
const GROUPS_SHOWN = 5
# an invariant probe's answer while the module behind it waits on its packages
const INVARIANT_PENDING = "pending"
# pending work, no fault: `dot status` prints it under this word; --brief, --json and the exit code count it as FAIL
const TODO = "todo"
# `dot status` lists the checks in this order: what needs action first
const LEVELS = [FAIL $TODO note ok]
# a systemd-run without --unit (run-u<n>, run-p<pid>-i<n>): its caller has the exit status, failure-notify skips it too
const UNIT_AD_HOC = '^run-(u[0-9]+|p[0-9]+-i[0-9]+)\.'

def report [level: string, check: string, text: string]: nothing -> record {
    {level: $level, check: $check, text: $text}
}

def failures []: nothing -> list<record> {
    let files = glob ($REPO | path join "FAILURES.*") | where { (ls $in | get 0.size) > 0B }
    if ($files | is-empty) { return [(report ok failures "no FAILURES.* left by dot apply")] }
    failures-reports $files
}

# Per FAILURES file: a head line with its count and where the detail is, then one line per failure group.
export def failures-reports [files: list<path>]: nothing -> list<record> {
    $files | each {|f|
        let entries = open --raw $f | lines | where ($it | str trim) != "" | each { str replace --all $"($REPO)/" "" }
        let groups = failures-group $entries
        let more = if ($groups | length) > $GROUPS_SHOWN { [$"  +(($groups | length) - $GROUPS_SHOWN) more in ($f | path basename)"] } else { [] }
        let from = $"($f | path basename) from (ls $f | get 0.modified | format date '%F %H:%M')"
        [$"($from), ($entries | length) failed; the detail: dot log --trace"] ++ ($groups | first $GROUPS_SHOWN | each { $"  ($in)" }) ++ $more
        | each { report FAIL failures $in }
    } | flatten
}

def hashes [dir: path, files: list<string>]: nothing -> list<string> {
    if ($files | is-empty) { return [] }
    cd $dir
    let summed = $files | str join "\u{0}" | ^xargs -0 sha256sum | complete
    # an unreadable file would otherwise drop out and count as differing
    if $summed.exit_code != 0 { error make {msg: $"($dir): ($summed.stderr | lines | first 3 | str join '; ')"} }
    $summed.stdout | lines
}

def config-pending []: nothing -> list<record> {
    if not ($SYSTEM_REPO | path exists) { return [] }
    let head = ^git -C $REPO rev-parse HEAD | str trim
    let source = file-trim ($SYSTEM_REPO | path join .source)
    let ours = system-files $REPO "--cached" | append (system-files $REPO "--others") | uniq
    let private = $ours | where ($it | str starts-with $SECRETS_PREFIX)
    let skip = $"./($SECRETS_PREFIX | str trim --right --char '/')"
    let theirs = cd $SYSTEM_REPO | ^find . -path $skip -prune -o -type f ! -name .source ! -name $SECRETS_DIGEST -printf '%P\n' | lines
    let both = try { {a: (hashes $REPO ($ours | where $it not-in $private)), b: (hashes $SYSTEM_REPO $theirs)} } catch {|e| {error: $e.msg} }
    if $both.error? != null { return [(report FAIL config $"cannot compare the root copy with the checkout: ($both.error)")] }
    let a = $both.a
    let b = $both.b
    let paths = ($a | where $it not-in $b) ++ ($b | where $it not-in $a) | each { str substring 66.. } | uniq
    # only what root acts on makes an apply due; a user-only module's file rides along with the next root entry
    let acted = try { root-acts-on $REPO (system-recorded) $paths | length } catch { $paths | length }
    let digest = file-trim ($SYSTEM_REPO | path join $SECRETS_DIGEST)
    let differing = [
        (if $acted > 0 { counted $acted file })
        (if (secrets-digest $REPO $private) != $digest { $SECRETS_PREFIX })
    ] | compact
    let waiting = ($paths | length) - $acted
    if ($differing | is-not-empty) {
        let at = $"the root copy is at ($source | str substring 0..6), the checkout at ($head | str substring 0..6)"
        [(report $TODO config $"dot apply pending: ($at) with ($differing | str join ' and ') differing")]
    } else if $waiting > 0 {
        [(report ok config $"the root copy matches the checkout in what root acts on; (counted $waiting 'user-only file') left for its next entry")]
    } else {
        [(report ok config "the root copy matches the checkout")]
    }
}

def reboot []: nothing -> list<record> {
    let built = try { open ($SYSTEM_STATE | path join $BOOT_BARRIER) | get built | into datetime } catch { null }
    if $built == null { return [] }
    let boot = open /proc/stat | lines | parse "btime {s}" | get 0.s | into int | $in * 1_000_000_000 | into datetime
    if $built > $boot {
        let built = $built | format date '%F %H:%M'
        [(report $TODO reboot $"reboot pending: the boot chain was rebuilt ($built), after this boot")]
    } else {
        [(report ok reboot "the running boot chain is the latest built")]
    }
}

def invariants []: nothing -> list<record> {
    invariants-load | where where == live | each {|i|
        let value = do { ^bash -c $i.probe } | complete | get stdout | str trim
        if $value == "n/a" { return null }
        if $value == $INVARIANT_PENDING {
            report note invariant $"($i.key) pending: its module waits on its packages, see the pending check"
        } else if $value == $i.want {
            report ok invariant $"($i.key)=($value)"
        } else {
            report FAIL invariant $"($i.key)=($value), expected ($i.want)"
        }
    } | compact
}

# Modules the last run of either layer left waiting on their packages, the network or a dependency (pending or failed):
# pending, no failure of their own. lines: pending-recorded's.
# A run that found DNS-over-TLS blocked adds the way through it.
export def pending-reports [lines: list<string>]: nothing -> list<record> {
    if ($lines | is-empty) { return [(report ok pending "no module waits on its packages, the network or a dependency")] }
    let blocked = $lines | any { str contains $DNS_TLS_BLOCKED }
    let escape = if $blocked {
        let way = dns-tls-escape --portal
        [(report note pending (if $way.command == null { $way.why } else { $"($way.why) ($way.command) && dot apply" }))]
    } else { [] }
    ($lines | each { report note pending $in }) ++ $escape
}

def apparmor []: nothing -> list<record> {
    if (file-trim /sys/module/apparmor/parameters/enabled) != "Y" {
        return [(report FAIL apparmor "apparmor is not enabled in the kernel")]
    }
    let rows = {|file|
        open --raw $file | lines | where not ($it | str starts-with "#") | parse --regex '^(?<name>\S+)\s+(?<mode>\S+)'
    }
    let enforced = do $rows $PROFILES_CONF | where ($it.mode | str starts-with enforce) | get name | uniq
    let backed = if ($APPARMOR_MANUAL | path exists) { do $rows $APPARMOR_MANUAL } else { [] }
        | where {|r| not ($r.mode | str starts-with enforce) and $r.name in $enforced }
        | each { $"($in.name):($in.mode)" }
    let live = glob /proc/[0-9]*/attr/apparmor/current | each {|f| file-trim $f }
        | where ($it | str ends-with " (complain)") | each { str replace " (complain)" "" } | uniq | sort
        | where $it in $enforced | each { $"($in):complain \(running\)" }
    let disabled = if ("/etc/apparmor.d/disable" | path exists) {
        # a link aa-install made to disable the stock stub of a profile apparmor.d or this repo replaces is no back-off
        ls /etc/apparmor.d/disable | get name | path basename | where $it in $enforced
            | where {|n| [$"($n).apparmor.d" $"($n).dotfiles"] | all {|f| not ("/etc/apparmor.d" | path join $f | path exists) } }
            | each { $"($in):disabled" }
    } else { [] }
    if ($backed ++ $live ++ $disabled | is-not-empty) {
        [(report FAIL apparmor $"backed off from enforce: (names-shown ($backed ++ $live ++ $disabled) $SHOWN_MAX); aa enforce <profile>")]
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
    let age = (date now) - ($entry.1 | into datetime) | $in / 1day | math floor
    let stale = $age > $SNAPSHOT_MAX_DAYS
    [(report (if $stale { "FAIL" } else { "ok" }) snapshot $"lsck0 snapshot ($pin) from ($day), ($age) days old(if $stale { ': dot sync' })")]
}

# missing: declared names not installed; recorded: root's "name first-asked" lines of names [lsck0] lacked; built: its
# database's time. A name asked for after the mirror's last build only waits for the next one (system-apply.nu
# mirror-awaited), so it is a note; any other missing name is a pending or failed install.
export def packages-reports [missing: list<string>, recorded: list<string>, built: any]: nothing -> list<record> {
    if ($missing | is-empty) { return [(report ok packages "every declared package installed")] }
    let awaited = awaited-names $recorded $built | where $it in $missing
    let pending = $missing | where $it not-in $awaited
    [
        (if ($pending | is-not-empty) { report $TODO packages $"dot apply --packages pending, declared but not installed: (names-shown $pending $SHOWN_MAX)" })
        (if ($awaited | is-not-empty) { report note packages $"not on the mirror yet, its next build brings them, then dot sync: (names-shown $awaited $SHOWN_MAX)" })
    ] | compact
}

# rows: the packages whose installed version sorts above the repo's ({name, repo, version, installed}). -Su never
# replaces those (a beta or git build above its release), so they stay behind every fix the repo ships.
export def stuck-reports [rows: list<record>]: nothing -> list<record> {
    if ($rows | is-empty) { return [(report ok stuck "no installed package sorts above its repo's version")] }
    let shown = $rows | each { $"($in.name) ($in.installed) > ($in.repo) ($in.version)" }
    [(report note stuck $"installed above the repo, -Su never replaces them: (names-shown $shown $SHOWN_MAX); sudo pacman -S <name>")]
}

# listing: `pacman -Sl`; the installed packages no repo carries at their installed version (a repo that has it, an own
# build beside an older one in extra, lists it unmarked), each with every repo's version.
export def stuck-candidates [listing: string]: nothing -> list<record> {
    let rows = $listing | lines
    let matching = $rows | where $it =~ ' \[installed\]$' | each { split row " " | get 1 }
    $rows | parse --regex $SL_DIFFERS | where name not-in $matching
}

def stuck []: nothing -> list<record> {
    if (which pacman | is-empty) { return [] }
    let candidates = stuck-candidates (^pacman -Sl | complete | get stdout)
    let newer = $candidates | where {|r| (^vercmp $r.installed $r.version | into int) > 0 }
    # stuck only when it sorts above every repo that carries it
    let names = $newer | get name | uniq | where {|n| ($candidates | where name == $n | length) == ($newer | where name == $n | length) }
    stuck-reports ($newer | where name in $names | uniq-by name)
}

# dumps: coredumpctl's records ({exe, sig}); one line per program, most crashes first.
export def cores-reports [dumps: list<record>]: nothing -> list<record> {
    if ($dumps | is-empty) { return [(report ok cores "no program dumped core in the last day")] }
    let shown = $dumps | group-by exe | items {|exe, runs| {exe: ($exe | path basename), count: ($runs | length)} }
        | sort-by count --reverse | each { $"($in.exe) x($in.count)" }
    [(report note cores $"dumped core in the last day: (names-shown $shown $SHOWN_MAX); coredumpctl info <exe>")]
}

def cores []: nothing -> list<record> {
    if (which coredumpctl | is-empty) { return [] }
    let out = ^coredumpctl --since $CORES_SINCE --json=short --no-pager list | complete
    # no dump in the window exits 1 with nothing on stdout
    let dumps = if ($out.stdout | str trim | is-empty) { [] } else { $out.stdout | from json }
    cores-reports $dumps
}

# A package group counts as installed. ctx: the system layer as the caller loaded it, null to load it here.
def packages [ctx: any]: nothing -> list<record> {
    if (which pacman | is-empty) { return [] }
    let ctx = if $ctx != null { $ctx } else { pipeline-load $REPO system }
    # profile-owner in a packages hook answers from the owners file only under the system layer
    let declared = with-env {DOT_LAYER: system} { modules-packages $REPO $ctx.modules $ctx.platform } | get pacman
    let unmet = with-env {LC_ALL: C} { do { ^pacman -Qq ...$declared } | complete }
        | get stderr | lines | parse "error: package '{name}' was not found" | get name
    # one query for every unmet name that may be a group: -Qg lists "<group> <member>" for those installed
    let groups = if ($unmet | is-empty) { [] } else { ^pacman -Qg ...$unmet | complete | get stdout | lines | each { split row " " | first } | uniq }
    let built = if ($LSCK0_DB | path exists) { ls $LSCK0_DB | get 0.modified } else { null }
    packages-reports ($unmet | where $it not-in $groups) (with-env {DOT_LAYER: system} { ledger-get $LEDGER_AWAITED }) $built
}

def firewall []: nothing -> list<record> {
    if (which nft | is-empty) or (platform-load $REPO).form_factor == "wsl" { return [] }
    let egress_enabled = succeeds systemctl -q is-enabled fw-egress.service
    let egress_down = $egress_enabled and not (succeeds systemctl -q is-active fw-egress.service)
    if not (succeeds systemctl -q is-active fw-lockdown.service fw-inbound.service) {
        [(report FAIL firewall "no inbound table loaded, fw-lockdown and fw-inbound are both inactive")]
    } else if $egress_down {
        [(report FAIL firewall "fw-egress is enabled but not active")]
    } else {
        [(report ok firewall "inbound and egress tables loaded")]
    }
}

export def units-owned []: list<string> -> list<string> { where $it !~ $UNIT_AD_HOC }

def units []: nothing -> list<record> {
    [system user] | each {|scope|
        let failed = ^systemctl $"--($scope)" list-units --failed --plain --no-legend | lines
            | each { split row " " | first } | units-owned
        let journal = if $scope == "user" { "journalctl --user -xeu <unit>" } else { "journalctl -xeu <unit>" }
        if ($failed | is-not-empty) {
            report FAIL units $"failed ($scope) units: (names-shown $failed $SHOWN_MAX); ($journal)"
        } else {
            report ok units $"no failed ($scope) unit"
        }
    }
}

# A user-hook whose last run failed: its unit's failed state ends with the boot, the journal's record does not, so a
# hook that failed headless during the install stays reported until a run succeeds.
def hooks []: nothing -> list<record> {
    let dir = xdg config systemd user
    let names = glob ($dir | path join "*.path") | where { open --raw $in | str contains $"Description=($HOOK_WATCH_PREFIX) " }
        | each { path parse | get stem }
    if ($names | is-empty) { return [] }
    let units = $names | each { [-u $"($in).service"] } | flatten
    let failed = ^journalctl --user --quiet --output json --output-fields USER_UNIT,MESSAGE ...$units --grep $HOOK_OUTCOME
        | complete | get stdout | lines | each { from json }
        | group-by USER_UNIT | items {|unit, runs| {unit: $unit, ok: ($runs | last | get MESSAGE | str starts-with "Finished")} }
        | where not ok | get unit
    if ($failed | is-empty) { return [(report ok hooks "every user hook's last run succeeded")] }
    [(report FAIL hooks $"last run failed: (names-shown $failed $SHOWN_MAX); journalctl --user -u <unit>, then systemctl --user start <unit>")]
}

# cmdline: the kernel's; missing: the token kinds this boot's systemd-cryptsetup found no token data for. A LUKS root
# whose rd.luks.options asks for no token unlocks by passphrase alone: a note with the enrol command.
export def luks-reports [cmdline: string, missing: list<string>]: nothing -> list<record> {
    let root = $cmdline | parse --regex $LUKS_ROOT | get --optional 0.uuid
    let options = $cmdline | parse --regex 'rd\.luks\.options=(?<o>\S+)' | get --optional 0.o | default "" | split row ","
    let asked = $LUKS_TOKENS | where {|t| $"($t | str lowercase)-device=auto" in $options }
    if $root != null and ($asked | is-empty) {
        return [(report note luks ($"the LUKS root unlocks by passphrase alone, no ($LUKS_TOKENS | str join ' or ') token enrolled: "
            + $"sudo systemd-cryptenroll --fido2-device=auto /dev/disk/by-uuid/($root) \(a touch\), or the TPM2 pin form "
            + "the system apply of base/boot/luks notes, then dot apply --system"))]
    }
    $missing | where $it in $asked | each {|t|
        report note luks ($"the LUKS root has no ($t) token, rd.luks.options asks for one: "
            + "the system apply of base/boot/luks notes the systemd-cryptenroll command")
    }
}

def luks []: nothing -> list<record> {
    let cmdline = open --raw /proc/cmdline
    let missing = if ($cmdline | str contains "-device=auto") {
        ^journalctl --boot --quiet --identifier systemd-cryptsetup --output cat --grep $LUKS_TOKEN_MISSING
        | complete | get stdout | parse --regex $LUKS_TOKEN_MISSING | get token | uniq
    } else { [] }
    luks-reports $cmdline $missing
}

# A crash record is retired by its command's next run that goes through (cli.nu guarded): one still there is unresolved.
export def crash-reports [files: list<path>]: nothing -> list<record> {
    let found = $files | each {|file|
        crash-list (crash-read $file) | each {|crash|
            report note crash $"dot ($crash.command) crashed in run ($crash.run) and has not gone through since: ($crash.error | lines | get --optional 0 | default ''); dot log ($crash.run) --trace, the whole error in ($file)"
        }
    } | flatten
    if ($found | is-empty) { [(report ok crash "no crash record left by a dot command")] } else { $found }
}

def crashes []: nothing -> list<record> {
    crash-reports ([(with-env {DOT_LAYER: user} { state-dir }) $SYSTEM_STATE] | uniq | each { crash-file ($in | path join runs) })
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

# the health checks, in order; one closure each so this list is their single source. system: the loaded system layer
# or null.
def checks [system: any]: nothing -> list<closure> {
    [
        {|| failures} {|| crashes} {|| config-pending} {|| pending-reports (pending-recorded)} {|| reboot} {|| invariants} {|| apparmor} {|| snapshot}
        {|| packages $system} {|| stuck} {|| firewall} {|| luks} {|| units} {|| hooks} {|| cores} {|| secrets} {|| preserved}
    ]
}

# The checks run side by side, they are independent reads; their records in check order.
def checks-run [system: any = null]: nothing -> list<record> {
    checks $system | par-each --keep-order {|c| do $c } | flatten
}

# Every check's records, unprinted, in check order; pending work reads FAIL here, as every reader of the level expects,
# and carries pending: true, so a reader that tells work waiting from a fault (core/alloy's metrics) still can.
# --system-ctx: the system layer, when the caller loaded it already.
export def doctor-checks [--system-ctx: record]: nothing -> list<record> {
    checks-run $system_ctx | each {|r|
        {level: (if $r.level == $TODO { "FAIL" } else { $r.level }), check: $r.check, text: $r.text, pending: ($r.level == $TODO)}
    }
}

# The lines of `dot status`: the checks by level, what needs action first, then the count of each level.
export def doctor-lines [records: list<record>]: nothing -> list<string> {
    let by_level = $LEVELS | each {|level| {level: $level, records: ($records | where level == $level)} }
    let lines = $by_level | get records | flatten | each {|r| $"($r.level | fill --width 4)  ($r.check | fill --width 10) ($r.text)" }
    $lines ++ ["" ($by_level | each { $"($in.records | length) ($in.level)" } | str join ", ")]
}

# Prints every check (--brief: only the FAIL and pending lines as "<check>: <text>"); true when one failed or is pending.
export def doctor-run [--brief]: nothing -> bool {
    let records = checks-run
    let failed = $records | where level in ["FAIL" $TODO]
    if $brief { $failed | each { print $"($in.check): ($in.text)" } | ignore } else { print (doctor-lines $records | str join "\n") }
    $failed | is-not-empty
}
