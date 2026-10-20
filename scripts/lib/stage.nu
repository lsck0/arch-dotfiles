use log.nu *

const STATE_DIR = "/var/lib/dotfiles-stage"
const KEY_FILE = "/etc/cryptsetup-keys.d/root.key"
const MKINITCPIO_DROPIN = "/etc/mkinitcpio.conf.d/dotfiles-stage.conf"
const SUDOERS_DROPIN = "/etc/sudoers.d/zz-dotfiles-stage"
const UNIT = "/etc/systemd/system/dotfiles-stage.service"
# on the ESP, readable without the disk password: the lsck0 iso refuses an unattended erase while it is there
const ESP_MARKER = "/boot/dotfiles-stage-in-progress"
# agetty shows it above the console login, where a stalled chain is seen
const ISSUE = "/etc/issue.d/dotfiles-stage.issue"
const DISARM_TRIES = 3
const DISARM_BACKOFF = 5sec
const EFIVARS = "/sys/firmware/efi/efivars"
const EFI_GLOBAL = "8be4df61-93ca-11d2-aa0d-00e098032b8c"
# BootNext's attributes: non-volatile, boot service and runtime access
const EFI_ATTRS_NV_BS_RT = 0x[07 00 00 00]
const INSTALL_ATTEMPTS_MAX = 3
# dot apply --packages' code for an abort, as opposed to a finished run that logged failures
const INSTALL_EXIT_ABORTED = 2
# cryptsetup's "no key available": a crash between the kill and the rm already removed the slot
const CRYPTSETUP_NO_KEY = 2

def note [message: string]: nothing -> nothing {
    log-info $message
    $"(date now | format date '%+') ($message)\n" | ^sudo tee -a ($STATE_DIR | path join log) | ignore
}

def luks-device []: nothing -> string {
    let file = $STATE_DIR | path join luks-device
    if ($file | path exists) { open --raw $file | str trim } else { "" }
}

# idempotent; sudo test because cryptsetup-keys.d is root-only
def disarm []: nothing -> bool {
    let device = luks-device
    let armed = (^sudo test -f $KEY_FILE | complete).exit_code == 0
    if $device == "" {
        if $armed { return false }
        ^sudo rm -f $MKINITCPIO_DROPIN
        return true
    }
    if $armed {
        let status = (^sudo cryptsetup open --test-passphrase --key-file $KEY_FILE $device | complete).exit_code
        if $status == 0 {
            if (^sudo cryptsetup luksRemoveKey $device $KEY_FILE | complete).exit_code != 0 { return false }
        } else if $status != $CRYPTSETUP_NO_KEY {
            return false
        }
        ^sudo rm -f $KEY_FILE
    }
    ^sudo rm -f $MKINITCPIO_DROPIN
    true
}

# the next boot is this one's entry again: a stick left in, booted first, would rerun its unattended install
def boot-next-here []: nothing -> nothing {
    let current = $EFIVARS | path join $"BootCurrent-($EFI_GLOBAL)"
    if not ($current | path exists) { return }
    let entry = open --raw $current | into binary | bytes at 4..5
    let next = $EFIVARS | path join $"BootNext-($EFI_GLOBAL)"
    # efivarfs files are immutable; one write of attributes and entry, as dd's single block
    if ($next | path exists) { ^sudo chattr -i $next | complete | ignore }
    let r = $EFI_ATTRS_NV_BS_RT | bytes add --end $entry | ^sudo dd $"of=($next)" bs=6 count=1 status=none | complete
    if $r.exit_code != 0 { note $"BootNext not set: ($r.stderr | str trim)" }
}

def stage-reboot []: nothing -> nothing {
    boot-next-here
    ^sudo systemctl reboot
}

export def stage-run [repo: path]: nothing -> nothing {
    let stage = open --raw ($STATE_DIR | path join next) | str trim
    mut next = match $stage {
        "install" => "config"
        "config" => ""
        _ => { error make {msg: $"unknown stage '($stage)' in ($STATE_DIR)/next"} }
    }
    if $stage == "config" {
        mut tries = 1
        while not (disarm) {
            if $tries >= $DISARM_TRIES {
                # the unit runs again next boot; the console says why the chain stopped meanwhile
                let message = $"dotfiles install chain stopped: the temporary disk key is still in place, see ($STATE_DIR)/log"
                note $"disarm failed ($tries) times, retrying next boot"
                ^sudo mkdir -p ($ISSUE | path dirname)
                $"\n($message)\n\n" | ^sudo tee $ISSUE | ignore
                exit 1
            }
            sleep $DISARM_BACKOFF
            $tries += 1
        }
        ^sudo rm -f $ISSUE
    }
    note $"($stage): start"
    if $stage == "config" {
        # best effort: a migration bookkeeping failure must not strand the sudo drop-in and the keyfile
        try {
            ^nu --no-config-file ($repo | path join scripts lib internal.nu) migrate --baseline
            ^sudo ($"/var/lib/dotfiles/repo/scripts/lib/system-apply.nu") migrate --baseline
        } catch {|e| note $"migrate --baseline failed: ($e.msg)" }
    }
    # stdout stays the tty, so dot re-execs under script and pacman draws its bars
    let args = if $stage == "install" { [apply --packages] } else { [apply] }
    let status = try { "" | ^nu --no-config-file ($repo | path join scripts dot.nu) ...$args; 0 } catch {|e| $e.exit_code? | default 1 }
    note (if $status == 0 { $"($stage): ok" } else { $"($stage): failed, see ($stage).log" })
    if $stage == "install" and $status == $INSTALL_EXIT_ABORTED {
        let attempts = (try { open --raw ($STATE_DIR | path join install-attempts) | into int } catch { 0 }) + 1
        $"($attempts)\n" | ^sudo tee ($STATE_DIR | path join install-attempts) | ignore
        if $attempts < $INSTALL_ATTEMPTS_MAX {
            note $"install: aborted, attempt ($attempts)/($INSTALL_ATTEMPTS_MAX), retrying next boot"
            $next = "install"
        } else {
            note $"install: aborted ($attempts) times, going on with config; run dot apply --packages later"
        }
    }
    note "rebooting"
    if ($next | is-not-empty) {
        $"($next)\n" | ^sudo tee ($STATE_DIR | path join next) | ignore
        stage-reboot
        return
    }
    # a trim lets the ssd drop the keyfile's old ESP blocks; only a reencrypt rotates the volume key
    ^sudo fstrim /boot | complete | ignore
    if (luks-device) != "" {
        note $"to rotate the disk's volume key \(slow, runs online\): sudo cryptsetup reencrypt (luks-device)"
    }
    boot-next-here
    # one root shell, the drop-in first: after its rm there is no passwordless sudo left, and a crash past it leaves none
    ^sudo sh -c $"rm -f ($SUDOERS_DROPIN); systemctl disable dotfiles-stage.service; rm -f ($UNIT) ($STATE_DIR)/next ($ESP_MARKER); systemctl reboot"
}
