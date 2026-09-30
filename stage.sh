#!/usr/bin/env bash
# Runs the install chain unattended, one stage per boot. bootstrap.sh arms it: dotfiles-stage.service
# starts this script as the user after every boot while /var/lib/dotfiles-stage/next exists, with a
# temporary LUKS keyfile in the initramfs and passwordless sudo so nothing waits for input.
#
#     boot 1: install.sh    packages
#     boot 2: config.sh     links, then disarm: keyslot and keyfile gone, sudo asks again, service removed
#     boot 3: normal passphrase prompt and login
#
# A failed stage is logged to /var/lib/dotfiles-stage/log and the chain moves on, so it always ends
# disarmed; rerun the failed script by hand afterwards.

set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")" || exit 1

STATE_DIR=/var/lib/dotfiles-stage
KEY_FILE=/etc/cryptsetup-keys.d/root.key
MKINITCPIO_DROPIN=/etc/mkinitcpio.conf.d/dotfiles-stage.conf
SUDOERS_DROPIN=/etc/sudoers.d/zz-dotfiles-stage
UNIT=/etc/systemd/system/dotfiles-stage.service

log() { echo "$(date -Is) $*" | sudo tee -a "$STATE_DIR/log"; }

# keyslot first: once it is gone the keyfile on the ESP opens nothing
disarm() {
    local device
    device=$(<"$STATE_DIR/luks-device")
    sudo cryptsetup luksRemoveKey "$device" "$KEY_FILE" || return 1
    sudo rm -f "$KEY_FILE" "$MKINITCPIO_DROPIN"
    sudo mkinitcpio -P || return 1
    sudo systemctl disable dotfiles-stage.service
    sudo rm -f "$UNIT" "$STATE_DIR/next"
}

stage=$(<"$STATE_DIR/next")
case "$stage" in
    install) next=config ;;
    config) next="" ;;
    *)
        echo "stage: unknown stage '$stage' in $STATE_DIR/next" >&2
        exit 1
        ;;
esac

log "$stage: start"
if ./"$stage".sh </dev/null; then log "$stage: ok"; else log "$stage: failed, see $stage.log"; fi

if [[ -n "$next" ]]; then
    echo "$next" | sudo tee "$STATE_DIR/next" >/dev/null
elif ! disarm; then
    log "disarm failed, the temporary keyfile and passwordless sudo are still in place"
    exit 1
fi
log "rebooting"
if [[ -n "$next" ]]; then
    sudo systemctl reboot
else
    # one sudo call: after the rm there is no passwordless sudo left to reboot with
    sudo sh -c "rm -f $SUDOERS_DROPIN && systemctl reboot"
fi
