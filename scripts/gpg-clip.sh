#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# gpg on the clipboard: `decrypt` decrypts or verifies it and shows the result, `encrypt` signs and encrypts it to picked keys, `sign` clear-signs it
# decrypted text is shown, never copied: the clipboard can outlive the read

set -uo pipefail

VIEWER_TITLE="gpg-clip"

notify() { notify-send --app-name=gpg-clip "$@"; }

clip_get() {
    local text
    text=$(wl-paste --no-newline 2>/dev/null) || { notify "Clipboard is empty"; exit 1; }
    [[ -n "$text" ]] || { notify "Clipboard is empty"; exit 1; }
    printf '%s' "$text"
}

clip_decrypt() {
    local text out status
    text=$(clip_get) || exit 1
    # tmpfs and 0600, unlinked as soon as the viewer holds it open
    out=$(umask 077 && mktemp "${XDG_RUNTIME_DIR:-/tmp}/gpg-clip.XXXXXX")
    status=$(printf '%s\n' "$text" | gpg --batch --yes --status-fd 1 --decrypt --output "$out" 2>/dev/null)
    local signer
    signer=$(sed -n 's/^\[GNUPG:\] GOODSIG [0-9A-F]* //p' <<<"$status")
    if grep -q '^\[GNUPG:\] BADSIG' <<<"$status"; then
        notify --urgency=critical "BAD signature" "The message was altered or the signature is forged"
    elif [[ -n "$signer" ]]; then
        notify "Good signature" "$signer"
    elif ! grep -qE '^\[GNUPG:\] (DECRYPTION_OKAY|PLAINTEXT)' <<<"$status"; then
        notify --urgency=critical "Nothing to decrypt or verify" "No OpenPGP message on the clipboard"
        rm -f "$out"
        exit 1
    fi
    [[ -s "$out" ]] || { rm -f "$out"; exit 0; }
    ghostty --title="$VIEWER_TITLE" -e sh -c 'exec 3<"$1"; rm -f -- "$1"; less /dev/fd/3' _ "$out"
}

# "name <mail>  FINGERPRINT", one line per usable key; $1 is the capability letter, $2 lists secret keys only
key_list() {
    local cap="$1" listing=--list-keys
    [[ "${2:-}" == secret ]] && listing=--list-secret-keys
    gpg "$listing" --with-colons 2>/dev/null | awk -F: -v cap="$cap" '
        $1 == "pub" || $1 == "sec" { usable = ($12 ~ cap && $2 != "r" && $2 != "e"); fpr = ""; next }
        $1 == "fpr" && fpr == "" { fpr = $10; next }
        $1 == "uid" && usable && fpr != "" && fpr != "x" && $2 != "r" { print $10 "  " fpr; fpr = "x" }
    ' | sort -u
}

pick() { "$DOTFILES/scripts/picker.sh" -p "$1" | awk '{ print $NF }'; }

# gpg.conf's default-key comes first, so enter signs with it; the only secret key signs without asking
signer_pick() {
    local keys default
    keys=$(key_list S secret)
    [[ -n "$keys" ]] || { notify --urgency=critical "No secret key to sign with"; exit 1; }
    default=$(gpgconf --list-options gpg 2>/dev/null | awk -F: '$1 == "default-key" { gsub(/"/, "", $10); print $10 }')
    if [[ $(wc -l <<<"$keys") -eq 1 ]]; then
        awk '{ print $NF }' <<<"$keys"
    else
        { [[ -z $default ]] || grep -F "$default" <<<"$keys"; grep -vF "${default:-NONE}" <<<"$keys"; } | pick "sign as"
    fi
}

# bemenu picks one line, so recipients are picked one at a time until "done"
recipients_pick() {
    local keys chosen=() fpr
    keys=$(key_list E)
    while true; do
        fpr=$( { ((${#chosen[@]})) && echo "done  (${#chosen[@]} picked)  DONE"; grep -vF -f <(printf '%s\n' "${chosen[@]:-NONE}") <<<"$keys"; } \
            | pick "encrypt to")
        [[ -n "$fpr" && "$fpr" != DONE ]] || break
        chosen+=("$fpr")
    done
    printf '%s\n' "${chosen[@]}"
}

uid_of() { gpg --list-keys --with-colons "$1" 2>/dev/null | awk -F: '$1 == "uid" { print $10; exit }'; }

clip_encrypt() {
    local text signer recipients args=() fpr armored hash
    text=$(clip_get) || exit 1
    # hashed from the clipboard, not $text: command substitution strips the trailing newlines the history keeps
    hash=$(wl-paste --type text --no-newline 2>/dev/null | md5sum | cut -d' ' -f1)
    mapfile -t recipients < <(recipients_pick)
    ((${#recipients[@]})) || exit 0
    signer=$(signer_pick)
    [[ -n "$signer" ]] || exit 0
    # the signing key is a recipient too, so the sent message stays readable here
    for fpr in "${recipients[@]}" "$signer"; do args+=(--recipient "$fpr"); done
    armored=$(printf '%s\n' "$text" | gpg --armor --local-user "$signer" --sign --encrypt "${args[@]}" 2>/dev/null) || {
        notify --urgency=critical "Encryption failed"
        exit 1
    }
    printf '%s\n' "$armored" | wl-copy
    timeout 3 quickshell ipc -p "$HOME/.config/quickshell" call clipboard forget "$hash" >/dev/null 2>&1 || true
    notify "Encrypted and signed as $(uid_of "$signer")" "For $(for fpr in "${recipients[@]}"; do uid_of "$fpr"; done | paste -sd, - | sed 's/,/, /g')"
}

clip_sign() {
    local text signer signed hash
    text=$(clip_get) || exit 1
    hash=$(wl-paste --type text --no-newline 2>/dev/null | md5sum | cut -d' ' -f1)
    signer=$(signer_pick)
    [[ -n "$signer" ]] || exit 0
    signed=$(printf '%s\n' "$text" | gpg --local-user "$signer" --clearsign 2>/dev/null) || {
        notify --urgency=critical "Signing failed"
        exit 1
    }
    printf '%s\n' "$signed" | wl-copy
    timeout 3 quickshell ipc -p "$HOME/.config/quickshell" call clipboard forget "$hash" >/dev/null 2>&1 || true
    notify "Signed as $(uid_of "$signer")" "Clear-signed text copied"
}

case "${1:-}" in
decrypt) clip_decrypt ;;
encrypt) clip_encrypt ;;
sign) clip_sign ;;
*)
    echo "usage: $(basename "$0") decrypt|encrypt|sign" >&2
    exit 2
    ;;
esac
