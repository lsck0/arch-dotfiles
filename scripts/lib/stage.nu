# One install stage per boot: install, then config, which disarms the chain and reboots.

use log.nu *
use state.nu [EXIT_ABORTED SYSTEM_REPO]
use secrets.nu [secret-is-plaintext OWNER_WITNESS]
use system.nu [ENTRY]
use profile.nu [profile-has]

const REPO = path self ../..
const WITNESS = $REPO | path join $OWNER_WITNESS
export const STAGE_STATE_DIR = "/var/lib/dotfiles-stage"
export const STAGE_KEY_FILE = "/etc/cryptsetup-keys.d/root.key"
const MKINITCPIO_DROPIN = "/etc/mkinitcpio.conf.d/dotfiles-stage.conf"
const SUDOERS_DROPIN = "/etc/sudoers.d/zz-dotfiles-stage"
const UNIT = "/etc/systemd/system/dotfiles-stage.service"
export const STAGE_ESP_MARKER = "/boot/dotfiles-stage-in-progress"
const ISSUE = "/etc/issue.d/dotfiles-stage.issue"
const SECRETS_ISSUE = "/etc/issue.d/dotfiles-secrets.issue"
const DISARM_TRIES = 3
const DISARM_BACKOFF = 5sec
const EFIVARS = "/sys/firmware/efi/efivars"
const EFI_GLOBAL = "8be4df61-93ca-11d2-aa0d-00e098032b8c"
const EFI_ATTRS_NV_BS_RT = 0x[07 00 00 00]
const INSTALL_ATTEMPTS_MAX = 3
const CRYPTSETUP_NO_KEY = 2
# a watcher's url (dot test, BOOTSTRAP_REPORT): the stages beacon to it, the chain's end reports to it
const REPORT = ($STAGE_STATE_DIR | path join report)

def note [message: string]: nothing -> nothing {
    log-info $message
    $"(date now | format date '%+') ($message)\n" | ^sudo tee -a ($STAGE_STATE_DIR | path join log) | ignore
}

# portmaster blocks the watcher; only a test install has a report url
def watcher-unblock []: nothing -> nothing {
    if ($REPORT | path exists) { do { ^sudo systemctl stop portmaster.service } | complete | ignore }
}

def report-beacon [tag: string]: nothing -> nothing {
    if not ($REPORT | path exists) { return }
    watcher-unblock
    ^curl -s -m 10 $"(open --raw $REPORT | str trim)/beacon/($tag)" | complete | ignore
}

def luks-device []: nothing -> string {
    let file = $STAGE_STATE_DIR | path join luks-device
    if ($file | path exists) { open --raw $file | str trim } else { "" }
}

def disarm []: nothing -> bool {
    let device = luks-device
    let armed = (^sudo test -f $STAGE_KEY_FILE | complete).exit_code == 0
    if $device == "" {
        if $armed { return false }
        ^sudo rm -f $MKINITCPIO_DROPIN
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
    ^sudo rm -f $MKINITCPIO_DROPIN
    true
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
    let stage = open --raw ($STAGE_STATE_DIR | path join next) | str trim
    mut next = match $stage {
        "install" => "config"
        "config" => ""
        _ => { error make {msg: $"unknown stage '($stage)' in ($STAGE_STATE_DIR)/next"} }
    }
    if $stage == "config" {
        mut tries = 1
        while not (disarm) {
            if $tries >= $DISARM_TRIES {
                let message = $"dotfiles install chain stopped: the temporary disk key is still in place, see ($STAGE_STATE_DIR)/log"
                note $"disarm failed ($tries) times, retrying next boot"
                ^sudo mkdir -p ($ISSUE | path dirname)
                $"\n($message)\n\n" | ^sudo tee $ISSUE | ignore
                # a watcher would otherwise poll until its chain timeout
                report-beacon chain-fail
                exit 1
            }
            sleep $DISARM_BACKOFF
            $tries += 1
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
    let status = try { "" | ^nu --no-config-file ($repo | path join scripts dot.nu) ...$args; 0 } catch {|e| $e.exit_code? | default 1 }
    note (if $status == 0 { $"($stage): ok" } else { $"($stage): failed, see ($stage).log" })
    report-beacon $"($stage)-(if $status == 0 { 'ok' } else { 'failed' })"
    if $stage == "install" and $status == $EXIT_ABORTED {
        let attempts = (try { open --raw ($STAGE_STATE_DIR | path join install-attempts) | into int } catch { 0 }) + 1
        $"($attempts)\n" | ^sudo tee ($STAGE_STATE_DIR | path join install-attempts) | ignore
        if $attempts < $INSTALL_ATTEMPTS_MAX {
            note $"install: aborted, attempt ($attempts)/($INSTALL_ATTEMPTS_MAX), retrying next boot"
            $next = "install"
        } else {
            note $"install: aborted ($attempts) times, going on with config; run dot apply --packages later"
        }
    }
    note "rebooting"
    if ($next | is-not-empty) {
        $"($next)\n" | ^sudo tee ($STAGE_STATE_DIR | path join next) | ignore
        stage-reboot
        return
    }
    ^sudo fstrim /boot | complete | ignore
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
    let report = if ($REPORT | path exists) { 'nu --no-config-file "$1/scripts/lib/stage-report.nu" "$2" "$3"; ' } else { "" }
    let disarm = $"rm -f ($SUDOERS_DROPIN); systemctl disable dotfiles-stage.service; rm -f ($UNIT) ($STAGE_STATE_DIR)/next ($STAGE_ESP_MARKER); "
    ^sudo sh -c $"($disarm)($report)systemctl reboot" sh $SYSTEM_REPO $env.USER $repo
}
