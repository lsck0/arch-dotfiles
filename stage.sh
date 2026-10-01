#!/usr/bin/env bash
# One unattended stage per boot, install.sh then config.sh; disarms the temporary keyfile and sudo at the end

set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")" || exit 1

STATE_DIR=/var/lib/dotfiles-stage
KEY_FILE=/etc/cryptsetup-keys.d/root.key
MKINITCPIO_DROPIN=/etc/mkinitcpio.conf.d/dotfiles-stage.conf
SUDOERS_DROPIN=/etc/sudoers.d/zz-dotfiles-stage
UNIT=/etc/systemd/system/dotfiles-stage.service
ATTEMPTS_FILE=$STATE_DIR/install-attempts
ABORTED_FILE=$STATE_DIR/install-aborted
# a few boots cover a flaky network or mirror, a real bug would loop forever
INSTALL_ATTEMPTS_MAX=3
# install.sh's EXIT_ABORTED, as opposed to a finished run that logged failures
INSTALL_EXIT_ABORTED=2

log() { echo "$(date -Is) $*" | sudo tee -a "$STATE_DIR/log"; }

# idempotent: a re-run after a partial disarm must still finish, so each step tolerates being already done
disarm() {
    local device
    device=$(<"$STATE_DIR/luks-device")
    # keyslot first: once it is gone the keyfile on the ESP opens nothing
    # sudo test: /etc/cryptsetup-keys.d is root-only, a plain [[ -f ]] as the user is always false
    if sudo test -f "$KEY_FILE"; then
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

# install.sh's prompts would otherwise read the pty `script` gives it
export DOTFILES_UNATTENDED=1

log "$stage: start"
./"$stage".sh </dev/null
status=$?
if ((status == 0)); then log "$stage: ok"; else log "$stage: failed, see $stage.log"; fi

if [[ "$stage" == install ]]; then
    if ((status == INSTALL_EXIT_ABORTED)); then
        attempts=$(($(cat "$ATTEMPTS_FILE" 2>/dev/null || echo 0) + 1))
        if ((attempts < INSTALL_ATTEMPTS_MAX)); then
            log "install: aborted, attempt $attempts/$INSTALL_ATTEMPTS_MAX, retrying next boot"
            echo "$attempts" | sudo tee "$ATTEMPTS_FILE" >/dev/null
            next=install
        else
            log "install: aborted $attempts times, moving on to config"
            sudo touch "$ABORTED_FILE"
            sudo rm -f "$ATTEMPTS_FILE"
        fi
    else
        sudo rm -f "$ATTEMPTS_FILE" "$ABORTED_FILE"
    fi
fi

if [[ -n "$next" ]]; then
    echo "$next" | sudo tee "$STATE_DIR/next" >/dev/null
elif [[ -f "$ABORTED_FILE" ]]; then
    sudo rm -f "$STATE_DIR/next"
    log "install.sh never finished, the temporary keyfile and passwordless sudo are still in place;" \
        "fix it, then 'echo install | sudo tee $STATE_DIR/next' and reboot"
    exit 1
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
