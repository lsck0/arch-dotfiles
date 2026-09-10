#!/usr/bin/env bash

set -ex

sudo chsh $USER -s /bin/zsh

sudo gpasswd -a $USER docker

# wireshark is in install.sh's PACKAGES, guaranteed; libvirt isn't (installed
# by hand, if at all) — usermod validates every group in one call atomically,
# so a missing libvirt group would silently take the wireshark group add
# down with it too. Split so one genuinely-optional group doesn't block the
# other.
sudo usermod -aG wireshark $USER
getent group libvirt >/dev/null && sudo usermod -aG libvirt $USER || echo "skip: libvirt group not present" >&2
