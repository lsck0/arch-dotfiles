# One install stage per boot: install, then config, which disarms the chain and reboots.

use log.nu *
use state.nu [EXIT_PENDING INSTALL_PASS_FILE SYSTEM_REPO CONFIG_ISSUE SECRETS_ISSUE]
use secrets.nu [secret-is-plaintext OWNER_WITNESS]
use system.nu [ENTRY]
use profile.nu [profile-has]
use cause.nu [failures-group ONLINE_ESCAPE]

const REPO = path self ../..
const WITNESS = $REPO | path join $OWNER_WITNESS
export const STAGE_STATE_DIR = "/var/lib/dotfiles-stage"
export const STAGE_KEY_FILE = "/etc/cryptsetup-keys.d/root.key"
export const STAGE_MKINITCPIO_DROPIN = "/etc/mkinitcpio.conf.d/dotfiles-stage.conf"
export const STAGE_SUDOERS_DROPIN = "/etc/sudoers.d/zz-dotfiles-stage"
export const STAGE_UNIT = "/etc/systemd/system/dotfiles-stage.service"
export const STAGE_ESP_MARKER = "/boot/dotfiles-stage-in-progress"
# the marker's text while the chain runs, and its first line once the chain stopped and was disarmed
export const STAGE_ESP_RUNNING = "a dotfiles install chain runs from this disk; the lsck0 iso will not erase it unattended"
export const STAGE_ESP_STOPPED = "stopped"
const ISSUE = "/etc/issue.d/dotfiles-stage.issue"
# a chain stopped before config and disarmed: what the console resumes it with
export const STAGE_NEXT = $STAGE_STATE_DIR | path join next
# the encrypted root the stage key opens, absent for an unencrypted install
export const STAGE_LUKS_DEVICE = $STAGE_STATE_DIR | path join luks-device
export const STAGE_STOPPED = $STAGE_STATE_DIR | path join stopped
const ATTEMPTS = $STAGE_STATE_DIR | path join install-attempts
export const STAGE_RESUME = "dot internal stage"
const STAGE_STOP = "stop"
const DISARM_TRIES = 3
const DISARM_BACKOFF = 5sec
const EFIVARS = "/sys/firmware/efi/efivars"
const EFI_GLOBAL = "8be4df61-93ca-11d2-aa0d-00e098032b8c"
const EFI_ATTRS_NV_BS_RT = 0x[07 00 00 00]
const INSTALL_ATTEMPTS_MAX = 3
# the wait before the reboot that retries an install pass, times the attempt
const INSTALL_BACKOFF = 1min
const INSTALL_FAILURES_SHOWN = 5
const FAILURES_INSTALL = "FAILURES.install"
const FAILURES_CONFIG = "FAILURES.config"
const CRYPTSETUP_NO_KEY = 2
# a watcher's url (dot test, BOOTSTRAP_REPORT): the stages beacon to it, the chain's end reports to it
export const STAGE_REPORT = $STAGE_STATE_DIR | path join report
# the vm's virtio channel to the watcher, past any guest firewall (tor lockdown); stage-report.nu sends its logs there
export const REPORT_CHANNEL = "/dev/virtio-ports/lsck0.report"
# as root, from the root copy: sh -c's $1 the copy, $2 the user, $3 the checkout, $4 set when the chain stopped
const REPORT_RUN = 'nu --no-config-file "$1/scripts/lib/stage-report.nu" "$2" "$3" ${4:+--stopped}; '
# as root: no stage left to run, no unit to start one, sudo asking for the password again; the attempts go with it, so
# a resume (stage-rearm) starts counting from zero
const STOP_DISARM = $"rm -f ($STAGE_NEXT) ($ATTEMPTS); echo install > ($STAGE_STOPPED); systemctl disable dotfiles-stage.service; rm -f ($STAGE_SUDOERS_DROPIN); "
# as root: the ESP marker of a chain disarmed for good, the disk key gone too
const STOP_MARK = $"echo ($STAGE_ESP_STOPPED) > ($STAGE_ESP_MARKER); "
# as root: sh -c's $1 the sudoers rule, $2 the drop-in, $3 the next stage's file, $4 the stopped marker, $5 its banner,
# $6 the ESP marker, $7 its running text
const STAGE_REARM = 'set -e; printf "%s" "$1" > "$2.new"; chmod 440 "$2.new"; visudo -cqf "$2.new"; mv -f "$2.new" "$2"; echo install > "$3"; rm -f "$4" "$5"; echo "$7" > "$6"; systemctl enable dotfiles-stage.service'

