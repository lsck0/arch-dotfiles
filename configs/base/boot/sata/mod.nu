use module.nu *
export use ../scripts/boot.nu [cmdline-set cmdline-unset]

export const meta = {native_only: [system]}

export const options = {
    probe: {
        type: bool
        default: true
        doc: ("Probe the SATA ports at boot; false on a machine without SATA disks keeps the built-in AHCI driver "
            + "from loading (0.3 s per empty port with staggered spin-up), and a SATA disk added later stays "
            + "invisible until this is true again")
        label: "Probe SATA ports"
        apply: reboot
    }
}

const BLACKLIST_KEY = "initcall_blacklist"
# the kernel has ahci built in, so there is no module to blacklist
const AHCI_INITCALL = "ahci_pci_driver_init"

export def system [cfg: record] {
    if $cfg.probe { step cmdline-unset $BLACKLIST_KEY } else { step cmdline-set $"($BLACKLIST_KEY)=($AHCI_INITCALL)" }
}
