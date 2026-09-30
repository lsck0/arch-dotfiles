#!/usr/bin/env bash
# One unattended stage per boot, install.sh then config.sh; disarms the temporary keyfile and sudo at the end

set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")" || exit 1

STATE_DIR=/var/lib/dotfiles-stage
KEY_FILE=/etc/cryptsetup-keys.d/root.key
MKINITCPIO_DROPIN=/etc/mkinitcpio.conf.d/dotfiles-stage.conf
SUDOERS_DROPIN=/etc/sudoers.d/zz-dotfiles-stage
UNIT=/etc/systemd/system/dotfiles-stage.service

log() { echo "$(date -Is) $*" | sudo tee -a "$STATE_DIR/log"; }

# idempotent: a re-run after a partial disarm must still finish, so each step tolerates being already done
disarm() {
    local device
    device=$(<"$STATE_DIR/luks-device")
    # keyslot first: once it is gone the keyfile on the ESP opens nothing
    if [[ -f "$KEY_FILE" ]]; then
        sudo cryptsetup luksRemoveKey "$device" "$KEY_FILE" || return 1
        sudo rm -f "$KEY_FILE"
    fi
    sudo rm -f "$MKINITCPIO_DROPIN"
    sudo mkinitcpio -P || return 1
    sudo systemctl disable dotfiles-stage.service || true
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
