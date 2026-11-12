use module.nu *
use ../boot.nu [cmdline-set cmdline-unset key-of]

export const options = {
    allow_smt: {
        type: bool
        default: false
        doc: "Keep hyperthreading despite MDS/MMIO, accepting the cross-sibling leak for the threads"
        label: "Allow SMT"
        apply: reboot
    }
    relax_mitigations: {
        type: bool
        default: false
        doc: ("Trade kernel hardening for speed on an old Intel cpu: retbleed=stuff for IBRS, no page zeroing on "
            + "alloc and free, a lazy iommu; a Kaby Lake laptop paid 1.4 us per syscall and faulted fresh memory "
            + "at 1 GB/s")
        label: "Relax mitigations"
        apply: reboot
    }
}

# relax_mitigations swaps these by key (cmdline-set replaces a token of the same key). Arch builds init_on_alloc on by
# default, so off is spelled out; retbleed=stuff (call depth tracking) is the skylake-family's cheap, best-effort fix
const RELAXED = [init_on_alloc=0 init_on_free=0 iommu.strict=0 retbleed=stuff]

# not set: lockdown (unsigned it87-dkms, bpf), debugfs=off (bpftrace), module.sig_enforce (dkms), iommu=pt
const TOKENS = [
    slab_nomerge init_on_alloc=1 init_on_free=1 randomize_kstack_offset=on vsyscall=none page_alloc.shuffle=1
    intel_iommu=on iommu.strict=1
]
const VULNS = [/sys/devices/system/cpu/vulnerabilities/mds /sys/devices/system/cpu/vulnerabilities/mmio_stale_data]

# Whether the cpu leaks across smt siblings, by hardware, not the smt state that nosmt itself turns off.
def smt-leaks []: nothing -> bool {
    let control = try { open --raw /sys/devices/system/cpu/smt/control | str trim } catch { "notsupported" }
    (
        $env.FORM_FACTOR? != "vm" and $control != "notsupported"
        and (open --raw /proc/cpuinfo | str contains GenuineIntel)
        and ($VULNS | any {|f| ($f | path exists) and not (open --raw $f | str contains "Not affected") })
    )
}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    let smt = if not $cfg.allow_smt and (smt-leaks) { [nosmt] } else { [] }
    let extra = $smt ++ (if $cfg.relax_mitigations { $RELAXED } else { [] })
    step harden ...$extra
}

export def harden [...extra: string]: nothing -> nothing {
    # one token per key, an extra over the default: passing both makes cmdline-set move the token to the end each run,
    # a cmdline change that rebuilds the boot chain for nothing
    let keys = $extra | each { key-of $in }
    cmdline-set ...($TOKENS | where {|t| (key-of $t) not-in $keys }) ...$extra
    if "nosmt" not-in $extra { cmdline-unset nosmt }
    if "retbleed=stuff" not-in $extra { cmdline-unset retbleed }
}