def note [message: string]: nothing -> nothing {
    log-info $message
    $"(date now | format date '%+') ($message)\n" | ^sudo tee -a ($STAGE_STATE_DIR | path join log) | ignore
}

# portmaster blocks the watcher; only a test install has a report url
def watcher-unblock []: nothing -> nothing {
    if ($STAGE_REPORT | path exists) { do { ^sudo systemctl stop portmaster.service } | complete | ignore }
}

# A beacon to the watcher at url, and over the vm's channel when there is one; --sudo when the channel is root's.
export def report-beacon-send [url: string, tag: string, --sudo]: nothing -> nothing {
    ^curl -s -m 10 $"($url)/beacon/($tag)" | complete | ignore
    if not ($REPORT_CHANNEL | path exists) { return }
    let line = $"beacon ($tag)\n"
    if $sudo { $line | ^sudo tee $REPORT_CHANNEL | complete | ignore } else { $line | ^tee $REPORT_CHANNEL | complete | ignore }
}

def report-beacon [tag: string]: nothing -> nothing {
    if not ($STAGE_REPORT | path exists) { return }
    watcher-unblock
    report-beacon-send (open --raw $STAGE_REPORT | str trim) $tag --sudo
}

def luks-device []: nothing -> string {
    if ($STAGE_LUKS_DEVICE | path exists) { open --raw $STAGE_LUKS_DEVICE | str trim } else { "" }
}

def disarm []: nothing -> bool {
    let device = luks-device
    let armed = (^sudo test -f $STAGE_KEY_FILE | complete).exit_code == 0
    if $device == "" {
        if $armed { return false }
        ^sudo rm -f $STAGE_MKINITCPIO_DROPIN
        return true
    }
    if $armed {
        let status = (^sudo cryptsetup open --test-passphrase --key-file $STAGE_KEY_FILE $device | complete).exit_code
        if $status == 0 {
            if (^sudo cryptsetup luksRemoveKey $device $STAGE_KEY_FILE | complete).exit_code != 0 { return false }
        } else if $status != $CRYPTSETUP_NO_KEY {
            return false
        }
        ^sudo rm -f $STAGE_KEY_FILE
    }
    ^sudo rm -f $STAGE_MKINITCPIO_DROPIN
    true
}

# The stage chain's passwordless sudo for its user, as bootstrap arms it.
export def stage-sudoers [user: string]: nothing -> string {
    $"($user) ALL=\(ALL:ALL\) NOPASSWD: ALL\nDefaults:($user) verifypw=any\n"
}

# disarm, retried: a device busy for a moment is no reason to keep the key
def disarm-retried []: nothing -> bool {
    for attempt in 1..$DISARM_TRIES {
        if (disarm) { return true }
        if $attempt < $DISARM_TRIES { sleep $DISARM_BACKOFF }
    }
    false
}

# What follows a stage: config once an install pass went through (a partial one too, however dot exited), else the
# install again after a reboot, or the stop once INSTALL_ATTEMPTS_MAX passes did not; config ends the chain.
# attempts counts the install passes run so far, this one included.
export def stage-next [stage: string, status: int, passed: bool, attempts: int]: nothing -> record {
    let ok = $status in [0 $EXIT_PENDING]
    if $stage == "config" { return {ok: $ok, next: ""} }
    if $passed { return {ok: $ok, next: "config"} }
    {ok: $ok, next: (if $attempts >= $INSTALL_ATTEMPTS_MAX { $STAGE_STOP } else { "install" })}
}

# The login banner of a chain stopped before config: what failed, that it is disarmed, how to get online and resume.
export def install-banner [attempts: int, failures: list<string>, --key-kept]: nothing -> string {
    let shown = failures-group $failures | first $INSTALL_FAILURES_SHOWN | each { $"  ($in)" }
    let disarmed = if $key_kept {
        "The temporary disk key could not be removed: the disk still unlocks without its passphrase. sudo asks again."
    } else {
        "The chain is disarmed: the disk asks for its passphrase again, sudo for the password."
    }
    [
        $"dotfiles install chain stopped: the package install failed ($attempts) times, so config did not run."
        ...(if ($shown | is-empty) { [] } else { ["What failed:" ...$shown] })
        $disarmed
        "Offline or on an untrusted network? Log in and get online with:"
        $"  ($ONLINE_ESCAPE)"
        "then resume the chain from here (sudo asks once, each boot of it asks for the disk passphrase):"
        $"  ($STAGE_RESUME)"
        $"Logs: ($STAGE_STATE_DIR)/log and install.log in the checkout."
    ] | str join "\n"
}

