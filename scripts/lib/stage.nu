# dot stage: one unattended stage per boot of the install chain, install then config; the config stage disarms the
# temporary keyfile first, and the chain retires itself and its sudo drop-in at the end

use log.nu *

const STATE_DIR = "/var/lib/dotfiles-stage"
const KEY_FILE = "/etc/cryptsetup-keys.d/root.key"
const MKINITCPIO_DROPIN = "/etc/mkinitcpio.conf.d/dotfiles-stage.conf"
const SUDOERS_DROPIN = "/etc/sudoers.d/zz-dotfiles-stage"
const UNIT = "/etc/systemd/system/dotfiles-stage.service"
# a few boots cover a flaky network or mirror, a real bug would loop forever
const INSTALL_ATTEMPTS_MAX = 3
# dot install's code for an abort, as opposed to a finished run that logged failures
const INSTALL_EXIT_ABORTED = 2
# cryptsetup's "no key available": a crash between the kill and the rm already removed the slot
const CRYPTSETUP_NO_KEY = 2

def note [message: string]: nothing -> nothing {
    log-info $message
    $"(date now | format date '%+') ($message)\n" | ^sudo tee -a ($STATE_DIR | path join log) | ignore
}

# idempotent; config's boot barrier rebuilds the initramfs without the keyfile, a stale one opens nothing once the slot
# is gone. sudo test because cryptsetup-keys.d is root-only
def disarm []: nothing -> bool {
    let device = open --raw ($STATE_DIR | path join luks-device) | str trim
    if (^sudo test -f $KEY_FILE | complete).exit_code == 0 {
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

export def stage-run [repo: path]: nothing -> nothing {
    let stage = open --raw ($STATE_DIR | path join next) | str trim
    mut next = match $stage {
        "install" => "config"
        "config" => ""
        _ => { error make {msg: $"unknown stage '($stage)' in ($STATE_DIR)/next"} }
    }
    # the keyfile only exists to boot into this stage, so nothing below can leave it armed
    if $stage == "config" and not (disarm) {
        note "disarm failed, the temporary keyfile is still in place"
        exit 1
    }
    note $"($stage): start"
    if $stage == "config" {
        # a fresh install is already at the current generation: every migration counts as run, none runs
        ^nu --no-config-file ($repo | path join scripts dot.nu) migrate --baseline
        ^sudo ($"/var/lib/dotfiles/repo/scripts/lib/system-apply.nu") migrate --baseline
    }
    # stdout stays the tty, so dot re-execs under script and pacman draws its bars
    let verb = if $stage == "install" { "install" } else { "apply" }
    let status = try { "" | ^nu --no-config-file ($repo | path join scripts dot.nu) $verb; 0 } catch {|e| $e.exit_code? | default 1 }
    note (if $status == 0 { $"($stage): ok" } else { $"($stage): failed, see ($stage).log" })
    if $stage == "install" and $status == $INSTALL_EXIT_ABORTED {
        let attempts = (try { open --raw ($STATE_DIR | path join install-attempts) | into int } catch { 0 }) + 1
        $"($attempts)\n" | ^sudo tee ($STATE_DIR | path join install-attempts) | ignore
        if $attempts < $INSTALL_ATTEMPTS_MAX {
            note $"install: aborted, attempt ($attempts)/($INSTALL_ATTEMPTS_MAX), retrying next boot"
            $next = "install"
        } else {
            note $"install: aborted ($attempts) times, moving on to config; rerun dot install by hand"
        }
    }
    note "rebooting"
    if ($next | is-not-empty) {
        $"($next)\n" | ^sudo tee ($STATE_DIR | path join next) | ignore
        ^sudo systemctl reboot
        return
    }
    # the keyfile sat in initramfs images on the unencrypted ESP: a trim lets the ssd drop the old blocks; whoever copied
    # the ESP and the header meanwhile still derives the volume key, only a reencrypt rotates it
    ^sudo fstrim /boot | complete | ignore
    note $"volume key unchanged since bootstrap; to rotate it \(online, slow\): sudo cryptsetup reencrypt (open --raw ($STATE_DIR | path join luks-device) | str trim)"
    # one sudo call: after the rm there is no passwordless sudo left to reboot with
    ^sudo systemctl disable dotfiles-stage.service
    ^sudo sh -c $"rm -f ($UNIT) ($STATE_DIR)/next ($SUDOERS_DROPIN) && systemctl reboot"
}
