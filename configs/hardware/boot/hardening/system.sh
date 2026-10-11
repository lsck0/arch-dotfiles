#!/usr/bin/env bash
# KSPP-style boot-time hardening, written into the UKI cmdline via the boot barrier (system-apply runs
# boot_commit, which rebuilds and signs the ukis). kernel_cmdline_set replaces tokens per key, so this is
# idempotent and co-exists with the tokens bootstrap.sh seeds at install.
# wsl has no uki or host kernel of its own.
[[ "$FORM_FACTOR" != wsl ]] || exit 0

source "$DOTFILES/configs/hardware/boot/boot-menu/common.sh"

# Deliberately NOT set, because they break tools this system relies on:
#   lockdown=confidentiality  -> blocks the unsigned it87-dkms module and restricts the bpf/kprobes pwndbg & bpftrace use
#   debugfs=off               -> breaks bpftrace / bpftop
#   module.sig_enforce        -> breaks DKMS modules
kernel_cmdline_set \
    slab_nomerge \
    init_on_alloc=1 \
    init_on_free=1 \
    randomize_kstack_offset=on \
    vsyscall=none \
    page_alloc.shuffle=1
