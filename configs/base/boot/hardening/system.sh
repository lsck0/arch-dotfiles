#!/usr/bin/env bash
# KSPP-style boot-time hardening, written into the UKI cmdline via the boot barrier (system-apply runs
# boot_commit, which rebuilds and signs the ukis). kernel_cmdline_set replaces tokens per key, so this is
# idempotent and co-exists with the tokens bootstrap.sh seeds at install.
# wsl has no uki or host kernel of its own.
[[ "$FORM_FACTOR" != wsl ]] || exit 0

source "$DOTFILES/configs/base/boot/common.sh"

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

# cross-thread data leak (MDS, MMIO stale data): on an smt-capable intel cpu these bugs affect, the per-vuln
# mitigations clear the cpu buffers but a sibling hyperthread can still read them, so disable smt. scoped by hardware,
# not the current smt state (nosmt itself turns smt off, which would otherwise flip the check and flap it every run):
# the smt/control file stays != notsupported while capable, and the vuln files still name the bug (not "Not affected")
# while mitigated-with-smt-off. amd zen and cpus these bugs do not affect keep smt. skipped in a guest: the host owns it
vuln_affected() { [[ -r "$1" ]] && ! grep -q 'Not affected' "$1"; }
smt_ctl=$(cat /sys/devices/system/cpu/smt/control 2>/dev/null || echo notsupported)
if [[ "$FORM_FACTOR" != vm ]] && grep -q GenuineIntel /proc/cpuinfo && [[ "$smt_ctl" != notsupported ]] &&
    { vuln_affected /sys/devices/system/cpu/vulnerabilities/mds ||
        vuln_affected /sys/devices/system/cpu/vulnerabilities/mmio_stale_data; }; then
    kernel_cmdline_set nosmt
else
    kernel_cmdline_unset nosmt
fi
