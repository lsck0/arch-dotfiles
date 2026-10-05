#!/usr/bin/env bash
# Wire fingerprint and YubiKey auth into sudo, additive to the password; login and the lock screen take the password only.
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/personal.sh
source ../../scripts/lib/platform.sh

# windows owns sign-in hardware under wsl: no fingerprint reader, a yubikey only through usbipd
[[ "$(platform_form_factor ../..)" != wsl ]] || exit 0

set -e

U2F_MODULE=/usr/lib/security/pam_u2f.so
FPRINT_MODULE=/usr/lib/security/pam_fprintd.so

# no nouserok: a user absent from the authfile must fall through to the password include, not pass unauthenticated
U2F_LINE=''
is_personal && U2F_LINE='auth       sufficient pam_u2f.so cue origin=pam://lsck0 appid=pam://lsck0 authfile='"${HOME}"'/.config/Yubico/u2f_keys'
FPRINT_LINE='auth       sufficient pam_fprintd.so'

# a validity/synaptics sensor uses python-validity + open-fprintd; other readers use fprintd directly
has_fprint() {
    # the validity unit ships everywhere, so also require the usb sensor
    if systemctl list-unit-files --no-legend 'python3-validity.service' 2>/dev/null | grep -q .; then
        lsusb -d 138a: >/dev/null 2>&1 || lsusb -d 06cb: >/dev/null 2>&1 && return 0
    fi
    # fprintd-list exits 0 even with "No devices found"
    command -v fprintd-list >/dev/null 2>&1 && fprintd-list "$(id -un)" 2>/dev/null | grep -q '^Fingerprints for user'
}

# copy, pam will not follow symlinks into home
sudo install -m 644 quickshell-lock /etc/pam.d/quickshell-lock
sudo rm -f /etc/pam.d/quickshell-lock-fprint

# insert an auth line before the first system-auth include; replaces an older line of the same module
pam_auth_install() {
    local svc="$1" line="$2" module="$3"
    [ -f "$svc" ] && [ -n "$line" ] || return 0
    if grep -qxF "$line" "$svc"; then return 0; fi
    local tmp
    tmp=$(mktemp)
    awk -v line="$line" -v module="$module" '
        index($0, module) { next }
        !added && $1 == "auth" && /include/ && /system-auth/ { print line; added=1 }
        { print }
    ' "$svc" >"$tmp"
    if [ -s "$tmp" ] && grep -q 'system-auth' "$tmp"; then
        [ -f "${svc}.pre-auth.bak" ] || sudo cp -a "$svc" "${svc}.pre-auth.bak"
        sudo install -m "$(stat -c %a "$svc")" "$tmp" "$svc"
    fi
    rm -f "$tmp"
}

# first-inserted sits highest: the yubikey touch stays first (the habit)
u2f_ok() { is_personal && [ -e "$U2F_MODULE" ]; }
fprint_ok() { has_fprint && [ -e "$FPRINT_MODULE" ]; }

if u2f_ok; then pam_auth_install /etc/pam.d/sudo "$U2F_LINE" pam_u2f.so; fi
if fprint_ok; then
    pam_auth_install /etc/pam.d/sudo "$FPRINT_LINE" pam_fprintd.so
elif grep -qE 'pam_fprintd\.so' /etc/pam.d/sudo; then
    sudo sed -i -E '/^auth[[:space:]]+sufficient[[:space:]]+pam_fprintd\.so/d' /etc/pam.d/sudo
fi

# login needs the typed password: a sufficient touch or swipe ends the stack before pam_gnome_keyring gets it and the login keyring stays locked; strip what older runs put there
if grep -qE 'pam_(u2f|fprintd)\.so' /etc/pam.d/system-login; then
    sudo sed -i -E '/^auth[[:space:]]+sufficient[[:space:]]+pam_(u2f|fprintd)\.so/d' /etc/pam.d/system-login
fi

# one secret service: kwallet's ksecretd would race gnome-keyring for org.freedesktop.secrets
if grep -q 'pam_kwallet5\.so' /etc/pam.d/ly 2>/dev/null; then
    sudo sed -i '/pam_kwallet5\.so/d' /etc/pam.d/ly
fi
