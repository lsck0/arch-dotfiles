#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -ex

# copies, pam will not follow symlinks into home
sed "s|@HOME@|$HOME|" quickshell-lock | sudo tee /etc/pam.d/quickshell-lock >/dev/null
sudo install -m 644 quickshell-lock-fprint /etc/pam.d/quickshell-lock-fprint

# optional yubikey touch auth, nouserok falls through to password
U2F_MODULE=/usr/lib/security/pam_u2f.so
U2F_LINE='auth       sufficient pam_u2f.so nouserok cue authfile='"${HOME}"'/.config/Yubico/u2f_keys'

pam_u2f_install() {
    # insert before the first system-auth include, else leave untouched
    local svc="$1"
    [ -f "$svc" ] || return 0
    if grep -q 'pam_u2f.so' "$svc"; then return 0; fi
    local tmp
    tmp=$(mktemp)
    awk -v line="$U2F_LINE" '
        !added && $1=="auth" && /include/ && /system-auth/ { print line; added=1 }
        { print }
    ' "$svc" >"$tmp"
    if [ -s "$tmp" ] && grep -q 'pam_u2f.so' "$tmp" && grep -q 'system-auth' "$tmp"; then
        [ -f "${svc}.pre-u2f.bak" ] || sudo cp -a "$svc" "${svc}.pre-u2f.bak"
        sudo install -m "$(stat -c %a "$svc")" "$tmp" "$svc"
    fi
    rm -f "$tmp"
}

if [ -e "$U2F_MODULE" ]; then
    pam_u2f_install /etc/pam.d/sudo
    pam_u2f_install /etc/pam.d/system-login
else
    echo "pam-u2f not installed (${U2F_MODULE} missing); skipping u2f PAM lines" >&2
fi
