#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/personal.sh

set -e

# luca gets a yubikey touch-or-password line; a guest gets plain password PAM
U2F_MODULE=/usr/lib/security/pam_u2f.so
# no nouserok: a user absent from the authfile must fall through to the password include, not pass unauthenticated
U2F_LINE=''
is_personal && U2F_LINE='auth       sufficient pam_u2f.so cue origin=pam://lsck0 appid=pam://lsck0 authfile='"${HOME}"'/.config/Yubico/u2f_keys'

# copies, pam will not follow symlinks into home
sed "s#@U2F_LINE@#${U2F_LINE}#" quickshell-lock | sudo tee /etc/pam.d/quickshell-lock >/dev/null
sudo install -m 644 quickshell-lock-fprint /etc/pam.d/quickshell-lock-fprint

pam_u2f_install() {
    # insert before the first system-auth include, else leave untouched
    local svc="$1"
    [ -f "$svc" ] || return 0
    if grep -qxF "$U2F_LINE" "$svc"; then return 0; fi
    local tmp
    tmp=$(mktemp)
    # an older pam_u2f line is replaced, not kept next to the new one
    awk -v line="$U2F_LINE" '
        /pam_u2f\.so/ { next }
        !added && $1=="auth" && /include/ && /system-auth/ { print line; added=1 }
        { print }
    ' "$svc" >"$tmp"
    if [ -s "$tmp" ] && grep -q 'pam_u2f.so' "$tmp" && grep -q 'system-auth' "$tmp"; then
        [ -f "${svc}.pre-u2f.bak" ] || sudo cp -a "$svc" "${svc}.pre-u2f.bak"
        sudo install -m "$(stat -c %a "$svc")" "$tmp" "$svc"
    fi
    rm -f "$tmp"
}

if is_personal && [ -e "$U2F_MODULE" ]; then
    pam_u2f_install /etc/pam.d/sudo
    pam_u2f_install /etc/pam.d/system-login
fi
