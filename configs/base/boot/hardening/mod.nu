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
