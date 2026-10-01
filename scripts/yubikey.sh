#!/usr/bin/env bash
# yubikey init [steps] (once per key, from unlocked secrets) | unlock (secrets by touch, config.sh runs it); always optional

set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
KEY_DIR="$REPO/configs/yubikey"
SECRETS="$REPO/configs/secrets"
SEALED_KEY="$KEY_DIR/secrets.key.age"
GPG_FINGERPRINT=E7501F533316E9AFC6AAE907122F2CB527D1EFE3
PAM_ORIGIN=pam://lsck0
SSH_APPLICATION=ssh:lsck0
AGE_SLOT=1
TOUCH_WAIT_S=1800
TOUCH_ATTEMPT_S=60

die() { echo "yubikey: $*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }

present() { command -v ykman >/dev/null && ykman info >/dev/null 2>&1; }
serial() { ykman info | awk -F': ' '/^Serial number/ {print $2}'; }
secrets_plain() { grep -qs 'BEGIN PGP PRIVATE KEY' "$SECRETS/pgp_privatekey.asc"; }
# git-crypt checks files out 0644, and ssh ignores a private key others can read
private_keys_0600() { chmod 600 "$SECRETS"/*private*key*.asc 2>/dev/null || true; }
recipient() { sed -n 's/^#[[:space:]]*Recipient: //p' "$1"; }

# the chain reaches this hours after bootstrap, so keep asking for a touch for a while before giving up
with_touch() {
    local deadline=$((SECONDS + TOUCH_WAIT_S))
    until timeout "$TOUCH_ATTEMPT_S" "$@"; do
        ((SECONDS < deadline)) || return 1
        sleep 2
    done
}

# every enrolled key's age recipient, so any of them opens the sealed git-crypt key
seal_secrets_key() {
    local key recipients=()
    key=$(mktemp)
    trap 'shred -u "$key" 2>/dev/null || true; trap - RETURN' RETURN
    git -C "$SECRETS" crypt export-key "$key"
    for identity in "$KEY_DIR"/age-*.identity; do
        recipients+=(-r "$(recipient "$identity")")
    done
    age -e "${recipients[@]}" -o "$SEALED_KEY" "$key"
}

# a copy onto the card from a throwaway keyring, the file in secrets stays the backup
pgp_to_card() {
    local home
    home=$(mktemp -d)
    trap 'gpgconf --homedir "$home" --kill all; command rm -rf "$home"; trap - RETURN' RETURN
    # through pcscd, which already holds the card for ykman
    printf 'disable-ccid\npcsc-shared\n' >"$home/scdaemon.conf"
    gpg --homedir "$home" --import "$SECRETS/pgp_privatekey.asc"
    echo "gpg prompt: keytocard -> 1 (signature), key 1, keytocard -> 2 (encryption), save"
    gpg --homedir "$home" --edit-key "$GPG_FINGERPRINT"
}

cmd_init() {
    present || die "no YubiKey detected"
    secrets_plain || die "secrets are locked, unlock them first"
    local sn
    sn=$(serial)
    local steps=("$@")
    ((${#steps[@]})) || steps=(pins pgp ssh u2f age)
    for step_name in "${steps[@]}"; do
        "init_$step_name" "$sn"
    done
    step "done: commit configs/yubikey; homelab .sops.yaml needs $(recipient "$KEY_DIR/age-$sn.identity" 2>/dev/null)"
}

init_pins() {
    if ykman fido info | grep -q '^PIN:.*Not set'; then
        step "FIDO2 PIN, needed once to create credentials, never for a touch"
        ykman fido access change-pin
    fi
    step "OpenPGP PINs: 'Enter PIN' wants the current one, 123456 (admin 12345678) until changed"
    ykman openpgp access change-pin
    ykman openpgp access change-admin-pin
}

card_has_pgp() { ykman openpgp info | tr -d ' ' | grep -q "Fingerprint:$GPG_FINGERPRINT"; }

init_pgp() {
    step "the Luca Sandrock key onto the card"
    # gpg exits non-zero after a quit without save although keytocard already wrote the card
    card_has_pgp || pgp_to_card || true
    card_has_pgp || die "the card does not hold $GPG_FINGERPRINT"
    ykman openpgp keys set-touch sig on
    ykman openpgp keys set-touch dec on
}

init_ssh() {
    step "ssh key, touch only; the stub is useless without the key and gets committed"
    ssh-keygen -t ed25519-sk -O resident -O "application=$SSH_APPLICATION" -N "" \
        -C "luca@yubikey-$1" -f "$KEY_DIR/ssh-$1"
    gh auth refresh -h github.com -s admin:public_key
    gh ssh-key add "$KEY_DIR/ssh-$1.pub" --title "yubikey-$1"
}

init_u2f() {
    step "pam_u2f for sudo, login and the lock screen"
    local line
    line=$(pamu2fcfg -o "$PAM_ORIGIN" -i "$PAM_ORIGIN" -u "$USER")
    if [[ -f "$KEY_DIR/u2f_keys" ]]; then
        sed -i "s|^$USER:.*|&:${line#"$USER":}|" "$KEY_DIR/u2f_keys"
    else
        echo "$line" >"$KEY_DIR/u2f_keys"
    fi
}

init_age() {
    step "age identity, touch without PIN, for sops and the sealed git-crypt key"
    # the plugin only drives a PIN-protected TDES management key, firmware 5.7+ ships an AES one
    if ! ykman piv info | grep -q 'protected by PIN'; then
        echo "management key: press enter for the default, then give the PIV PIN"
        ykman piv access change-management-key -a TDES --protect
    fi
    local identity
    identity=$(age-plugin-yubikey --generate --serial "$1" --slot "$AGE_SLOT" --name lsck0 \
        --pin-policy never --touch-policy always)
    echo "$identity" >"$KEY_DIR/age-$1.identity"
    seal_secrets_key
}

# each step is one touch; no key, no enrollment or no touch just skips
cmd_unlock() {
    # ykman and the age plugin talk to the card through pcscd; configs/yubikey enables it later
    sudo systemctl start pcscd.socket 2>/dev/null || true
    if ! present; then
        # no yubikey: the pgp key (git-crypt's gpg user) can still unlock an already-pulled secrets worktree
        if [[ -e "$SECRETS/.git" ]] && ! secrets_plain; then
            git -C "$SECRETS" crypt unlock && private_keys_0600 \
                || echo "yubikey: no key present and pgp git-crypt unlock failed"
        else
            echo "yubikey: none plugged in, secrets stay as they are"
        fi
        return 0
    fi
    local sn stub identity
    sn=$(serial)
    stub="$KEY_DIR/ssh-$sn"
    identity="$KEY_DIR/age-$sn.identity"
    if [[ ! -f "$stub" || ! -f "$identity" || ! -f "$SEALED_KEY" ]]; then
        echo "yubikey: $sn is not enrolled (yubikey init), skipping"
        return 0
    fi

    if [[ ! -e "$SECRETS/.git" ]]; then
        # ssh rejects a key file other users can read, git checks the stub out 0644
        local key_file
        key_file=$(mktemp)
        install -m600 "$stub" "$key_file"
        local ssh_command="ssh -i $key_file -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
        echo ">>> touch the YubiKey to pull the secrets"
        with_touch git -C "$REPO" -c "core.sshCommand=$ssh_command" \
            -c "url.git@github.com:lsck0/.insteadOf=https://github.com/lsck0/" \
            submodule update --init configs/secrets || echo "yubikey: pull failed or no touch"
        command rm -f "$key_file"
        [[ -e "$SECRETS/.git" ]] || return 0
    fi

    if ! secrets_plain; then
        echo ">>> touch the YubiKey to unlock the secrets"
        local key
        key=$(mktemp)
        # shred even if crypt unlock fails under set -e, so the plaintext key never lingers on tmpfs
        trap 'shred -u "$key" 2>/dev/null || true; trap - RETURN' RETURN
        if with_touch age -d -i "$identity" -o "$key" "$SEALED_KEY"; then
            git -C "$SECRETS" crypt unlock "$key" && private_keys_0600 || echo "yubikey: git-crypt unlock failed"
        else
            echo "yubikey: unlock failed or no touch"
        fi
    fi
}

case "${1:-}" in
    init) shift; cmd_init "$@" ;;
    unlock) cmd_unlock ;;
    *) die "usage: yubikey init [pins|pgp|ssh|u2f|age ...] | unlock" ;;
esac
