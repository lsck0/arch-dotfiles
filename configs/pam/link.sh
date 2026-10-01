#!/usr/bin/env bash
# Wire fingerprint and YubiKey auth into login and sudo; both are additive, password always remains the fallback.
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/personal.sh

set -e

U2F_MODULE=/usr/lib/security/pam_u2f.so
FPRINT_MODULE=/usr/lib/security/pam_fprintd.so

# no nouserok: a user absent from the authfile must fall through to the password include, not pass unauthenticated
U2F_LINE=''
is_personal && U2F_LINE='auth       sufficient pam_u2f.so cue origin=pam://lsck0 appid=pam://lsck0 authfile='"${HOME}"'/.config/Yubico/u2f_keys'
FPRINT_LINE='auth       sufficient pam_fprintd.so'

# a validity/synaptics sensor uses python-validity + open-fprintd; other readers use fprintd directly
has_fprint() {
    systemctl list-unit-files --no-legend 'python3-validity.service' 2>/dev/null | grep -q . && return 0
    command -v fprintd-list >/dev/null 2>&1 && fprintd-list "$(id -un)" >/dev/null 2>&1
}

# copies, pam will not follow symlinks into home
sed "s#@U2F_LINE@#${U2F_LINE}#" quickshell-lock | sudo tee /etc/pam.d/quickshell-lock >/dev/null
sudo install -m 644 quickshell-lock-fprint /etc/pam.d/quickshell-lock-fprint

# insert an auth line before the first system-auth include; replaces an older line of the same module
pam_auth_install() {
    local svc="$1" line="$2" module="$3"
    [ -f "$svc" ] && [ -n "$line" ] || return 0
    if grep -qxF "$line" "$svc"; then return 0; fi
    local tmp
    tmp=$(mktemp)
    awk -v line="$line" -v module="$module" '
        $0 ~ module { next }
        !added && $1 == "auth" && /include/ && /system-auth/ { print line; added=1 }
        { print }
    ' "$svc" >"$tmp"
    if [ -s "$tmp" ] && grep -q 'system-auth' "$tmp"; then
        [ -f "${svc}.pre-auth.bak" ] || sudo cp -a "$svc" "${svc}.pre-auth.bak"
        sudo install -m "$(stat -c %a "$svc")" "$tmp" "$svc"
    fi
    rm -f "$tmp"
}

# first-inserted sits highest. sudo keeps the yubikey touch first (the habit); login prompts fingerprint first
u2f_ok() { is_personal && [ -e "$U2F_MODULE" ]; }
fprint_ok() { has_fprint && [ -e "$FPRINT_MODULE" ]; }

if u2f_ok; then pam_auth_install /etc/pam.d/sudo "$U2F_LINE" 'pam_u2f\.so'; fi
if fprint_ok; then pam_auth_install /etc/pam.d/sudo "$FPRINT_LINE" 'pam_fprintd\.so'; fi

if fprint_ok; then pam_auth_install /etc/pam.d/system-login "$FPRINT_LINE" 'pam_fprintd\.so'; fi
if u2f_ok; then pam_auth_install /etc/pam.d/system-login "$U2F_LINE" 'pam_u2f\.so'; fi