# The login banner of a chain that ran to its end with a failed config stage: it is disarmed like a clean one, so only
# this says some modules were not applied.
export def config-banner [failures: list<string>]: nothing -> string {
    let shown = failures-group $failures | first $INSTALL_FAILURES_SHOWN | each { $"  ($in)" }
    [
        "dotfiles install chain finished, but its config stage failed: some modules are not applied."
        ...(if ($shown | is-empty) { [] } else { ["What failed:" ...$shown] })
        "Fix what failed, then run `dot apply` at a terminal; this banner clears after one with no failure."
        $"Logs: config.log and ($FAILURES_CONFIG) in the checkout, `dot status`."
    ] | str join "\n"
}

# A chain stopped before config disarms what leaves the machine open: the stage key slot and keyfile (the disk
# unlocks by itself), the passwordless sudoers drop-in, and the unit with its next stage. The trade-off: a reboot no
# longer retries on its own; a person at the console resumes with STAGE_RESUME, sudo asking once and each boot of the
# rest of the chain asking for the disk passphrase, since the key is not armed again.
def install-stop [repo: path, attempts: int]: nothing -> nothing {
    let failures = try { open --raw ($repo | path join $FAILURES_INSTALL) | lines } catch { [] }
    let key_kept = not (disarm-retried)
    note $"install: failed ($attempts) times, the chain stops before config and is disarmed(if $key_kept { ' but for its disk key' } else { '' }), see the login banner"
    ^sudo mkdir -p ($ISSUE | path dirname)
    $"\n(install-banner $attempts $failures --key-kept=$key_kept)\n\n" | ^sudo tee $ISSUE | ignore
    # a stopped chain uploads its logs too, the banner among them, and the report sends the verdict; the root copy
    # exists once the install ran as root
    let report = if ($STAGE_REPORT | path exists) and ($SYSTEM_REPO | path join scripts lib stage-report.nu | path exists) { $REPORT_RUN } else {
        report-beacon chain-fail
        ""
    }
    # one root shell: sudo stops being passwordless within it, and the report sees the disarmed chain
    # a kept disk key still unlocks the disk: the marker keeps calling the chain running, never safely stopped
    let mark = if $key_kept { "" } else { $STOP_MARK }
    ^sudo sh -c $"($STOP_DISARM)($mark)($report)" sh $SYSTEM_REPO $env.USER $repo stopped | complete | ignore
}

# A stopped chain resumed at the console: sudo asks once, then the drop-in, the unit and the install stage are back.
# The disk key is not, so each boot left in the chain asks for the passphrase.
def stage-rearm []: nothing -> nothing {
    if not (is-terminal --stdin) { error make {msg: $"the install chain stopped and is disarmed; resume it at the console: ($STAGE_RESUME)"} }
    ^sudo sh -c $STAGE_REARM sh (stage-sudoers $env.USER) $STAGE_SUDOERS_DROPIN $STAGE_NEXT $STAGE_STOPPED $ISSUE $STAGE_ESP_MARKER $STAGE_ESP_RUNNING
    note "install: resumed at the console, the chain armed again without its disk key"
}

def boot-next-here []: nothing -> nothing {
    let current = $EFIVARS | path join $"BootCurrent-($EFI_GLOBAL)"
    if not ($current | path exists) { return }
    let entry = open --raw $current | into binary | bytes at 4..5
    let next = $EFIVARS | path join $"BootNext-($EFI_GLOBAL)"
    if ($next | path exists) { ^sudo chattr -i $next | complete | ignore }
    # efivarfs files are immutable; attributes and entry go in one write, as dd's single block
    let r = $EFI_ATTRS_NV_BS_RT | bytes add --end $entry | ^sudo dd $"of=($next)" bs=6 count=1 status=none | complete
    if $r.exit_code != 0 { note $"BootNext not set: ($r.stderr | str trim)" }
}

def stage-reboot []: nothing -> nothing {
    boot-next-here
    ^sudo systemctl reboot
}

