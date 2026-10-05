#!/usr/bin/env bash
# One unattended stage per boot, install.sh then config.sh; the config stage disarms the temporary keyfile first, the chain retires itself and sudo at the end

set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")" || exit 1

STATE_DIR=/var/lib/dotfiles-stage
KEY_FILE=/etc/cryptsetup-keys.d/root.key
MKINITCPIO_DROPIN=/etc/mkinitcpio.conf.d/dotfiles-stage.conf
SUDOERS_DROPIN=/etc/sudoers.d/zz-dotfiles-stage
UNIT=/etc/systemd/system/dotfiles-stage.service
ATTEMPTS_FILE=$STATE_DIR/install-attempts
# a few boots cover a flaky network or mirror, a real bug would loop forever
INSTALL_ATTEMPTS_MAX=3
# install.sh's EXIT_ABORTED, as opposed to a finished run that logged failures
INSTALL_EXIT_ABORTED=2

log() { echo "$(date -Is) $*" | sudo tee -a "$STATE_DIR/log"; }

# idempotent; config.sh's boot barrier rebuilds the initramfs without the keyfile, a stale one opens nothing once the slot is gone
disarm() {
    local device
    device=$(<"$STATE_DIR/luks-device")
    # keyslot first: once it is gone the keyfile on the ESP opens nothing; sudo test because /etc/cryptsetup-keys.d is root-only, a plain [[ -f ]] as the user is always false
    if sudo test -f "$KEY_FILE"; then
        sudo cryptsetup luksRemoveKey "$device" "$KEY_FILE" || return 1
        sudo rm -f "$KEY_FILE"
    fi
    sudo rm -f "$MKINITCPIO_DROPIN"
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

# the keyfile only exists to boot into this stage, so nothing below can leave it armed
if [[ "$stage" == config ]] && ! disarm; then
    log "disarm failed, the temporary keyfile is still in place"
    exit 1
fi

log "$stage: start"
./"$stage".sh </dev/null
status=$?
if ((status == 0)); then log "$stage: ok"; else log "$stage: failed, see $stage.log"; fi

if [[ "$stage" == install ]] && ((status == INSTALL_EXIT_ABORTED)); then
    attempts=$(($(cat "$ATTEMPTS_FILE" 2>/dev/null || echo 0) + 1))
    echo "$attempts" | sudo tee "$ATTEMPTS_FILE" >/dev/null
    if ((attempts < INSTALL_ATTEMPTS_MAX)); then
        log "install: aborted, attempt $attempts/$INSTALL_ATTEMPTS_MAX, retrying next boot"
        next=install
    else
        log "install: aborted $attempts times, moving on to config; rerun ./install.sh by hand"
    fi
fi

log "rebooting"
if [[ -n "$next" ]]; then
    echo "$next" | sudo tee "$STATE_DIR/next" >/dev/null
    sudo systemctl reboot
else
    # a crash before this line reruns the config stage next boot; one sudo call, after the rm there is no passwordless sudo left to reboot with
    sudo systemctl disable dotfiles-stage.service
    sudo sh -c "rm -f $UNIT $STATE_DIR/next $SUDOERS_DROPIN && systemctl reboot"
fi
