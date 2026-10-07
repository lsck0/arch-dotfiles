#!/usr/bin/env bash
# fingerprint and YubiKey auth on sudo, additive to the password; login and the lock screen take the password only.
# older lines (u2f authfile=, fprint lock service, u2f/fprintd on login, kwallet on ly) are patch 18's

# windows owns sign-in hardware under wsl: no fingerprint reader, a yubikey only through usbipd
[[ "$FORM_FACTOR" != wsl ]] || exit 0

U2F_MODULE=/usr/lib/security/pam_u2f.so
FPRINT_MODULE=/usr/lib/security/pam_fprintd.so
# login.defs' range for people: the users whose enrolled fingers count
HUMAN_UID_MIN=1000
HUMAN_UID_MAX=59999

# every user's own ~/.config/Yubico/u2f_keys (pam_u2f's default); no nouserok: a user without one falls through to
# the password include, never passes unauthenticated
U2F_LINE='auth       sufficient pam_u2f.so cue origin=pam://lsck0 appid=pam://lsck0'
FPRINT_LINE='auth       sufficient pam_fprintd.so'

# a validity/synaptics sensor uses python-validity + open-fprintd; other readers use fprintd, once anyone enrolled a finger
has_fprint() {
    local user
    # the validity unit ships everywhere, so also require the usb sensor
    if systemctl list-unit-files --no-legend 'python3-validity.service' 2>/dev/null | grep -q .; then
        lsusb -d 138a: >/dev/null 2>&1 || lsusb -d 06cb: >/dev/null 2>&1 && return 0
    fi
    command -v fprintd-list >/dev/null 2>&1 || return 1
    # fprintd-list exits 0 even with "No devices found"
    for user in $(awk -F: -v lo="$HUMAN_UID_MIN" -v hi="$HUMAN_UID_MAX" '$3 >= lo && $3 <= hi {print $1}' /etc/passwd); do
        fprintd-list "$user" 2>/dev/null | grep -q '^Fingerprints for user' && return 0
    done
    return 1
}

# copy, pam will not follow symlinks
install -m 644 quickshell-lock /etc/pam.d/quickshell-lock

# insert an auth line before the first system-auth include; drops every line matching the <module> regex first
pam_auth_install() {
    local svc="$1" line="$2" module="$3" tmp
    [ -f "$svc" ] || return 0
    if grep -qxF "$line" "$svc"; then return 0; fi
    tmp=$(mktemp)
    awk -v line="$line" -v module="$module" '
        $0 ~ module { next }
        !added && $1 == "auth" && /include/ && /system-auth/ { print line; added=1 }
        { print }
    ' "$svc" >"$tmp"
    if [ -s "$tmp" ] && grep -q 'system-auth' "$tmp"; then
        [ -f "${svc}.pre-auth.bak" ] || cp -a "$svc" "${svc}.pre-auth.bak"
        install -m "$(stat -c %a "$svc")" "$tmp" "$svc"
    fi
    rm -f "$tmp"
}

# first-inserted sits highest: the yubikey touch stays first (the habit), so a new u2f line (the authfile= one going)
# also drops the fprintd line for the step below to reinsert under it
if [ -e "$U2F_MODULE" ]; then pam_auth_install /etc/pam.d/sudo "$U2F_LINE" 'pam_(u2f|fprintd)[.]so'; fi
if has_fprint && [ -e "$FPRINT_MODULE" ]; then
    pam_auth_install /etc/pam.d/sudo "$FPRINT_LINE" 'pam_fprintd[.]so'
elif grep -qE '^auth[[:space:]]+sufficient[[:space:]]+pam_fprintd\.so' /etc/pam.d/sudo; then
    sed -i -E '/^auth[[:space:]]+sufficient[[:space:]]+pam_fprintd\.so/d' /etc/pam.d/sudo
fi
