use module.nu *
use ../boot.nu [cmdline-set cmdline-unset]

export const options = {
    allow_smt: {
        type: bool
        default: false
        doc: "Keep hyperthreading despite MDS/MMIO, accepting the cross-sibling leak for the threads"
        label: "Allow SMT"
        apply: reboot
        scope: machine
    }
}

# KSPP boot hardening. not set, each breaks something relied on: lockdown=confidentiality (the unsigned it87-dkms,
# bpf/kprobes for pwndbg and bpftrace), debugfs=off (bpftrace, bpftop), module.sig_enforce (dkms)
const TOKENS = [
    slab_nomerge init_on_alloc=1 init_on_free=1 randomize_kstack_offset=on vsyscall=none page_alloc.shuffle=1
]
const VULNS = [/sys/devices/system/cpu/vulnerabilities/mds /sys/devices/system/cpu/vulnerabilities/mmio_stale_data]

# by hardware, not the current smt state (nosmt itself turns it off and would flap the check): smt/control stays
# capable and the vuln files keep naming the bug while mitigated with smt off. a guest's host owns smt
def smt-leaks []: nothing -> bool {
    let control = try { open --raw /sys/devices/system/cpu/smt/control | str trim } catch { "notsupported" }
    (
        ($env.FORM_FACTOR? != "vm" and $control != "notsupported"
            and (open --raw /proc/cpuinfo | str contains GenuineIntel))
        and ($VULNS | any {|f| ($f | path exists) and not (open --raw $f | str contains "Not affected") })
    )
}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    step harden ...(if not $cfg.allow_smt and (smt-leaks) { [nosmt] } else { [] })
}

export def harden [...extra: string]: nothing -> nothing {
    cmdline-set ...$TOKENS ...$extra
    if "nosmt" not-in $extra { cmdline-unset nosmt }
}
