#!/usr/bin/env bash
# drop pam state older base/pam runs left: the u2f line with luca's authfile= (pam_u2f's per-user default replaces it), the
# fingerprint lock service, u2f/fprintd on login (the typed password must reach gnome-keyring), kwallet on ly (one secret service)
set -euo pipefail

rm -f /etc/pam.d/quickshell-lock-fprint
# a sufficient line only ever adds a way in, so dropping one can not lock anyone out
if grep -qE '^auth[[:space:]]+sufficient[[:space:]]+pam_u2f\.so.*[[:space:]]authfile=' /etc/pam.d/sudo 2>/dev/null; then
    sed -i -E '/^auth[[:space:]]+sufficient[[:space:]]+pam_u2f\.so.*[[:space:]]authfile=/d' /etc/pam.d/sudo
fi
if grep -qE '^auth[[:space:]]+sufficient[[:space:]]+pam_(u2f|fprintd)\.so' /etc/pam.d/system-login 2>/dev/null; then
    sed -i -E '/^auth[[:space:]]+sufficient[[:space:]]+pam_(u2f|fprintd)\.so/d' /etc/pam.d/system-login
fi
if grep -q 'pam_kwallet5\.so' /etc/pam.d/ly 2>/dev/null; then
    sed -i '/pam_kwallet5\.so/d' /etc/pam.d/ly
fi
