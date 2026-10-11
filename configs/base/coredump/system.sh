#!/usr/bin/env bash

install -Dm644 10-storage.conf /etc/systemd/coredump.conf.d/10-storage.conf
# sorts before systemd.conf, so its age wins for the coredump directory
install -Dm644 coredump-tmpfiles.conf /etc/tmpfiles.d/coredump.conf
systemctl daemon-reload

# a kernel panic leaves no core: efi_pstore (default off in arch's kernel) keeps its last log in nvram, and
# systemd-pstore moves it to /var/lib/systemd/pstore on the next boot. windows owns the kernel under wsl
[[ "$FORM_FACTOR" != wsl ]] || exit 0
source "$DOTFILES/configs/base/boot/common.sh"
if esp_supported; then
    kernel_cmdline_set efi_pstore.pstore_disable=0
fi
systemctl enable systemd-pstore.service
