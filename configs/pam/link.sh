#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -ex

# PAM service files for the quickshell matrix lock. Real files in /etc/pam.d
# (not symlinks: PAM will not follow a symlink out of /etc into the home dir,
# and the stack must resolve at early boot / on a locked session).
sudo install -m 644 quickshell-lock        /etc/pam.d/quickshell-lock
sudo install -m 644 quickshell-lock-fprint /etc/pam.d/quickshell-lock-fprint