# Runs the stage named in the state dir's `next`, then arms the following one or disarms the chain.
export def stage-run [repo: path]: nothing -> nothing {
    if not ($STAGE_NEXT | path exists) and ($STAGE_STOPPED | path exists) { stage-rearm }
    if not ($STAGE_NEXT | path exists) { error make {msg: "the install chain already finished, no stage left to run"} }
    let stage = open --raw $STAGE_NEXT | str trim
    if $stage not-in [install config] { error make {msg: $"unknown stage '($stage)' in ($STAGE_NEXT)"} }
    if $stage == "config" {
        if not (disarm-retried) {
            let message = $"dotfiles install chain stopped: the temporary disk key is still in place, see ($STAGE_STATE_DIR)/log"
            note $"disarm failed ($DISARM_TRIES) times, retrying next boot"
            ^sudo mkdir -p ($ISSUE | path dirname)
            $"\n($message)\n\n" | ^sudo tee $ISSUE | ignore
            # a watcher would otherwise poll until its chain timeout
            report-beacon chain-fail
            exit 1
        }
        ^sudo rm -f $ISSUE
    }
    note $"($stage): start"
    if $stage == "config" {
        try {
            ^nu --no-config-file ($repo | path join scripts lib internal.nu) migrate --baseline
            ^sudo ($SYSTEM_REPO | path join $ENTRY) migrate --baseline
        } catch {|e| note $"migrate --baseline failed: ($e.msg)" }
    }
    let args = if $stage == "install" { [apply --packages] } else { [apply] }
    # counted before the pass, so one that dies with the machine still counts towards the stop
    let attempts = (try { open --raw $ATTEMPTS | into int } catch { 0 }) | if $stage == "install" { $in + 1 } else { $in }
    if $stage == "install" {
        if $attempts > $INSTALL_ATTEMPTS_MAX {
            install-stop $repo ($attempts - 1)
            exit 1
        }
        $"($attempts)\n" | ^sudo tee $ATTEMPTS | ignore
        ^sudo rm -f $INSTALL_PASS_FILE
    }
    let status = try { "" | ^nu --no-config-file ($repo | path join scripts dot.nu) ...$args; 0 } catch {|e| $e.exit_code? | default 1 }
    # config runs after a partial pass, its modules without packages pending; after no pass it would disarm a bare system
    let decided = stage-next $stage $status ($INSTALL_PASS_FILE | path exists) $attempts
    # pending modules wait on packages a later dot apply --packages brings; the stage itself went through
    note (if $decided.ok { $"($stage): ok(if $status == $EXIT_PENDING { ', some modules pending, see dot status' })" } else { $"($stage): failed, see ($stage).log" })
    report-beacon $"($stage)-(if $decided.ok { 'ok' } else { 'failed' })"
    if $decided.next == $STAGE_STOP {
        install-stop $repo $attempts
        exit 1
    }
    if $stage == "install" and $decided.next == "install" {
        let wait = $INSTALL_BACKOFF * $attempts
        note $"install: the package pass did not go through, attempt ($attempts)/($INSTALL_ATTEMPTS_MAX), retrying after a reboot in ($wait)"
        sleep $wait
    }
    note "rebooting"
    let next = $decided.next
    if ($next | is-not-empty) {
        $"($next)\n" | ^sudo tee $STAGE_NEXT | ignore
        stage-reboot
        return
    }
    ^sudo fstrim /boot | complete | ignore
    if not $decided.ok {
        let failures = try { open --raw ($repo | path join $FAILURES_CONFIG) | lines | where ($it | str trim) != "" } catch { [] }
        note "config: failed, the chain ends disarmed, see the login banner"
        ^sudo mkdir -p ($CONFIG_ISSUE | path dirname)
        $"\n(config-banner $failures)\n\n" | ^sudo tee $CONFIG_ISSUE | ignore
    }
    if (luks-device) != "" {
        note $"to rotate the disk's volume key \(slow, runs online\): sudo cryptsetup reencrypt (luks-device)"
    }
    if (profile-has secrets) and not (secret-is-plaintext $WITNESS) {
        let message = "dotfiles secrets are still locked: the YubiKey was not recognized during the install chain.\nPlug it in and run `dot apply` (or `dot secrets unlock`) to pull it in; this banner clears itself once unlocked."
        note "secrets still locked, see the login banner"
        ^sudo mkdir -p ($SECRETS_ISSUE | path dirname)
        $"\n($message)\n\n" | ^sudo tee $SECRETS_ISSUE | ignore
    }
    boot-next-here
    # the report runs as root from the root copy, after the chain is disarmed, so it sees the finished system
    let report = if ($STAGE_REPORT | path exists) { $REPORT_RUN } else { "" }
    let disarm = $"rm -f ($STAGE_SUDOERS_DROPIN); systemctl disable dotfiles-stage.service; rm -f ($STAGE_UNIT) ($STAGE_NEXT) ($STAGE_ESP_MARKER); "
    ^sudo sh -c $"($disarm)($report)systemctl reboot" sh $SYSTEM_REPO $env.USER $repo
}
